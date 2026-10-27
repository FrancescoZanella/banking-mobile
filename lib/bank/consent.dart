/// Collegamento e rinnovo delle banche: `state` monouso, sessione, aggancio dei conti.
library;

import 'dart:convert';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../core/config.dart';
import '../core/dates.dart';

/// `state` casuale da 32 byte (come `secrets.token_urlsafe(32)`).
String newState([Random? random]) {
  final r = random ?? Random.secure();
  return base64Url.encode(List.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
}

double _epochSeconds(DateTime now) => now.millisecondsSinceEpoch / 1000;

/// Confronto a tempo costante, per non rivelare quanti caratteri coincidono.
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

/// Chiave della banca: quella già esistente o uno slug nome-paese.
Future<String> bankKeyFor(DatabaseExecutor db, Map<String, dynamic> aspsp) async {
  final rows = await db.query('banks',
      columns: ['key'], where: 'aspsp_name = ? AND country = ?', whereArgs: [aspsp['name'], aspsp['country']]);
  if (rows.isNotEmpty) return rows.first['key'] as String;
  final slug = (aspsp['name'] as String)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '$slug-${(aspsp['country'] as String).toLowerCase()}';
}

/// Registra un collegamento in corso (scade dopo 20 minuti).
Future<void> savePending(DatabaseExecutor db, String state, String bankKey, Map<String, dynamic> aspsp,
    {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final ttl = AppConfig.pendingAuthorizationTtl.inSeconds;
  await db.rawDelete('DELETE FROM pending_auth WHERE created_at < ?', [_epochSeconds(n) - ttl]);
  await db.insert('pending_auth', {
    'state': state,
    'bank_key': bankKey,
    'aspsp_json': jsonEncode(aspsp),
    'created_at': _epochSeconds(n),
  });
}

/// Restituisce e consuma l'autorizzazione in attesa, se valida.
Future<Map<String, Object?>?> takePending(DatabaseExecutor db, String? state, {DateTime? now}) async {
  if (state == null || state.isEmpty) return null;
  final n = now ?? DateTime.now();
  for (final row in await db.query('pending_auth')) {
    if (constantTimeEquals(row['state'] as String, state)) {
      await db.delete('pending_auth', where: 'state = ?', whereArgs: [row['state']]);
      final age = _epochSeconds(n) - (row['created_at'] as num);
      return age <= AppConfig.pendingAuthorizationTtl.inSeconds ? row : null;
    }
  }
  return null;
}

/// Registra il consenso e collega i conti restituiti a quelli già noti.
Future<List<int>> saveSession(DatabaseExecutor db, String bankKey, Map<String, dynamic> session) async {
  final now = utcNow();
  final access = (session['access'] as Map?) ?? {};
  await db.rawUpdate(
      "UPDATE consents SET status = 'replaced' WHERE bank_key = ? AND status = 'active'", [bankKey]);
  final consentId = await db.insert('consents', {
    'bank_key': bankKey,
    'session_id': session['session_id'],
    'valid_until': access['valid_until'] ?? now,
    'status': 'active',
    'created_at': now,
  });
  return linkAccounts(db, bankKey, consentId,
      [for (final a in (session['accounts'] as List? ?? [])) Map<String, dynamic>.from(a as Map)]);
}

/// Associa i conti della sessione a quelli già noti (o li crea).
///
/// Un conto è identificato da IBAN + valuta: alcune banche, per esempio, espongono
/// un conto per ogni valuta (EUR, GBP, …) tutti con lo stesso IBAN.
Future<List<int>> linkAccounts(
    DatabaseExecutor db, String bankKey, int consentId, List<Map<String, dynamic>> accounts) async {
  final now = utcNow();
  // Gli uid dei conti cambiano a ogni sessione: si sganciano i vecchi.
  await db.rawUpdate('UPDATE accounts SET uid = NULL WHERE bank_key = ?', [bankKey]);

  final accountIds = <int>[];
  for (final acc in accounts) {
    final uid = acc['uid'] as String?;
    if (uid == null || uid.isEmpty) continue;
    final rawIban = (((acc['account_id'] as Map?) ?? {})['iban'] as String? ?? '')
        .replaceAll(' ', '')
        .toUpperCase();
    final iban = rawIban.isEmpty ? null : rawIban;
    final currency = acc['currency'] as String?;
    final name = (acc['name'] ?? acc['product']) as String?;

    int? existing;
    if (iban != null) {
      final rows = await db.rawQuery(
          'SELECT id FROM accounts WHERE bank_key = ? AND iban = ? AND currency IS ?',
          [bankKey, iban, currency]);
      existing = rows.map((r) => r['id'] as int).where((id) => !accountIds.contains(id)).firstOrNull;
    }
    if (existing == null) {
      // Conti senza IBAN: si riaggancia solo se c'è un unico candidato.
      final candidates = [
        for (final r in await db.rawQuery(
            'SELECT id FROM accounts WHERE bank_key = ? AND iban IS NULL '
            'AND (currency = ? OR currency IS NULL)',
            [bankKey, currency]))
          if (!accountIds.contains(r['id'])) r['id'] as int,
      ];
      if (candidates.length == 1) existing = candidates.first;
    }

    if (existing != null) {
      await db.rawUpdate(
        'UPDATE accounts SET uid = ?, consent_id = ?, iban = coalesce(?, iban), '
        'name = coalesce(?, name), currency = coalesce(?, currency) WHERE id = ?',
        [uid, consentId, iban, name, currency, existing],
      );
      accountIds.add(existing);
    } else {
      accountIds.add(await db.insert('accounts', {
        'bank_key': bankKey,
        'uid': uid,
        'consent_id': consentId,
        'iban': iban,
        'name': name,
        'currency': currency,
        'created_at': now,
      }));
    }
  }
  return accountIds;
}

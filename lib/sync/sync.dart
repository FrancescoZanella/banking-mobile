/// Scaricamento movimenti e saldi.
///
/// - recupero storico: subito dopo il consenso, strategia "longest";
/// - incrementale: dall'ultimo movimento meno qualche giorno di sovrapposizione,
///   al massimo una volta ogni 12 ore per conto (limite PSD2).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../bank/enable_banking.dart';
import '../core/config.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../domain/categorize.dart';

/// Ordine di preferenza dei tipi di saldo ISO 20022 da mostrare.
const balancePreference = ['ITAV', 'CLAV', 'ITBD', 'CLBD', 'XPCD', 'OPAV', 'PRCD', 'OTHR'];

String? _name(Object? party) => (party is Map ? party['name'] as String? : null)?.nullIfEmpty;

String? _iban(Object? acc) {
  final iban = (acc is Map ? acc['iban'] as String? : null) ?? '';
  final clean = iban.replaceAll(' ', '').toUpperCase();
  return clean.isEmpty ? null : clean;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Id stabile del movimento: transaction_id, entry_reference oppure un hash.
String transactionKey(int accountId, Map<String, dynamic> tx) {
  final transactionId = tx['transaction_id'];
  if (transactionId != null && '$transactionId'.isNotEmpty) return '$accountId|t|$transactionId';
  final entryReference = tx['entry_reference'];
  if (entryReference != null && '$entryReference'.isNotEmpty) return '$accountId|e|$entryReference';
  final amount = (tx['transaction_amount'] as Map?) ?? {};
  final parts = [
    tx['booking_date'] ?? tx['transaction_date'] ?? tx['value_date'],
    amount['amount'],
    amount['currency'],
    tx['credit_debit_indicator'],
    _name(tx['creditor']),
    _name(tx['debtor']),
    ((tx['remittance_information'] as List?) ?? []).join('|'),
  ];
  final digest = sha256.convert(utf8.encode(jsonEncode(parts))).toString().substring(0, 32);
  return '$accountId|h|$digest';
}

Map<String, Object?> normalize(int accountId, Map<String, dynamic> tx) {
  final amount = (tx['transaction_amount'] as Map?) ?? {};
  final cents = toCents(amount['amount'], tx['credit_debit_indicator'] as String?);
  final outgoing = cents < 0;
  final remittance = ((tx['remittance_information'] as List?) ?? []).join(' ');
  return {
    'id': transactionKey(accountId, tx),
    'account_id': accountId,
    'booking_date': tx['booking_date'] ?? tx['transaction_date'] ?? tx['value_date'],
    'value_date': tx['value_date'],
    'amount_cents': cents,
    'currency': amount['currency'],
    'status': tx['status'] ?? 'BOOK',
    'counterparty': _name(outgoing ? tx['creditor'] : tx['debtor']),
    'counterparty_iban': _iban(outgoing ? tx['creditor_account'] : tx['debtor_account']),
    'description': remittance.isNotEmpty ? remittance : tx['note'],
    'mcc': tx['merchant_category_code'],
    'raw_json': jsonEncode(tx),
  };
}

/// Inserisce/aggiorna i movimenti; restituisce quanti sono nuovi.
///
/// I movimenti in attesa (PDNG) della finestra vengono rimossi prima: la banca
/// li restituisce di nuovo se sono ancora in attesa, oppure come contabilizzati.
/// La categoria scelta a mano e la notifica già inviata passano al movimento
/// che li sostituisce (vedi [_replacementOf]).
///
/// Con [markNotified] i movimenti nuovi risultano già notificati: si usa per lo
/// storico di una banca appena collegata o rinnovata.
Future<int> storeTransactions(DatabaseExecutor db, int accountId,
    List<Map<String, dynamic>> transactions, String windowFrom, {String? markNotified}) async {
  final pending = [
    ...await db.rawQuery(
      'SELECT id, amount_cents, counterparty, description, booking_date, category_id, '
      "category_source, is_internal, notified_at FROM transactions WHERE account_id = ? AND status = 'PDNG' "
      'AND (booking_date IS NULL OR booking_date >= ?)',
      [accountId, windowFrom],
    ),
  ];
  await db.rawDelete(
    "DELETE FROM transactions WHERE account_id = ? AND status = 'PDNG' "
    'AND (booking_date IS NULL OR booking_date >= ?)',
    [accountId, windowFrom],
  );
  final now = utcNow();
  var added = 0;
  for (final raw in transactions) {
    final tx = normalize(accountId, raw);
    final id = tx['id'];
    final exists = (await db.rawQuery('SELECT 1 FROM transactions WHERE id = ?', [id])).isNotEmpty;
    if (exists) {
      final changes = Map.of(tx)
        ..remove('id')
        ..remove('account_id');
      await db.update('transactions', {...changes, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
    } else {
      final previous = _replacementOf(tx, pending);
      await db.insert('transactions', {
        ...tx,
        'created_at': now,
        'updated_at': now,
        'notified_at': previous?['notified_at'] ?? markNotified,
        if (previous?['category_source'] == 'manual') ...{
          'category_id': previous!['category_id'],
          'category_source': 'manual',
          'is_internal': previous['is_internal'],
        },
      });
      added++;
    }
  }
  return added;
}

/// Il movimento in attesa che [tx] sostituisce, se c'è (e lo toglie da [pending]):
/// stesso id (ancora in attesa) oppure, perché molte banche cambiano id alla
/// contabilizzazione, stesso importo e stessa controparte entro 7 giorni.
Map<String, Object?>? _replacementOf(Map<String, Object?> tx, List<Map<String, Object?>> pending) {
  String party(Map<String, Object?> t) =>
      ((t['counterparty'] ?? t['description']) as String? ?? '').trim().toLowerCase();
  bool near(Map<String, Object?> t) {
    final a = parseIsoDay(t['booking_date'] as String?), b = parseIsoDay(tx['booking_date'] as String?);
    return a == null || b == null || daysBetween(a, b).abs() <= 7;
  }

  var i = pending.indexWhere((p) => p['id'] == tx['id']);
  if (i < 0) {
    i = pending.indexWhere((p) =>
        p['amount_cents'] == tx['amount_cents'] && party(p).isNotEmpty && party(p) == party(tx) && near(p));
  }
  return i < 0 ? null : pending.removeAt(i);
}

Future<void> storeBalances(DatabaseExecutor db, int accountId, List<Map<String, dynamic>> balances) async {
  final now = utcNow();
  for (final b in balances) {
    final amount = (b['balance_amount'] as Map?) ?? {};
    if (amount['amount'] == null) continue;
    await db.insert('balances', {
      'account_id': accountId,
      'balance_type': b['balance_type'],
      'amount_cents': toCents(amount['amount']),
      'currency': amount['currency'],
      'reference_date': b['reference_date'],
      'fetched_at': now,
    });
  }
}

bool consentIsUsable(Map<String, Object?>? consent, [DateTime? now]) {
  if (consent == null || consent['status'] != 'active') return false;
  final until = DateTime.parse(consent['valid_until'] as String);
  return until.isAfter((now ?? DateTime.now()).toUtc());
}

bool isDue(Map<String, Object?> account, [DateTime? now]) {
  final last = account['last_sync_at'] as String?;
  if (last == null || last.isEmpty) return true;
  return (now ?? DateTime.now()).toUtc().difference(DateTime.parse(last)) >= AppConfig.minSyncInterval;
}

class SyncResult {
  SyncResult(this.accountId, {this.ok = true, this.added = 0, this.error});
  final int accountId;
  bool ok;
  int added;
  String? error;
}

Future<SyncResult> syncAccount(Database db, EnableBankingApi api, Map<String, Object?> account,
    {bool backfill = false, DateTime? now}) async {
  final accountId = account['id'] as int;
  final consents = await db.query('consents', where: 'id = ?', whereArgs: [account['consent_id']]);
  final consent = consents.isEmpty ? null : consents.first;
  if (!consentIsUsable(consent, now)) {
    return SyncResult(accountId, ok: false, error: 'consenso scaduto');
  }

  final t = today(now);
  final lastRow = await db.rawQuery(
      'SELECT max(booking_date) AS d FROM transactions WHERE account_id = ?', [accountId]);
  final last = parseIsoDay(lastRow.first['d'] as String?);
  final String dateFrom;
  final String strategy;
  if (backfill || last == null) {
    dateFrom = iso(addDays(t, -AppConfig.backfillDays));
    strategy = 'longest';
  } else {
    dateFrom = iso(addDays(last, -AppConfig.overlapDays));
    strategy = 'default';
  }

  final started = utcNow(now);
  final result = SyncResult(accountId);
  try {
    final uid = account['uid'] as String;
    final txs = await api.getTransactions(uid, dateFrom, dateTo: iso(t), strategy: strategy);
    final balances = await api.getBalances(uid);
    await db.transaction((txn) async {
      result.added = await storeTransactions(txn, accountId, txs, dateFrom,
          markNotified: strategy == 'longest' ? 'storico' : null);
      await storeBalances(txn, accountId, balances);
      await txn.update('accounts', {'last_sync_at': utcNow(now)}, where: 'id = ?', whereArgs: [accountId]);
    });
  } on EnableBankingError catch (e) {
    result
      ..ok = false
      ..error = e.toString();
    if (e.isConsentProblem && consent != null) {
      await db.update('consents', {'status': 'expired'}, where: 'id = ?', whereArgs: [consent['id']]);
    }
  } catch (e) {
    // Rete, paginazione, dati inattesi.
    result
      ..ok = false
      ..error = e is AppError ? e.message : '${e.runtimeType}: $e';
  }

  await db.insert('sync_runs', {
    'account_id': accountId,
    'kind': strategy == 'longest' ? 'backfill' : 'incremental',
    'started_at': started,
    'ok': result.ok ? 1 : 0,
    'n_new': result.added,
    'error': result.error,
  });
  return result;
}

Future<List<SyncResult>> syncAll(Database db, EnableBankingApi api,
    {bool onlyDue = true, Set<int>? accountIds, bool backfill = false, DateTime? now}) async {
  final accounts = await db.query('accounts', where: 'uid IS NOT NULL');
  final results = <SyncResult>[];
  for (final account in accounts) {
    if (accountIds != null && !accountIds.contains(account['id'])) continue;
    if (onlyDue && !isDue(account, now)) continue;
    results.add(await syncAccount(db, api, account, backfill: backfill, now: now));
  }
  if (results.any((r) => r.ok && r.added > 0) || backfill) {
    await db.transaction((txn) => recategorize(txn));
  }
  return results;
}

/// Tra gli ultimi saldi di un conto sceglie il tipo più significativo.
Map<String, Object?>? preferredBalance(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return null;
  int rank(Map<String, Object?> r) {
    final i = balancePreference.indexOf(r['balance_type'] as String? ?? '');
    return i < 0 ? balancePreference.length : i;
  }

  return rows.reduce((a, b) => rank(b) < rank(a) ? b : a);
}

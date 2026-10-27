/// Azioni della pagina Conti: collega, rinnova, ritorno dalla banca, scollega,
/// elimina, rinomina, nascondi, sincronizza. Stessi passaggi e stessi messaggi
/// della versione web (consent.py e routes/accounts.py).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/config.dart';
import '../domain/categorize.dart';
import '../sync/sync.dart';
import 'consent.dart';
import 'enable_banking.dart';

/// Esito da mostrare all'utente (l'equivalente dei messaggi flash del web).
class Flash {
  const Flash(this.text, {this.ok = true});
  final String text;
  final bool ok;
}

/// Avvio di un collegamento: o l'indirizzo della banca da aprire, o un errore.
class AuthStart {
  const AuthStart.url(String this.url) : error = null;
  const AuthStart.error(String this.error) : url = null;
  final String? url;
  final String? error;
}

bool _isCatalogError(Object e) => e is AppError || e is EnableBankingError || e is TimeoutException;

/// Una sola sincronizzazione alla volta (come background.py del web).
class SyncRunner extends ChangeNotifier {
  SyncRunner(this._db, this._api);

  final Database _db;
  final EnableBankingApi _api;
  Future<List<SyncResult>>? _running;

  bool get running => _running != null;

  /// Avvisa le pagine aperte che i dati sono cambiati (es. banca collegata).
  void notifyChanged() => notifyListeners();

  /// Avvia una sincronizzazione. Con [waitForLock] attende quella in corso
  /// invece di rinunciare (serve al recupero storico dopo un collegamento).
  Future<List<SyncResult>?> start(
      {bool onlyDue = true, Set<int>? accountIds, bool backfill = false, bool waitForLock = false}) async {
    while (_running != null) {
      if (!waitForLock) return null;
      await _running;
    }
    final job = syncAll(_db, _api, onlyDue: onlyDue, accountIds: accountIds, backfill: backfill);
    _running = job;
    notifyListeners();
    try {
      return await job;
    } finally {
      _running = null;
      notifyListeners();
    }
  }
}

class BankService {
  BankService(this.db, this.api, this.sync);

  final Database db;
  final EnableBankingApi api;
  final SyncRunner sync;

  /// Nomi del catalogo italiano in ordine alfabetico; null se non disponibile.
  Future<List<String>?> catalogNames() async {
    try {
      final names = [for (final a in await api.listAspsps(AppConfig.country)) a['name'] as String]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return names;
    } catch (e) {
      if (_isCatalogError(e)) return null; // la pagina mostra un avviso al posto del menu
      rethrow;
    }
  }

  /// Collega una banca nuova scelta dal menu.
  Future<AuthStart> connectNew(String name) async {
    if (name.isEmpty) return const AuthStart.error('Scegli la banca da collegare.');
    final Map<String, dynamic>? aspsp;
    try {
      // Il nome arriva dal menu, ma si valida comunque contro il catalogo.
      aspsp = await api.getAspsp(name, AppConfig.country);
    } catch (e) {
      if (_isCatalogError(e)) return AuthStart.error('Lettura del catalogo non riuscita: $e');
      rethrow;
    }
    if (aspsp == null) {
      return const AuthStart.error('Banca non trovata nel catalogo di Enable Banking: ricarica la pagina.');
    }
    // La banca viene salvata solo al ritorno, se il login va a buon fine.
    return _startConsent(await bankKeyFor(db, aspsp), aspsp, aspsp['name'] as String);
  }

  /// Rinnova (o ricollega) una banca già presente.
  Future<AuthStart> connectExisting(String bankKey) async {
    final rows = await db.query('banks', where: 'key = ?', whereArgs: [bankKey]);
    if (rows.isEmpty) return const AuthStart.error('Banca non trovata.');
    final bank = rows.first;
    final Map<String, dynamic>? aspsp;
    try {
      aspsp = await api.getAspsp(bank['aspsp_name'] as String? ?? '', bank['country'] as String? ?? '');
    } catch (e) {
      if (_isCatalogError(e)) return AuthStart.error('Avvio collegamento non riuscito: $e');
      rethrow;
    }
    if (aspsp == null) {
      return AuthStart.error('Avvio collegamento non riuscito: ${bank['label']} non è più nel catalogo di Enable Banking.');
    }
    return _startConsent(bankKey, aspsp, bank['label'] as String);
  }

  Future<AuthStart> _startConsent(String bankKey, Map<String, dynamic> aspsp, String label) async {
    final state = newState();
    final String url;
    try {
      await api.checkApplication();
      url = await api.startAuth(aspsp, state);
    } on EnableBankingError catch (e) {
      return AuthStart.error('Enable Banking ha rifiutato il collegamento a $label ($e). '
          'Verifica che la banca sia collegata alla tua app nel Control Panel.');
    } catch (e) {
      if (_isCatalogError(e)) return AuthStart.error('Avvio collegamento non riuscito: $e');
      rethrow;
    }
    await savePending(db, state, bankKey, aspsp);
    await db.update('banks', {'aspsp_name': aspsp['name'], 'country': aspsp['country']},
        where: 'key = ?', whereArgs: [bankKey]);
    if (!url.startsWith('https://')) {
      return const AuthStart.error("URL di autorizzazione non valido ricevuto dall'API.");
    }
    return AuthStart.url(url);
  }

  /// Ritorno dalla banca (deep link bankingmobile://callback?state&code…).
  Future<Flash> handleCallback(Uri uri) async {
    if (uri.scheme != AppConfig.callbackScheme || uri.host != AppConfig.callbackHost) {
      return const Flash('Indirizzo di ritorno non riconosciuto.', ok: false);
    }
    final query = uri.queryParameters;
    final pending = await takePending(db, query['state']);
    if (pending == null) {
      return const Flash('Ritorno dalla banca rifiutato: richiesta assente o scaduta. Riprova.', ok: false);
    }
    final code = query['code'];
    if ((query['error'] ?? '').isNotEmpty || code == null || code.isEmpty) {
      final reason = query['error_description'] ?? query['error'] ?? 'nessun codice';
      return Flash(
          'Autorizzazione non completata: $reason. Se è una banca nuova, verifica che sia collegata '
          'alla tua app nel Control Panel di Enable Banking.',
          ok: false);
    }

    final bankKey = pending['bank_key'] as String;
    final aspsp = Map<String, dynamic>.from(jsonDecode(pending['aspsp_json'] as String) as Map);
    final List<int> accountIds;
    try {
      final session = await api.createSession(code);
      if ((session['session_id'] as String?)?.isNotEmpty != true) {
        throw AppError('La risposta API non contiene session_id.');
      }
      final accounts = (session['accounts'] as List? ?? []);
      if (!accounts.any((a) => ((a as Map)['uid'] as String?)?.isNotEmpty == true)) {
        // Tipico della modalità limitata: login riuscito ma conto non collegato
        // all'app. Non si salva nulla, così un rinnovo andato a vuoto non sgancia
        // i conti che funzionano già.
        return Flash(
            'Il login con ${aspsp['name']} è riuscito, ma Enable Banking non ha restituito nessun conto. '
            'La tua app è in modalità limitata: puoi leggere solo i conti che hai collegato nel '
            'Control Panel di Enable Banking. Collega lì il conto di questa banca e poi riprova da qui.',
            ok: false);
      }
      accountIds = await db.transaction((txn) async {
        // Solo ora, a login riuscito, una banca nuova entra fra le tue.
        await txn.rawInsert(
          'INSERT OR IGNORE INTO banks (key, label, aspsp_name, country) VALUES (?, ?, ?, ?)',
          [bankKey, aspsp['name'], aspsp['name'], aspsp['country']],
        );
        return saveSession(txn, bankKey, session);
      });
    } catch (e) {
      if (_isCatalogError(e)) return Flash('Collegamento non completato: $e', ok: false);
      rethrow;
    }

    final label = (await db.query('banks', where: 'key = ?', whereArgs: [bankKey])).first['label'];
    // Il recupero storico può durare minuti: gira in background e attende
    // l'eventuale sincronizzazione già in corso invece di essere saltato.
    unawaited(sync.start(onlyDue: false, accountIds: accountIds.toSet(), backfill: true, waitForLock: true));
    return Flash('$label collegata: ${accountIds.length} conti. Importazione dello storico completo '
        'in corso (può richiedere qualche minuto).');
  }

  /// Revoca su Enable Banking i consensi attivi e sgancia i conti.
  Future<void> _revoke(String bankKey) async {
    for (final consent in await db.query('consents',
        where: "bank_key = ? AND status = 'active'", whereArgs: [bankKey])) {
      await api.deleteSession(consent['session_id'] as String);
      await db.update('consents', {'status': 'revoked'}, where: 'id = ?', whereArgs: [consent['id']]);
    }
    await db.rawUpdate('UPDATE accounts SET uid = NULL WHERE bank_key = ?', [bankKey]);
  }

  Future<Flash> disconnect(String bankKey) async {
    final bank = (await db.query('banks', where: 'key = ?', whereArgs: [bankKey])).firstOrNull;
    if (bank == null) return const Flash('Banca non trovata.', ok: false);
    try {
      await _revoke(bankKey);
    } catch (e) {
      if (_isCatalogError(e)) return Flash('Scollegamento non riuscito: $e', ok: false);
      rethrow;
    }
    return Flash('${bank['label']} scollegata: il consenso è stato revocato e non arriveranno '
        'nuovi movimenti. Lo storico resta nella dashboard.');
  }

  Future<Flash> deleteBank(String bankKey, String typedName) async {
    final bank = (await db.query('banks', where: 'key = ?', whereArgs: [bankKey])).firstOrNull;
    if (bank == null) return const Flash('Banca non trovata.', ok: false);
    final label = bank['label'] as String;
    if (typedName.trim().toLowerCase() != label.toLowerCase()) {
      return Flash('Per eliminare scrivi esattamente il nome «$label».', ok: false);
    }
    if (sync.running) return const Flash('Sincronizzazione in corso: riprova tra qualche istante.', ok: false);
    try {
      await _revoke(bankKey);
    } catch (e) {
      if (_isCatalogError(e)) {
        return Flash('Eliminazione annullata: revoca del consenso non riuscita ($e).', ok: false);
      }
      rethrow;
    }
    await db.transaction((txn) async {
      const accounts = 'SELECT id FROM accounts WHERE bank_key = ?';
      for (final table in ['sync_runs', 'balances', 'transactions']) {
        await txn.rawDelete('DELETE FROM $table WHERE account_id IN ($accounts)', [bankKey]);
      }
      for (final table in ['accounts', 'consents', 'pending_auth']) {
        await txn.delete(table, where: 'bank_key = ?', whereArgs: [bankKey]);
      }
      await txn.delete('banks', where: 'key = ?', whereArgs: [bankKey]);
      // Senza questi conti alcuni giroconti non hanno più la controparte.
      await recategorize(txn);
    });
    return Flash('$label eliminata insieme a conti, movimenti e saldi.');
  }

  Future<void> setNickname(int accountId, String value) async {
    final trimmed = value.trim();
    await db.update('accounts', {'nickname': trimmed.isEmpty ? null : trimmed.substring(0, trimmed.length.clamp(0, 40))},
        where: 'id = ?', whereArgs: [accountId]);
  }

  /// Un conto nascosto continua a sincronizzarsi, ma non entra nei totali.
  Future<void> toggleHidden(int accountId) =>
      db.rawUpdate('UPDATE accounts SET hidden = 1 - hidden WHERE id = ?', [accountId]);

  /// Rispetta comunque l'intervallo minimo: protegge il limite PSD2.
  Future<Flash> syncNow() async {
    if (sync.running) return const Flash('Una sincronizzazione è già in corso.', ok: false);
    unawaited(sync.start(onlyDue: true));
    return Flash('Sincronizzazione avviata per i conti non aggiornati da più di '
        '${AppConfig.minSyncInterval.inHours} ore.');
  }
}

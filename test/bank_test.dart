// Parità con i test delle banche di tests/test_web.py (collegamento, ritorno
// dalla banca, scollega, elimina, stati della pagina Conti).
import 'dart:async';

import 'package:bankingmobile/app/app.dart';
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/bank/bank_service.dart';
import 'package:bankingmobile/bank/enable_banking.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/security/app_lock.dart';
import 'package:bankingmobile/sync/background.dart';
import 'package:bankingmobile/domain/reports.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'security_test.dart' show FakeAuth;
import 'support.dart';

const catalog = [
  {'name': 'Banca Gamma', 'country': 'IT', 'maximum_consent_validity': 15552000},
  {'name': 'Banca Beta', 'country': 'IT', 'maximum_consent_validity': 15552000},
  {'name': 'Banca Alfa', 'country': 'IT', 'maximum_consent_validity': 15552000},
  {'name': 'Zeta', 'country': 'IT', 'maximum_consent_validity': 15552000},
];

/// Banca finta: registra le chiamate come i monkeypatch dei test web.
class FakeApi implements EnableBankingApi {
  final started = <(String, String)>[];
  final revoked = <String>[];
  Map<String, dynamic> Function(String code)? session;
  bool catalogBroken = false;

  @override
  Future<Map<String, dynamic>> checkApplication() async => {};

  @override
  Future<List<Map<String, dynamic>>> listAspsps(String country) async {
    if (catalogBroken) throw EnableBankingError('Lettura catalogo fallita', 503);
    return [for (final a in catalog) Map<String, dynamic>.from(a)];
  }

  @override
  Future<Map<String, dynamic>?> getAspsp(String name, String country) async {
    for (final a in await listAspsps(country)) {
      if (a['name'] == name) return a;
    }
    return null;
  }

  @override
  Future<String> startAuth(Map<String, dynamic> aspsp, String state) async {
    started.add((aspsp['name'] as String, state));
    return 'https://tilisy.enablebanking.com/x';
  }

  @override
  Future<Map<String, dynamic>> createSession(String code) async => session!(code);

  @override
  Future<void> deleteSession(String sessionId) async => revoked.add(sessionId);

  @override
  Future<List<Map<String, dynamic>>> getBalances(String uid) async => [];

  @override
  Future<List<Map<String, dynamic>>> getTransactions(String uid, String dateFrom,
          {String? dateTo, String strategy = 'default'}) async =>
      [];
}

Map<String, dynamic> emptySession(String _) =>
    {'session_id': 'sess-vuota', 'access': {'valid_until': '2027-04-24T10:00:00Z'}, 'accounts': []};

void main() {
  late Database db;
  late FakeApi api;
  late BankService bank;

  setUp(() async {
    db = await openTestDb();
    // Il DB di test parte con Zeta e Theta: qui le banche le crea ogni test.
    await db.delete('banks');
    api = FakeApi();
    bank = BankService(db, api, SyncRunner(db, api));
  });
  tearDown(() => db.close());

  Future<Set<String>> bankKeys() async => {for (final r in await db.query('banks')) r['key'] as String};
  Uri callback(String query) => Uri.parse('bankingmobile://callback?$query');

  test('catalogo nel menu, in ordine; errore del catalogo → null (avviso in pagina)', () async {
    expect(await bank.catalogNames(), ['Banca Alfa', 'Banca Beta', 'Banca Gamma', 'Zeta']);
    api.catalogBroken = true;
    expect(await bank.catalogNames(), isNull);
  });

  test('banca fuori catalogo rifiutata (solo nome esatto)', () async {
    expect((await bank.connectNew('Banca Inesistente')).error, contains('Banca non trovata nel catalogo'));
    expect((await bank.connectNew('banca beta')).error, contains('Banca non trovata nel catalogo'));
    expect(api.started, isEmpty);
    expect(await bankKeys(), isEmpty);
  });

  test('banca nuova salvata solo dopo il login riuscito', () async {
    final start = await bank.connectNew('Banca Gamma');
    expect(start.url, 'https://tilisy.enablebanking.com/x');
    expect(api.started.single.$1, 'Banca Gamma');
    expect(await bankKeys(), isNot(contains('banca-gamma-it')));

    api.session = (code) => {
          'session_id': 'sess-gamma',
          'access': {'valid_until': '2027-04-24T10:00:00Z'},
          'accounts': [
            {'uid': 'u-int', 'account_id': {'iban': 'IT99Z'}, 'currency': 'EUR'},
          ],
        };
    final flash = await bank.handleCallback(callback('state=${api.started.single.$2}&code=abc'));
    expect(flash.text, startsWith('Banca Gamma collegata: 1 conti'));
    expect(await bankKeys(), contains('banca-gamma-it'));
    await bank.sync.start(waitForLock: true); // attende il recupero storico avviato
  });

  test('login fallito non lascia nulla', () async {
    await bank.connectNew('Banca Beta');
    final flash = await bank.handleCallback(callback('state=${api.started.single.$2}&error=access_denied'));
    expect(flash.ok, isFalse);
    expect(flash.text, contains('Autorizzazione non completata: access_denied'));
    expect(await bankKeys(), isNot(contains('banca-beta-it')));
  });

  test('banca già nota riusa la sua chiave', () async {
    await addBank(db, 'zeta'); // già collegata in passato, con la sua chiave
    await bank.connectNew('Zeta');
    expect(await scalar(db, 'SELECT bank_key FROM pending_auth'), 'zeta');
  });

  test('nessun conto restituito → spiega il Control Panel, non salva nulla', () async {
    api.session = emptySession;
    await bank.connectNew('Banca Alfa');
    final flash = await bank.handleCallback(callback('state=${api.started.single.$2}&code=abc'));
    expect(flash.text, allOf(contains('non ha restituito nessun conto'), contains('Control Panel')));
    expect(await bankKeys(), isNot(contains('banca-alfa-it')));
  });

  test('rinnovo a vuoto non sgancia i conti che funzionano', () async {
    api.session = emptySession;
    final acc = await addAccount(db, bankKey: 'zeta', uid: 'uid-ok', iban: 'IT00X1');
    await bank.connectNew('Zeta');
    await bank.handleCallback(callback('state=${api.started.single.$2}&code=abc'));
    expect(await scalar(db, 'SELECT uid FROM accounts WHERE id = ?', [acc]), 'uid-ok');
    expect((await db.query('consents')).map((r) => r['status']), ['active']);
  });

  test('ritorno con state sconosciuto, già usato o con schema estraneo: rifiutato', () async {
    expect((await bank.handleCallback(callback('state=nope&code=abc'))).text, contains('rifiutato'));
    await bank.connectNew('Banca Beta');
    api.session = emptySession;
    final state = api.started.single.$2;
    await bank.handleCallback(callback('state=$state&code=abc'));
    expect((await bank.handleCallback(callback('state=$state&code=abc'))).text, contains('rifiutato')); // monouso
    final foreign = await bank.handleCallback(Uri.parse('https://evil.example/callback?state=$state&code=abc'));
    expect(foreign.ok, isFalse);
  });

  Future<(int, int)> twoBanks() async {
    final zeta = await addAccount(db, bankKey: 'zeta', uid: 'u-zeta', iban: 'IT11');
    final theta = await addAccount(db, bankKey: 'theta', uid: 'u-theta', iban: 'IT02');
    await storeTransactions(db, zeta, [tx('10', ref: 'r1', day: '2026-10-02')], '2026-01-01');
    await storeTransactions(db, theta, [tx('20', ref: 'f1', day: '2026-10-03')], '2026-01-01');
    return (zeta, theta);
  }

  test('scollega: revoca il consenso e tiene lo storico', () async {
    final (zeta, _) = await twoBanks();
    final flash = await bank.disconnect('zeta');
    expect(flash.text, contains('scollegata'));
    expect(api.revoked, ['sess-u-zeta']);
    expect(await scalar(db, 'SELECT uid FROM accounts WHERE id = ?', [zeta]), isNull);
    expect(await scalar(db, "SELECT status FROM consents WHERE bank_key = 'zeta'"), 'revoked');
    expect(await scalar(db, 'SELECT count(*) FROM transactions WHERE account_id = ?', [zeta]), 1);
    // Una revoca voluta non genera l'avviso "consenso scaduto".
    expect((await consentAlerts(db)).where((a) => a.key == 'zeta'), isEmpty);
  });

  test('elimina solo scrivendo il nome esatto, e solo quella banca', () async {
    final (zeta, theta) = await twoBanks();
    await bank.deleteBank('zeta', 'Zet');
    expect(api.revoked, isEmpty);
    expect(await scalar(db, "SELECT count(*) FROM banks WHERE key = 'zeta'"), 1);

    await bank.deleteBank('zeta', ' zeta ');
    expect(api.revoked, ['sess-u-zeta']);
    for (final (table, column) in [('banks', 'key'), ('consents', 'bank_key'), ('accounts', 'bank_key')]) {
      expect(await scalar(db, "SELECT count(*) FROM $table WHERE $column = 'zeta'"), 0);
    }
    expect(await scalar(db, 'SELECT count(*) FROM transactions WHERE account_id = ?', [zeta]), 0);
    // Theta non viene toccata.
    expect(await scalar(db, 'SELECT count(*) FROM transactions WHERE account_id = ?', [theta]), 1);
  });

  test('rinomina (max 40 caratteri, vuoto = nome della banca) e nascondi', () async {
    final (zeta, _) = await twoBanks();
    await bank.setNickname(zeta, '  Conto principale  ');
    expect(await scalar(db, 'SELECT nickname FROM accounts WHERE id = ?', [zeta]), 'Conto principale');
    await bank.setNickname(zeta, 'x' * 60);
    expect((await scalar(db, 'SELECT nickname FROM accounts WHERE id = ?', [zeta]) as String).length, 40);
    await bank.setNickname(zeta, '   ');
    expect(await scalar(db, 'SELECT nickname FROM accounts WHERE id = ?', [zeta]), isNull);
    await bank.toggleHidden(zeta);
    expect(await scalar(db, 'SELECT hidden FROM accounts WHERE id = ?', [zeta]), 1);
    await bank.toggleHidden(zeta);
    expect(await scalar(db, 'SELECT hidden FROM accounts WHERE id = ?', [zeta]), 0);
  });

  test('indirizzi di ritorno: solo deep link e App Link della pagina di ritorno', () {
    expect(isCallbackUri(Uri.parse('bankingmobile://callback?state=a&code=b')), isTrue);
    expect(isCallbackUri(Uri.parse('https://francescozanella.github.io/banking/?state=a&code=b')), isTrue);
    expect(isCallbackUri(Uri.parse('https://francescozanella.github.io/banking/privacy.html')), isFalse);
    expect(isCallbackUri(Uri.parse('https://francescozanella.github.io/bankingx/?state=a')), isFalse);
    expect(isCallbackUri(Uri.parse('https://francescozanella.github.io/Bankrelay/app/?state=a')), isFalse); // vecchio indirizzo
    expect(isCallbackUri(Uri.parse('https://evil.example/banking/?state=a')), isFalse);
    expect(isCallbackUri(Uri.parse('http://francescozanella.github.io/banking/?state=a')), isFalse);
    expect(isCallbackUri(Uri.parse('bankingmobile://altro?state=a')), isFalse);
  });

  test('notifica dei consensi: solo nomi e giorni, mai importi', () {
    final text = consentNotificationText(const [
      ConsentAlert('a', 'Zeta', 0, expired: true),
      ConsentAlert('b', 'ThetaBank', 5, expired: false),
    ]);
    expect(text, 'Zeta scaduto; ThetaBank scade tra 5 giorni');
  });

  testWidgets('pagina Conti: stati dei consensi, conto nascosto, azioni', (tester) async {
    late (int, int) ids;
    await tester.runAsync(() async {
      ids = await twoBanks();
      await db.update('accounts', {'hidden': 1}, where: 'id = ?', whereArgs: [ids.$2]);
      await db.update('consents', {'valid_until': '2026-01-01T00:00:00Z'}, where: "bank_key = 'theta'");
    });
    final services = AppServices(
      db: db,
      secrets: MemorySecretStore(),
      api: api,
      pickPem: () async => null,
      openBankPage: (url) async => true,
    );
    // Schermo alto: tutte le schede banca vengono costruite.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Services(
      services: services,
      child: MaterialApp(home: const AccountsScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Consenso scaduto'), findsOneWidget);
    expect(find.textContaining('Consenso valido fino al'), findsOneWidget);
    expect(find.textContaining('nascosto'), findsOneWidget);
    expect(find.text('Scollega'), findsWidgets);
    expect(find.text('Elimina'), findsNWidgets(2));
    // Patrimonio: solo i conti visibili (nessun saldo nel test → 0).
    expect(find.byKey(const Key('net-worth')), findsOneWidget);
  });

  testWidgets('deep link di ritorno: esito mostrato nell\'app', (tester) async {
    final links = StreamController<Uri>();
    final services = AppServices(
      db: db,
      secrets: MemorySecretStore(),
      api: api,
      pickPem: () async => null,
      openBankPage: (url) async => true,
    );
    await tester.pumpWidget(BankingApp(services: services, lock: AppLock(FakeAuth()), links: links.stream));
    await settle(tester);
    await tester.runAsync(() async {
      links.add(Uri.parse('bankingmobile://callback?state=sconosciuto&code=x'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Ritorno dalla banca rifiutato'), findsOneWidget);
    await links.close();
  });
}

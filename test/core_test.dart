// Parità con tests/test_core.py della versione web.
import 'package:bankingmobile/bank/consent.dart';
import 'package:bankingmobile/bank/enable_banking.dart';
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/core/money.dart';
import 'package:bankingmobile/data/database.dart';
import 'package:bankingmobile/data/defaults.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  late Database db;
  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  test('to_cents', () {
    expect(toCents('12.34', 'DBIT'), -1234);
    expect(toCents('12.34', 'CRDT'), 1234);
    expect(toCents('-5.5'), -550);
    expect(toCents('0.005', 'CRDT'), 1);
    expect(toCents('1000', 'DBIT'), -100000);
  });

  test('dedup and pending replaced', () async {
    final acc = await addAccount(db);
    final first = [tx('10.00', ref: 'A'), tx('3.50', status: 'PDNG', day: '2026-10-05')];
    expect(await storeTransactions(db, acc, first, '2026-09-01'), 2);
    // Stesso movimento + il pending ora contabilizzato con un riferimento.
    final second = [tx('10.00', ref: 'A'), tx('3.50', ref: 'B', day: '2026-10-06')];
    expect(await storeTransactions(db, acc, second, '2026-09-01'), 1);
    final rows = await db.rawQuery('SELECT status FROM transactions ORDER BY id');
    expect(rows.map((r) => r['status']), ['BOOK', 'BOOK']);
  });

  test('categorization rules and manual override', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [
      tx('50', ref: '1', name: 'ESSELUNGA MILANO'),
      tx('9.99', ref: '2', name: 'Netflix.com'),
      tx('20', ref: '3', name: 'Sconosciuto'),
      tx('1500', indicator: 'CRDT', ref: '4', name: 'ACME SPA', remittance: ['Stipendio ottobre']),
    ], '2026-01-01');
    await recategorize(db);
    final names = {
      for (final r in await db.rawQuery(
          'SELECT t.id, c.name FROM transactions t JOIN categories c ON c.id = t.category_id'))
        r['id']: r['name'],
    };
    expect(names['$acc|e|1'], 'Spesa alimentare');
    expect(names['$acc|e|2'], 'Abbonamenti');
    expect(names['$acc|e|3'], 'Altre spese');
    expect(names['$acc|e|4'], 'Stipendio');

    final svago = await scalar(db, "SELECT id FROM categories WHERE name = 'Svago e viaggi'");
    await db.rawUpdate("UPDATE transactions SET category_id = ?, category_source = 'manual' WHERE id = ?",
        [svago, '$acc|e|1']);
    await recategorize(db);
    expect(await scalar(db, 'SELECT category_id FROM transactions WHERE id = ?', ['$acc|e|1']), svago);
  });

  test('internal transfers only by own iban', () async {
    final zeta = await addAccount(db, bankKey: 'zeta', uid: 'u1', iban: 'IT011');
    final theta = await addAccount(db, bankKey: 'theta', uid: 'u2', iban: 'IT002');
    await storeTransactions(db, theta, [
      tx('200', ref: 'f1', name: 'Me', iban: 'IT011', day: '2026-10-01'), // IBAN di un tuo conto
      tx('75', ref: 'f2', name: 'Me', day: '2026-10-10'), // solo importo uguale
    ], '2026-01-01');
    await storeTransactions(db, zeta, [
      tx('75', indicator: 'CRDT', ref: 'r2', name: 'Me', day: '2026-10-12'),
      tx('90', indicator: 'CRDT', ref: 'r3', name: 'X', day: '2026-10-12', remittance: ['giroconto']),
      tx('50', ref: 'r4', name: 'Cambio valuta', day: '2026-10-13'),
    ], '2026-01-01');
    await recategorize(db);
    final internal = {
      for (final r in await db.rawQuery('SELECT id FROM transactions WHERE is_internal = 1')) r['id'],
    };
    // Né l'abbinamento degli importi né il testo «giroconto» bastano.
    expect(internal, {'$theta|e|f1'});
  });

  test('migration removes rules towards transfers', () async {
    final giro = await scalar(db, "SELECT id FROM categories WHERE name = 'Giroconti'");
    await db.rawInsert(
        "INSERT INTO category_rules (category_id, field, pattern) VALUES (?, 'text', 'trasferimento')", [giro]);
    await setSetting(db, 'default_rules_version', '2');
    await initDb(db);
    expect(await scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [giro]), 0);
    expect(await scalar(db, 'SELECT count(*) FROM category_rules') as int, greaterThan(0)); // le altre restano
  });

  test('pending state validation', () async {
    final now = DateTime.now();
    await savePending(db, 'good', 'zeta', {}, now: now);
    await savePending(db, 'old', 'zeta', {}, now: now.subtract(const Duration(seconds: 99999)));
    expect(await takePending(db, ''), isNull);
    expect(await takePending(db, 'wrong'), isNull);
    expect(await takePending(db, 'old'), isNull); // scaduto
    expect((await takePending(db, 'good'))!['bank_key'], 'zeta');
    expect(await takePending(db, 'good'), isNull); // monouso
  });

  test('save session reuses account without iban', () async {
    final old = await addAccount(db, bankKey: 'zeta', uid: 'old-uid');
    final ids = await saveSession(db, 'zeta', {
      'session_id': 'new-session',
      'access': {'valid_until': '2027-04-20T10:00:00Z'},
      'accounts': [
        {'uid': 'new-uid', 'account_id': {'iban': 'LT12 3456'}, 'currency': 'EUR'},
      ],
    });
    expect(ids, [old]);
    final row = (await db.query('accounts', where: 'id = ?', whereArgs: [old])).first;
    expect((row['uid'], row['iban']), ('new-uid', 'LT123456'));
    final statuses = await db.rawQuery('SELECT status FROM consents ORDER BY id');
    expect(statuses.map((r) => r['status']), ['replaced', 'active']);
  });

  test('consent valid until uses bank maximum', () {
    final now = DateTime.utc(2026, 10, 26);
    expect(consentValidUntil({'maximum_consent_validity': 180 * 86400}, now), '2027-04-23T23:58:00Z');
  });

  test('consent error detection', () {
    expect(EnableBankingError('x', 401).isConsentProblem, isTrue);
    expect(EnableBankingError('x', 400, 'EXPIRED_SESSION').isConsentProblem, isTrue);
    expect(EnableBankingError('x', 500, 'ASPSP_ERROR').isConsentProblem, isFalse);
  });

  // test_db_is_encrypted → integration_test/db_encryption_test.dart (serve SQLCipher sul telefono).

  test('is_due respects interval', () async {
    final id = await addAccount(db);
    Future<Map<String, Object?>> account() async =>
        (await db.query('accounts', where: 'id = ?', whereArgs: [id])).first;
    expect(isDue(await account()), isTrue);
    await db.update('accounts', {'last_sync_at': utcNow()}, where: 'id = ?', whereArgs: [id]);
    expect(isDue(await account()), isFalse);
  });

  test('same iban different currencies are separate accounts', () async {
    Map<String, dynamic> session(String sid, String eur, String gbp) => {
          'session_id': sid,
          'access': {'valid_until': '2027-04-24T10:00:00Z'},
          'accounts': [
            {'uid': eur, 'account_id': {'iban': 'IT00X1'}, 'currency': 'EUR'},
            {'uid': gbp, 'account_id': {'iban': 'IT00X1'}, 'currency': 'GBP'},
          ],
        };
    final first = await saveSession(db, 'zeta', session('s1', 'eur-1', 'gbp-1'));
    expect(first.toSet().length, 2);
    // Al rinnovo gli uid cambiano: ogni valuta ritrova il proprio conto.
    final second = await saveSession(db, 'zeta', session('s2', 'eur-2', 'gbp-2'));
    expect(second, first);
    final rows = {for (final r in await db.rawQuery('SELECT currency, uid FROM accounts')) r['currency']: r['uid']};
    expect(rows, {'EUR': 'eur-2', 'GBP': 'gbp-2'});
  });

  test('migration adds hidden column', () async {
    sqfliteFfiInit();
    final fresh = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await fresh.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, bank_key TEXT NOT NULL, '
        'uid TEXT UNIQUE, consent_id INTEGER, iban TEXT, name TEXT, nickname TEXT, currency TEXT, '
        'last_sync_at TEXT, created_at TEXT NOT NULL)');
    await fresh.rawInsert("INSERT INTO accounts (bank_key, created_at) VALUES ('zeta', 'x')");
    await initDb(fresh);
    expect(await scalar(fresh, 'SELECT hidden FROM accounts'), 0);
    await fresh.close();
  });

  test('hidden accounts still count for internal transfers', () async {
    final zeta = await addAccount(db, bankKey: 'zeta', uid: 'u1', iban: 'IT011');
    final theta = await addAccount(db, bankKey: 'theta', uid: 'u2', iban: 'IT002');
    await db.update('accounts', {'hidden': 1}, where: 'id = ?', whereArgs: [zeta]);
    await storeTransactions(db, theta, [tx('50', ref: 'f', iban: 'IT011')], '2026-01-01');
    await recategorize(db);
    expect(await scalar(db, 'SELECT is_internal FROM transactions'), 1);
  });

  test('day label', () {
    final ref = DateTime(2026, 10, 26);
    expect(dayLabel('2026-10-26', ref), 'Oggi');
    expect(dayLabel('2026-10-25', ref), 'Ieri');
    expect(dayLabel('2026-10-03', ref), '3 ottobre');
    expect(dayLabel('2025-12-14', ref), '14 dicembre 2025');
  });

  test('default categories have icons', () async {
    expect(await scalar(db, 'SELECT count(*) FROM categories WHERE icon IS NULL'), 0);
    expect(await scalar(db, "SELECT icon FROM categories WHERE name = 'Spesa alimentare'"), 'shopping-cart');
    expect(defaultCategories.length, await scalar(db, 'SELECT count(*) FROM categories'));
  });

  test('own party rule', () {
    final names = [
      {'francesco', 'zanella'},
    ];
    expect(isOwnParty('ZANELLA FRANCESCO', null, names), isTrue);
    expect(isOwnParty('Francesco Zanella', 'qualsiasi', names), isTrue);
    expect(isOwnParty('Pinco Zanella', null, names), isFalse);
    expect(isOwnParty('Zanella Francesco Srl', null, names), isFalse); // nome diverso
    // Senza controparte: nome e cognome di seguito nella descrizione.
    expect(isOwnParty(null, 'Bonifico istantaneo a francesco zanella Rif. 0001', names), isTrue);
    expect(isOwnParty(null, 'Bonifico da ZANELLA FRANCESCO', names), isTrue);
    expect(isOwnParty(null, 'Pagamento a Francesco Rossi, Zanella Pinco', names), isFalse);
    expect(isOwnParty(null, null, names), isFalse);
  });

  test('transfer to myself detected', () async {
    final theta = await addAccount(db, bankKey: 'theta', uid: 'u1', iban: 'IT01');
    await db.update('accounts', {'name': 'ZANELLA FRANCESCO'}, where: 'id = ?', whereArgs: [theta]);
    await storeTransactions(db, theta, [
      tx('500', indicator: 'CRDT', ref: 'a', name: 'Francesco Zanella', day: '2026-10-01'),
      tx('40', ref: 'b', name: 'Pinco Zanella', day: '2026-10-02'),
    ], '2026-01-01');
    await recategorize(db);
    final internal = {
      for (final r in await db.rawQuery('SELECT id FROM transactions WHERE is_internal = 1')) r['id'],
    };
    expect(internal, {'$theta|e|a'});
  });

  test('paypal is an external service', () async {
    await db.rawInsert(
        "INSERT INTO banks (key, label, aspsp_name, country) VALUES ('kappa-it', 'Banca Kappa', 'Banca Kappa', 'IT')");
    final bank = await addAccount(db, bankKey: 'kappa-it', uid: 'u-bank', iban: 'IT99X');
    final rows = [
      tx('100', indicator: 'CRDT', ref: 'c1', name: null, remittance: ['Bonifico in entrata da PAYPAL Rif. 000001']),
      tx('200', ref: 'c2', name: null, remittance: ['Addebito diretto PAYPAL EUROPE S.A.R.L. ET CIE']),
      tx('10', ref: 'c3', name: null, remittance: ['Pagamento carta ZANELLA PAYPAL *negozio.online']),
      tx('20', indicator: 'CRDT', ref: 'c4', name: null, remittance: ['Bonifico estero da PayPal Europe S.a.r.l.']),
    ];
    await storeTransactions(db, bank, rows, '2026-01-01');
    await recategorize(db);
    expect(await scalar(db, 'SELECT count(*) FROM transactions WHERE is_internal = 1'), 0);
  });

  test('classifier version triggers recalculation', () async {
    final acc = await addAccount(db, bankKey: 'theta', uid: 'u1', iban: 'IT01');
    await db.update('accounts', {'name': 'Mario Rossi'}, where: 'id = ?', whereArgs: [acc]);
    await storeTransactions(db, acc, [tx('100', indicator: 'CRDT', ref: 'a', name: 'Rossi Mario')], '2026-01-01');
    await db.rawUpdate('UPDATE transactions SET is_internal = 0');
    await setSetting(db, 'classifier_version', '1');
    await initDb(db);
    expect(await scalar(db, 'SELECT is_internal FROM transactions'), 1);
    expect(await getSetting(db, 'classifier_version'), '$classifierVersion');
  });
}

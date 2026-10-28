// Movimenti da categorizzare: categoria dei movimenti in attesa conservata,
// scelta dei movimenti da notificare, apertura del dettaglio dalla notifica.
import 'dart:async';

import 'package:bankingmobile/app/app.dart';
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/bank/bank_service.dart';
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/data/database.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/domain/to_categorize.dart';
import 'package:bankingmobile/domain/transactions.dart';
import 'package:bankingmobile/security/app_lock.dart';
import 'package:bankingmobile/sync/background.dart' show movementNotificationId;
import 'package:bankingmobile/sync/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bank_test.dart' show FakeApi;
import 'security_test.dart' show FakeAuth;
import 'support.dart';

/// Banca finta che restituisce i movimenti indicati.
class TxApi extends FakeApi {
  List<Map<String, dynamic>> txs = [];

  @override
  Future<List<Map<String, dynamic>>> getTransactions(String uid, String dateFrom,
          {String? dateTo, String strategy = 'default'}) async =>
      txs;
}

void main() {
  late Database db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  final now = DateTime(2026, 10, 26);
  String daysAgo(int n) => iso(addDays(today(now), -n));
  Future<int> categoryId(String name) async =>
      await scalar(db, 'SELECT id FROM categories WHERE name = ?', [name]) as int;
  Future<Map<String, Object?>> row(String id) async =>
      (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

  group('movimenti in attesa', () {
    test('categoria a mano e notifica restano se è ancora in attesa (stesso id)', () async {
      final acc = await addAccount(db);
      final pending = tx('12', ref: 'p', name: 'Bar Roma', status: 'PDNG', day: '2026-10-20');
      await storeTransactions(db, acc, [pending], '2026-10-01');
      await setCategory(db, '$acc|e|p', await categoryId('Ristoranti e bar'));
      await markNotified(db, ['$acc|e|p']);

      await storeTransactions(db, acc, [pending], '2026-10-01');
      final r = await row('$acc|e|p');
      expect((r['category_id'], r['category_source']), (await categoryId('Ristoranti e bar'), 'manual'));
      expect(r['notified_at'], isNotNull);
    });

    test('contabilizzato con un altro id: stessa categoria, nessuna nuova notifica', () async {
      final acc = await addAccount(db);
      await storeTransactions(
          db, acc, [tx('12', ref: 'p', name: 'Bar Roma', status: 'PDNG', day: '2026-10-20')], '2026-10-01');
      final giro = await categoryId('Giroconti');
      await setCategory(db, '$acc|e|p', giro); // anche un giroconto scelto a mano
      await markNotified(db, ['$acc|e|p']);

      await storeTransactions(db, acc, [tx('12', ref: 'b', name: 'BAR ROMA', day: '2026-10-22')], '2026-10-01');
      expect(await scalar(db, 'SELECT count(*) FROM transactions'), 1);
      final r = await row('$acc|e|b');
      expect((r['category_id'], r['category_source'], r['is_internal']), (giro, 'manual', 1));
      expect(r['notified_at'], isNotNull);
      await recategorize(db); // le regole non toccano la scelta a mano
      expect((await row('$acc|e|b'))['category_id'], giro);
    });

    test('importo cambiato o controparte diversa: è un movimento nuovo', () async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('40', ref: 'p1', name: 'Ristorante', status: 'PDNG', day: '2026-10-20'),
        tx('5', ref: 'p2', name: 'Edicola', status: 'PDNG', day: '2026-10-20'),
      ], '2026-10-01');
      await markNotified(db, ['$acc|e|p1', '$acc|e|p2']);
      await storeTransactions(db, acc, [
        tx('44', ref: 'b1', name: 'Ristorante', day: '2026-10-21'), // con la mancia
        tx('5', ref: 'b2', name: 'Tabaccheria', day: '2026-10-21'),
      ], '2026-10-01');
      expect((await row('$acc|e|b1'))['notified_at'], isNull);
      expect((await row('$acc|e|b2'))['notified_at'], isNull);
    });

    test('troppo lontano nel tempo: non è lo stesso movimento', () async {
      final acc = await addAccount(db);
      await storeTransactions(
          db, acc, [tx('9.99', ref: 'p', name: 'Netflix', status: 'PDNG', day: '2026-09-01')], '2026-08-01');
      await markNotified(db, ['$acc|e|p']);
      await storeTransactions(db, acc, [tx('9.99', ref: 'b', name: 'Netflix', day: '2026-10-01')], '2026-08-01');
      expect((await row('$acc|e|b'))['notified_at'], isNull);
    });
  });

  group('quali movimenti notificare', () {
    test('solo i dubbi recenti, visibili, non giroconti né scelti a mano; una volta sola', () async {
      final acc = await addAccount(db, uid: 'u1', iban: 'IT00A');
      final hidden = await addAccount(db, bankKey: 'theta', uid: 'u2', iban: 'IT00B');
      await storeTransactions(db, acc, [
        tx('20', ref: 'dubbio', name: 'Negozio Strano', day: daysAgo(1)),
        tx('50', ref: 'regola', name: 'ESSELUNGA MILANO', day: daysAgo(1)),
        tx('30', ref: 'mano', name: 'Altro Negozio', day: daysAgo(1)),
        tx('15', ref: 'vecchio', name: 'Negozio Antico', day: daysAgo(10)),
        tx('100', indicator: 'CRDT', ref: 'entrata', name: 'Sconosciuto Srl', day: daysAgo(2)),
        tx('200', ref: 'giro', name: 'Io', iban: 'IT00B', day: daysAgo(1)),
      ], '2026-01-01');
      await storeTransactions(db, hidden, [tx('7', ref: 'nascosto', name: 'Bar', day: daysAgo(1))], '2026-01-01');
      await db.update('accounts', {'hidden': 1}, where: 'id = ?', whereArgs: [hidden]);
      await recategorize(db);
      await setCategory(db, '$acc|e|mano', await categoryId('Altre spese')); // scelta consapevole

      final ids = [for (final r in await toNotify(db, now: now)) r['id']];
      expect(ids, unorderedEquals(['$acc|e|dubbio', '$acc|e|entrata']));
      // Il riquadro in Home guarda all'ultimo mese, anche ai più vecchi di 7 giorni.
      expect([for (final r in await toCategorize(db, now: now)) r['id']],
          unorderedEquals(['$acc|e|dubbio', '$acc|e|entrata', '$acc|e|vecchio']));

      await markNotified(db, ids.cast<String>());
      expect(await toNotify(db, now: now), isEmpty);
    });

    test('storico di una banca collegata o rinnovata: nessuna notifica', () async {
      final acc = await addAccount(db);
      final api = TxApi()..txs = [tx('20', ref: 'x', name: 'Negozio Strano', day: daysAgo(1))];
      final account = (await db.query('accounts', where: 'id = ?', whereArgs: [acc])).single;
      await syncAccount(db, api, account, backfill: true, now: now);
      expect((await row('$acc|e|x'))['notified_at'], 'storico');
      expect(await toNotify(db, now: now), isEmpty);

      // Le sincronizzazioni successive invece segnalano i movimenti nuovi.
      api.txs = [...api.txs, tx('25', ref: 'y', name: 'Negozio Nuovo', day: daysAgo(0))];
      await syncAccount(db, api, account, now: now);
      expect([for (final r in await toNotify(db, now: now)) r['id']], ['$acc|e|y']);
    });

    test('aggiornando l\'app i movimenti già scaricati non vengono notificati', () async {
      final acc = await addAccount(db);
      await db.execute('ALTER TABLE transactions DROP COLUMN notified_at'); // database di prima
      await db.insert('transactions', {
        'id': '$acc|e|old',
        'account_id': acc,
        'booking_date': daysAgo(1),
        'amount_cents': -2000,
        'status': 'BOOK',
        'counterparty': 'Negozio Strano',
        'raw_json': '{}',
        'created_at': utcNow(),
        'updated_at': utcNow(),
      });
      await initDb(db);
      expect((await row('$acc|e|old'))['notified_at'], 'prima');
      expect(await toNotify(db, now: now), isEmpty);
    });

    test('dopo ogni sincronizzazione parte il controllo delle notifiche', () async {
      var calls = 0;
      final runner = SyncRunner(db, FakeApi(), afterSync: (_) async => calls++);
      await runner.start(onlyDue: false);
      expect(calls, 1);
    });

    test('id delle notifiche: stabili, distinti, lontani da quelli riservati', () {
      expect(movementNotificationId('1|e|a'), movementNotificationId('1|e|a'));
      expect(movementNotificationId('1|e|a'), isNot(movementNotificationId('1|e|b')));
      expect(movementNotificationId('1|e|a'), greaterThanOrEqualTo(1000));
    });
  });

  group('tocco sulla notifica', () {
    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    late int acc;
    late AppServices services;
    final dismissed = <String>[];

    setUp(() async {
      acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('20', ref: 'x', name: 'Negozio Strano', day: daysAgo(1))], '2026-01-01');
      dismissed.clear();
      services = AppServices(
        db: db,
        secrets: MemorySecretStore(),
        api: FakeApi(),
        pickPem: () async => null,
        openBankPage: (url) async => true,
        dismissNotification: (id) async => dismissed.add(id),
      );
    });

    testWidgets('app bloccata: il dettaglio si apre solo dopo lo sblocco', (tester) async {
      tallScreen(tester);
      final auth = FakeAuth()..next = AuthOutcome.failed;
      final opens = StreamController<String>();
      await tester.pumpWidget(BankingApp(services: services, lock: AppLock(auth), openTransactions: opens.stream));
      await settle(tester);
      opens.add('$acc|e|x');
      await settle(tester);
      expect(find.byKey(const Key('save-category')), findsNothing); // nessun dato prima dello sblocco

      auth.next = AuthOutcome.success;
      await tester.tap(find.byKey(const Key('unlock')));
      await settle(tester);
      expect(find.text('Negozio Strano'), findsWidgets);
      expect(find.byKey(const Key('save-category')), findsOneWidget);
      await opens.close();
    });

    testWidgets('app aperta: dettaglio subito; categorizzare toglie la notifica', (tester) async {
      tallScreen(tester);
      final opens = StreamController<String>();
      await tester.pumpWidget(BankingApp(services: services, lock: AppLock(FakeAuth()), openTransactions: opens.stream));
      await settle(tester);
      opens.add('$acc|e|x');
      await settle(tester);
      expect(find.byKey(const Key('save-category')), findsOneWidget);

      await tester.tap(find.byKey(const Key('category-select')));
      await settle(tester);
      await tester.tap(find.text('Salute').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-category')));
      await settle(tester);
      final source = await tester.runAsync(() => scalar(db, 'SELECT category_source FROM transactions'));
      expect(source, 'manual');
      expect(dismissed, ['$acc|e|x']);
      await opens.close();
    });
  });
}

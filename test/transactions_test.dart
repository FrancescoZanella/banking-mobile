// Parità con i test di Home e Movimenti di tests/test_web.py
// (test_manual_category_creates_rule, test_hidden_account_excluded_from_totals_and_list,
// test_home_feed_and_detail_panel, test_category_change_from_home_returns_home,
// test_transactions_periods_and_grouping, test_manual_transfer_and_visibility).
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/domain/reports.dart';
import 'package:bankingmobile/domain/transactions.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/home_screen.dart';
import 'package:bankingmobile/ui/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bank_test.dart' show FakeApi;
import 'support.dart';

void main() {
  late Database db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  Future<int> categoryId(String name) async =>
      await scalar(db, 'SELECT id FROM categories WHERE name = ?', [name]) as int;

  /// Pagina dentro l'app finta; attende le query sul DB (vero I/O, fuori dal tempo finto).
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    final services = AppServices(
      db: db,
      secrets: MemorySecretStore(),
      api: FakeApi(),
      pickPem: () async => null,
      openBankPage: (url) async => true,
    );
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Services(services: services, child: MaterialApp(home: Scaffold(body: page))));
    await settle(tester);
  }

  test('categoria a mano con regola: vale per tutti i movimenti della controparte', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [
      tx('4', ref: 'a', name: 'Panetteria Rossi'),
      tx('6', ref: 'b', name: 'Panetteria Rossi'),
    ], '2026-01-01');
    final cat = await categoryId('Spesa alimentare');
    final message = await setCategory(db, '$acc|e|a', cat, makeRule: true);
    expect(message, 'Regola creata: «Panetteria Rossi» → Spesa alimentare.');
    final rows = await db.rawQuery('SELECT category_id, category_source FROM transactions ORDER BY id');
    expect([for (final r in rows) (r['category_id'], r['category_source'])], [(cat, 'manual'), (cat, 'auto')]);
    expect(await scalar(db, "SELECT count(*) FROM category_rules WHERE pattern = 'panetteria rossi'"), 1);

    // «Automatica» la riporta al calcolo delle regole.
    await setCategory(db, '$acc|e|a', null);
    expect(await scalar(db, "SELECT category_source FROM transactions WHERE id = '$acc|e|a'"), 'auto');
  });

  test('conto nascosto escluso dai totali e dalla lista, salvo «Mostra conti nascosti»', () async {
    final zeta = await addAccount(db, bankKey: 'zeta', uid: 'u-zeta', iban: 'IT11');
    final theta = await addAccount(db, bankKey: 'theta', uid: 'u-theta', iban: 'IT02');
    await storeTransactions(db, zeta, [tx('10', ref: 'r1', day: '2026-10-02')], '2026-01-01');
    await storeTransactions(db, theta, [tx('20', ref: 'f1', day: '2026-10-03')], '2026-01-01');
    await db.update('accounts', {'hidden': 1}, where: 'id = ?', whereArgs: [zeta]);

    expect((await monthSummary(db, DateTime.utc(2026, 10)))['expense'], 2000);
    expect((await loadTransactions(db, const TxFilter())).count, 1);
    expect((await loadTransactions(db, const TxFilter(hidden: true))).count, 2);
  });

  test('periodi, raggruppamento per giorno, etichette dei chip e CSV', () async {
    final now = DateTime(2026, 10, 26);
    (String?, String?) range(TxFilter f) => f.range(now);
    expect(range(const TxFilter(period: 'month')), ('2026-10-01', '2026-10-26'));
    expect(range(const TxFilter(period: 'prev')), ('2026-09-01', '2026-09-30'));
    expect(range(const TxFilter(period: 'year')).$1, '2026-01-01');
    // Un intervallo esplicito vince sulla scorciatoia.
    expect(range(const TxFilter(period: 'month', from: '2026-05-01')).$1, '2026-05-01');
    expect(range(const TxFilter(period: 'bogus')), (null, null));

    final acc = await addAccount(db);
    await storeTransactions(db, acc, [
      tx('10', ref: 'a', name: 'Bar', day: '2026-10-02'),
      tx('5', ref: 'b', name: 'Edicola', day: '2026-10-02'),
      tx('100', indicator: 'CRDT', ref: 'c', name: 'Rimborso', day: '2026-10-03'),
    ], '2026-01-01');

    const october = TxFilter(from: '2026-10-01', to: '2026-10-31');
    final page = await loadTransactions(db, october);
    expect([for (final d in page.days) (d.$1, d.$3)], [('2026-10-03', 10000), ('2026-10-02', -1500)]);
    expect((page.spent, page.received, page.count), (1500, 10000, 3));
    expect(chipLabels(october, [], [])['period'], '01/10/26 – 31/10/26');

    final labels = chipLabels(const TxFilter(direction: 'in', category: 'none'), [], []);
    expect(labels, {'category': 'Senza categoria', 'direction': 'Entrate'});
    expect((await loadTransactions(db, const TxFilter(q: 'edic'))).count, 1);
    expect((await loadTransactions(db, const TxFilter(min: '6', max: '50'))).count, 1);

    final csv = await exportCsv(db, const TxFilter(from: '2026-10-02', to: '2026-10-02'));
    expect(csv, startsWith('﻿data;banca;conto;controparte;descrizione;importo;'));
    expect(csv, allOf(contains('Bar'), contains('-10,00;EUR'), isNot(contains('Rimborso'))));
  });

  test('CSV: niente formule eseguibili da Excel', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [tx('1', ref: 'x', name: '=HYPERLINK("http://x")')], '2026-01-01');
    final csv = await exportCsv(db, const TxFilter());
    expect(csv, contains('"\'=HYPERLINK(""http://x"")"'));
  });

  test('giroconto scelto a mano: visibile ma fuori dai totali, nessuna regola', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [
      tx('500', ref: 'a', name: 'Ricarica', day: '2026-10-05'),
      tx('20', ref: 'b', name: 'Bar', day: '2026-10-05'),
    ], '2026-01-01');
    final giro = await categoryId('Giroconti'), other = await categoryId('Altre spese');

    final message = await setCategory(db, '$acc|e|a', giro, makeRule: true);
    expect(message, contains('Per i giroconti non si creano regole'));
    expect(await scalar(db, "SELECT is_internal FROM transactions WHERE id = '$acc|e|a'"), 1);
    expect(await scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [giro]), 0);

    final page = await loadTransactions(db, const TxFilter(from: '2026-10-01', to: '2026-10-31'));
    expect(page.count, 2);
    expect((page.spent, page.days.single.$3), (2000, -2000));

    await setCategory(db, '$acc|e|a', other);
    expect(await scalar(db, "SELECT is_internal FROM transactions WHERE id = '$acc|e|a'"), 0);
  });

  testWidgets('Home: patrimonio, feed per giorno, dettaglio con lo storico', (tester) async {
    late int acc;
    await tester.runAsync(() async {
      acc = await addAccount(db, bankKey: 'zeta', uid: 'u-home', iban: 'IT11');
      final t = today();
      await storeTransactions(db, acc, [
        tx('4.50', ref: 'a', name: 'Bar <Centrale>', day: iso(t)),
        tx('3.00', ref: 'b', name: 'Bar <Centrale>', day: iso(addDays(t, -1))),
        tx('9.99', ref: 'c', name: 'Netflix', day: iso(addDays(t, -40))),
      ], '2020-01-01');
      await db.insert('balances', {
        'account_id': acc,
        'balance_type': 'ITAV',
        'amount_cents': 123456,
        'currency': 'EUR',
        'fetched_at': utcNow(),
      });
    });
    await pumpPage(tester, const HomeScreen());

    expect(find.text('1.234,56 €'), findsWidgets); // patrimonio
    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Ieri'), findsOneWidget);
    expect(find.text('Bar <Centrale>'), findsNWidgets(2)); // testo, mai HTML
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('tx-')),
        findsNWidgets(3));

    await tester.tap(find.byKey(ValueKey('tx-$acc|e|a')));
    await settle(tester);
    expect(find.text('Con Bar <Centrale>'), findsOneWidget);
    expect(find.text('-7,50 €'), findsOneWidget); // totale con la controparte
  });

  testWidgets('cambio categoria dal dettaglio: si resta in Home, aggiornata', (tester) async {
    late int acc;
    await tester.runAsync(() async {
      acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('4', ref: 'a', day: iso(today()))], '2026-01-01');
    });
    await pumpPage(tester, const HomeScreen());
    await tester.tap(find.byKey(ValueKey('tx-$acc|e|a')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('category-select')));
    await settle(tester);
    await tester.tap(find.text('Salute').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('save-category')));
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const Key('save-category')), findsNothing); // pannello chiuso
    expect(find.textContaining('Salute ·'), findsOneWidget); // riga del feed aggiornata
    final source = await tester.runAsync(() => scalar(db, "SELECT category_source FROM transactions"));
    expect(source, 'manual');
  });

  testWidgets('Movimenti: chip attivi, «Azzera filtri», totali e gruppi per giorno', (tester) async {
    await tester.runAsync(() async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('10', ref: 'a', name: 'Bar', day: '2026-10-02'),
        tx('5', ref: 'b', name: 'Edicola', day: '2026-10-02'),
        tx('100', indicator: 'CRDT', ref: 'c', name: 'Rimborso', day: '2026-10-03'),
      ], '2026-01-01');
    });
    String? shared;
    await pumpPage(
      tester,
      TransactionsScreen(
        initial: const TxFilter(from: '2026-10-01', to: '2026-10-31'),
        shareCsv: (csv) async => shared = csv,
      ),
    );
    expect(find.text('-15,00 €'), findsOneWidget);
    expect(find.text('+100,00 €'), findsNWidgets(2)); // totale del giorno e riga
    expect(find.byKey(const Key('day-2026-10-02')), findsOneWidget);
    expect(find.byKey(const Key('day-2026-10-03')), findsOneWidget);
    expect(find.text('01/10/26 – 31/10/26'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chip-direction')));
    await settle(tester);
    await tester.tap(find.text('Entrate').last);
    await settle(tester);
    expect(find.text('Rimborso'), findsOneWidget);
    expect(find.text('Bar'), findsNothing);

    await tester.tap(find.byKey(const Key('export-csv')));
    await settle(tester);
    expect(shared, allOf(contains('Rimborso'), isNot(contains('Edicola'))));

    await tester.tap(find.byKey(const Key('clear-filters')));
    await settle(tester);
    expect(find.byKey(const Key('clear-filters')), findsNothing);
    expect(find.text('Edicola'), findsOneWidget);
  });
}


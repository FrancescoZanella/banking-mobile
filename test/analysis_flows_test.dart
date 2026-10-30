// Parità con test_analysis_page_periods e test_flows_page di tests/test_web.py,
// più i dati mostrati (confronto allo stesso giorno, categorie, fonti ricorrenti).
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/core/periods.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/analysis_screen.dart';
import 'package:bankingmobile/ui/flows_screen.dart';
import 'package:bankingmobile/ui/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bank_test.dart' show FakeApi;
import 'support.dart';

final now = DateTime(2026, 10, 26);

void main() {
  late Database db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    final services = AppServices(
      db: db,
      secrets: MemorySecretStore(),
      api: FakeApi(),
      pickPem: () async => null,
      openBankPage: (url) async => true,
    );
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Services(services: services, child: MaterialApp(home: Scaffold(body: page))));
    await settle(tester);
  }

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('period-next'))).onPressed != null;

  String label(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('period-label'))).data!;

  test('barre fino al mese del periodo, mai oltre il mese in corso; barra evidenziata', () {
    final today = DateTime.utc(2026, 10, 26);
    expect(barsEnd(periodFor(PeriodKind.month, DateTime.utc(2026, 8, 15)), today), DateTime.utc(2026, 8));
    expect(barsEnd(periodFor(PeriodKind.year, today), today), DateTime.utc(2026, 10));
    final year = periodFor(PeriodKind.year, today);
    expect(monthInPeriod(DateTime.utc(2026, 3), year), isTrue);
    expect(monthInPeriod(DateTime.utc(2025, 12), year), isFalse);
    expect(monthInPeriod(DateTime.utc(2026, 10), periodFor(PeriodKind.week, today)), isTrue);
  });

  testWidgets('Analisi: periodi, confronto allo stesso giorno, categoria → Movimenti filtrati', (tester) async {
    await tester.runAsync(() async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('30', ref: 'a', name: 'Esselunga', day: '2026-10-05'),
        tx('20', ref: 'b', name: 'Esselunga', day: '2026-09-04'),
        tx('50', ref: 'c', name: 'Esselunga', day: '2026-09-28'), // dopo il 26: fuori dal confronto
      ], '2026-01-01');
    });
    await pumpPage(tester, AnalysisScreen(now: now));
    expect(find.text('Analisi spese'), findsOneWidget);
    expect(label(tester), 'ottobre 2026');
    expect(nextEnabled(tester), isFalse); // periodo in corso: niente futuro
    expect(find.text('Speso finora a ottobre'), findsOneWidget);
    expect(find.text('30,00 €'), findsWidgets);
    expect(find.text('10,00 € in più rispetto a settembre allo stesso giorno'), findsOneWidget);

    await tester.tap(find.byKey(const Key('period-prev')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('period-prev')));
    await settle(tester);
    expect(label(tester), 'agosto 2026');
    // Primo mese dei dati: niente confronto con luglio e niente freccia indietro.
    expect(find.byKey(const Key('no-comparison')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('period-prev'))).onPressed, isNull);
    expect(nextEnabled(tester), isTrue);

    for (final (kind, expected) in [('Settimana', '27 luglio – 2 agosto 2026'), ('Anno', '2026'), ('Mese', 'gennaio 2026')]) {
      await tester.tap(find.text(kind));
      await settle(tester);
      expect(label(tester), expected, reason: kind);
    }

    await tester.tap(find.text('Anno'));
    await settle(tester);
    expect(find.text('Speso finora nel 2026'), findsOneWidget);
    final category = await tester.runAsync(
        () => scalar(db, "SELECT category_id FROM transactions WHERE id LIKE '%|e|a'"));
    await tester.tap(find.byKey(Key('category-${category ?? 'none'}')));
    await settle(tester);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    // Tre movimenti della categoria nell'anno (il «3» del riquadro, non quello sul pulsante Filtri).
    expect(find.descendant(of: find.byType(Card), matching: find.text('3')), findsOneWidget);
  });

  testWidgets('Flussi: settimana, mese e anno, totali, categorie, entrate ricorrenti', (tester) async {
    await tester.runAsync(() async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [
        for (final (i, day) in ['2026-07-27', '2026-08-27', '2026-09-27', '2026-10-01'].indexed)
          tx('1000', indicator: 'CRDT', ref: 's$i', name: 'ACME Srl', day: day),
        tx('250', ref: 'x', name: 'Esselunga', day: '2026-10-10'),
      ], '2026-01-01');
    });
    await pumpPage(tester, FlowsScreen(now: now));
    expect(find.text('Entrate e flusso di cassa'), findsOneWidget);
    expect(find.text('Settimana'), findsOneWidget); // ora anche la settimana
    expect(find.text('Mese'), findsOneWidget);
    expect(find.text('Entrate finora'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('saved'))).data, '+750,00 €');
    expect(tester.widget<Text>(find.byKey(const Key('savings-rate'))).data, '75%');
    expect(find.textContaining('Ricorrente · ogni mese · prossima ~'), findsOneWidget);
    expect(nextEnabled(tester), isFalse);

    // Uscite ed entrate del mese divise per categoria.
    final expense = find.byKey(const Key('expense-by-category'));
    final income = find.byKey(const Key('income-by-category'));
    expect(find.descendant(of: expense, matching: find.byKey(const Key('flow-out-none'))), findsOneWidget);
    expect(find.descendant(of: expense, matching: find.text('250,00 €')), findsWidgets);
    expect(find.descendant(of: income, matching: find.text('1.000,00 €')), findsWidgets);

    // Saldo per categoria: entrate e uscite sono entrambe senza categoria, 1.000 − 250.
    final net = find.byKey(const Key('net-by-category'));
    expect(find.descendant(of: net, matching: find.byKey(const Key('net-none'))), findsOneWidget);
    expect(find.descendant(of: net, matching: find.text('+750,00 €')), findsOneWidget);

    // Tocco su una categoria → i suoi movimenti del periodo.
    await tester.tap(find.byKey(const Key('flow-out-none')));
    await settle(tester);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.text('Esselunga'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Anno'));
    await settle(tester);
    expect(label(tester), '2026');
  });
}

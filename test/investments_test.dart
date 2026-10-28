// Investimenti: tolti dalle uscite, sommati ai risparmiati, solo per i movimenti
// scelti a mano. Richieste dell'utente del 28/10/2026.
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/data/database.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/domain/analysis.dart';
import 'package:bankingmobile/domain/cashflow.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/domain/reports.dart';
import 'package:bankingmobile/domain/transactions.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/flows_screen.dart';
import 'package:bankingmobile/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bank_test.dart' show FakeApi;
import 'support.dart';

void main() {
  late Database db;
  late int acc;
  late int investimenti;

  final oct = (DateTime.utc(2026, 10), DateTime.utc(2026, 11));

  setUp(() async {
    db = await openTestDb();
    investimenti = await scalar(db, "SELECT id FROM categories WHERE name = 'Investimenti'") as int;
    acc = await addAccount(db, bankKey: 'theta', uid: 'u1', iban: 'IT01');
    await storeTransactions(db, acc, [
      tx('2000', indicator: 'CRDT', ref: 'stip', name: 'ACME SPA', day: '2026-10-01', remittance: ['Stipendio']),
      tx('300', ref: 'spesa', name: 'Esselunga', day: '2026-10-02'),
      tx('800', ref: 'etf', name: null, day: '2026-10-03',
          remittance: ['Compravendita titoli ETF azionario']),
      tx('200', indicator: 'CRDT', ref: 'vendita', name: null, day: '2026-10-10',
          remittance: ['Compravendita titoli azioni']),
    ], '2026-08-01');
    await recategorize(db);
  });
  tearDown(() => db.close());

  Future<String?> category(String ref) async => await scalar(db,
      'SELECT c.name FROM transactions t JOIN categories c ON c.id = t.category_id WHERE t.id = ?',
      ['$acc|e|$ref']) as String?;

  /// Come dal dettaglio del movimento: l'utente sceglie «Investimenti».
  Future<void> markInvestments() async {
    await setCategory(db, '$acc|e|etf', investimenti);
    await setCategory(db, '$acc|e|vendita', investimenti);
  }

  test('nessun riconoscimento automatico: solo i movimenti scelti a mano', () async {
    expect(await category('etf'), 'Altre spese');
    expect(await category('vendita'), 'Altre entrate');
    expect(await scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [investimenti]), 0);
    await markInvestments();
    expect(await category('etf'), 'Investimenti');
    await recategorize(db); // le regole non toccano la scelta a mano
    expect(await category('vendita'), 'Investimenti');
  });

  test('aggiornando l\'app la regola automatica della prima versione viene tolta', () async {
    await db.rawInsert(
        "INSERT INTO category_rules (category_id, field, pattern, priority) VALUES (?, 'text', 'compravendita titoli', 5)",
        [investimenti]);
    await setCategory(db, '$acc|e|vendita', investimenti); // questa scelta a mano resta
    await recategorize(db);
    expect(await category('etf'), 'Investimenti'); // messo dalla regola
    await setSetting(db, 'investments_version', '1');

    await initDb(db);
    expect(await scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [investimenti]), 0);
    expect(await category('etf'), 'Altre spese');
    expect(await category('vendita'), 'Investimenti');
  });

  test('tolti dalle uscite, sommati ai risparmiati (una volta sola)', () async {
    await markInvestments();
    final t = await totals(db, oct.$1, oct.$2);
    // Uscite: 300 + 800 − 800 investiti = 300. Investiti: 800 − 200 venduti = 600.
    // Risparmiati: sul conto 2.000 + 200 − 300 − 800 = 1.100, più i 600 investiti = 1.700.
    expect((t.income, t.expense, t.net), (200000, 30000, 170000));
    final inv = await invested(db, oct.$1, oct.$2);
    expect(inv, 60000);
    expect(t.net, (200000 + 20000 - 30000 - 80000) + inv);
    expect(await totalSpend(db, oct.$1, oct.$2), 30000);
    expect((await monthSummary(db, DateTime.utc(2026, 10)))['expense'], 30000);
    final flows = await byCategory(db, oct.$1, oct.$2);
    expect([for (final c in flows.expense) c.name], ['Spesa alimentare']);
    expect(flows.income.map((c) => c.name), isNot(contains('Investimenti')));
  });

  test("Movimenti: nell'elenco sì, nelle uscite mai (nemmeno filtrando il conto Theta)", () async {
    await markInvestments();
    final all = await loadTransactions(db, const TxFilter());
    expect((all.count, all.spent, all.received), (4, 30000, 200000)); // elencati tutti e 4
    final theta = await loadTransactions(db, TxFilter(account: acc));
    expect((theta.count, theta.spent, theta.received), (4, 30000, 200000));
    final days = {for (final (day, _, total) in theta.days) day: total};
    expect(days['2026-10-03'], 0); // il giorno con il solo acquisto di ETF non ha uscite
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.runAsync(markInvestments);
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

  testWidgets('Home: «Investito da agosto» (invariata)', (tester) async {
    await pumpPage(tester, const HomeScreen());
    expect(tester.widget<Text>(find.byKey(const Key('home-invested'))).data, 'Investito da agosto: 600,00 €');
  });

  testWidgets('Flussi: Risparmiati e Investiti', (tester) async {
    await pumpPage(tester, FlowsScreen(now: DateTime(2026, 10, 26)));
    expect(tester.widget<Text>(find.byKey(const Key('saved'))).data, '+1.700,00 €');
    expect(find.textContaining('di cui investiti'), findsNothing); // dicitura tolta su richiesta
    expect(tester.widget<Text>(find.byKey(const Key('invested'))).data, '600,00 €');
    expect(find.text('Risparmiati'), findsOneWidget);
    expect(find.text('Investiti'), findsOneWidget);
  });

  testWidgets('Flussi: Risparmiati e Investiti visibili anche senza investimenti', (tester) async {
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
    await tester.pumpWidget(Services(
        services: services, child: MaterialApp(home: Scaffold(body: FlowsScreen(now: DateTime(2026, 10, 26))))));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('invested'))).data, '0,00 €');
    expect(find.text('Risparmiati'), findsOneWidget);
  });
}

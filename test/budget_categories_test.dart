// Parità con test_budget_page_and_forms, test_category_icons e la parte sulle
// regole di test_manual_transfer_and_visibility (tests/test_web.py).
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/data/defaults.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/domain/budget.dart';
import 'package:bankingmobile/domain/categories.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/budget_screen.dart';
import 'package:bankingmobile/ui/categories_screen.dart';
import 'package:bankingmobile/ui/home_screen.dart';
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

  test('budget: salva, importo non valido, solo spese, totale «1.600», rimuovi', () async {
    final spesa = await categoryId('Spesa alimentare');
    final entrate = await scalar(db, "SELECT id FROM categories WHERE kind = 'income' LIMIT 1") as int;

    expect((await saveBudget(db, '$spesa', '450')).text, 'Budget salvato.');
    expect(await scalar(db, 'SELECT amount_cents FROM budgets WHERE category_id = ?', [spesa]), 45000);
    final bad = await saveBudget(db, '$spesa', 'boh');
    expect(bad.ok, isFalse);
    expect(bad.text, contains('Importo non valido'));
    // Solo categorie di spesa.
    expect((await saveBudget(db, '$entrate', '10')).ok, isFalse);
    expect(await scalar(db, 'SELECT count(*) FROM budgets WHERE category_id = ?', [entrate]), 0);
    expect((await freeCategories(db)).map((c) => c['id']), isNot(contains(spesa)));

    await saveBudget(db, 'total', '1.600');
    expect(await scalar(db, "SELECT value FROM settings WHERE key = 'budget_total'"), '160000');
    await deleteBudget(db, 'total');
    expect(await scalar(db, "SELECT value FROM settings WHERE key = 'budget_total'"), '0');
    await deleteBudget(db, '$spesa');
    expect(await scalar(db, 'SELECT count(*) FROM budgets'), 0);
  });

  test('icone delle categorie: in elenco, generica se manca, rifiutate le altre', () async {
    expect(iconChoices, contains('pizza')); // tra le icone proposte
    await createCategory(db, name: 'Animali', kind: 'expense', color: '#123456', icon: 'paw');
    expect(await scalar(db, "SELECT icon FROM categories WHERE name = 'Animali'"), 'paw');
    await createCategory(db, name: 'Varie', kind: 'expense', color: '#123456');
    expect(await scalar(db, "SELECT icon FROM categories WHERE name = 'Varie'"), 'tag');
    final hack = await createCategory(db, name: 'Hack', kind: 'expense', color: '#123456', icon: 'x" onload="');
    expect(hack.ok, isFalse);
    expect(await scalar(db, "SELECT count(*) FROM categories WHERE name = 'Hack'"), 0);
    expect((await createCategory(db, name: 'Animali', kind: 'expense', color: '#123456')).text,
        'Esiste già una categoria con questo nome.');
    expect((await createCategory(db, name: 'X', kind: 'boh', color: '#123456')).ok, isFalse);
    expect((await createCategory(db, name: 'X', kind: 'expense', color: 'red')).ok, isFalse);

    final cat = await categoryId('Animali');
    expect(await setIcon(db, cat, 'gift'), isTrue);
    expect(await setIcon(db, cat, 'nope'), isFalse);
    expect(await scalar(db, 'SELECT icon FROM categories WHERE id = ?', [cat]), 'gift');
  });

  test('regole: ricategorizzano; verso Giroconti no; eliminare categoria o regola ricalcola', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [tx('20', ref: 'a', name: 'Palestra Fit')], '2026-01-01');
    final salute = await categoryId('Salute'), giro = await categoryId('Giroconti');

    final transfer = await createRule(db, field: 'text', pattern: 'ricarica', categoryId: giro);
    expect(transfer.text, contains('non con una regola'));
    expect(await scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [giro]), 0);
    expect((await createRule(db, field: 'text', pattern: 'x', categoryId: salute)).text, 'Regola non valida.');
    expect((await createRule(db, field: 'iban', pattern: 'palestra', categoryId: salute)).ok, isFalse);

    expect((await createRule(db, field: 'text', pattern: ' PALESTRA ', categoryId: salute)).ok, isTrue);
    expect(await scalar(db, 'SELECT category_id FROM transactions'), salute);
    final rule = await scalar(db, "SELECT id FROM category_rules WHERE pattern = 'palestra'") as int;
    await deleteRule(db, rule);
    expect(await scalar(db, 'SELECT category_id FROM transactions'), isNot(salute));

    // Categoria eliminata: anche le sue regole e i budget, i movimenti ricalcolati.
    await createCategory(db, name: 'Sport', kind: 'expense', color: '#123456');
    final sport = await categoryId('Sport');
    await createRule(db, field: 'text', pattern: 'palestra', categoryId: sport);
    await saveBudget(db, '$sport', '30');
    expect(await scalar(db, 'SELECT category_id FROM transactions'), sport);
    await deleteCategory(db, sport);
    expect(await scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [sport]), 0);
    expect(await scalar(db, 'SELECT count(*) FROM budgets'), 0);
    expect(await scalar(db, 'SELECT category_id FROM transactions'), isNot(sport));
  });

  testWidgets('pagina Budget: aggiungi dal pannello, stato e rimuovi', (tester) async {
    await tester.runAsync(() async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('400', ref: 'a', name: 'Esselunga', day: '2026-10-10')], '2026-01-01');
    });
    await pumpPage(tester, BudgetScreen(now: DateTime(2026, 10, 26)));
    expect(find.text('Budget e abbonamenti'), findsOneWidget);
    expect(find.text('Nessun budget ancora. Scegli una categoria e un importo mensile.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-budget')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('budget-target')));
    await settle(tester);
    await tester.tap(find.text('Totale del mese').last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('budget-amount')), '450');
    await tester.tap(find.byKey(const Key('budget-save')));
    await settle(tester);

    expect(find.text('Budget salvato.'), findsOneWidget);
    expect(find.textContaining('Restano 50,00 €'), findsOneWidget); // 400 di 450: avviso (≥80%)
    await tester.tap(find.text('rimuovi'));
    await settle(tester);
    await tester.tap(find.text('Rimuovi'));
    await settle(tester);
    expect(find.text('Nessun budget ancora. Scegli una categoria e un importo mensile.'), findsOneWidget);
  });

  testWidgets('Home: «Vedi budget» solo se un budget è al limite', (tester) async {
    await pumpPage(tester, const HomeScreen());
    expect(find.text('Vedi budget'), findsNothing);
  });

  testWidgets('pagina Categorie: tocco → cambio icona; regola verso Giroconti rifiutata', (tester) async {
    late int salute, giro;
    await tester.runAsync(() async {
      salute = await categoryId('Salute');
      giro = await categoryId('Giroconti');
    });
    await pumpPage(tester, const CategoriesScreen());
    expect(find.text('Categorie e regole'), findsOneWidget);

    await tester.tap(find.byKey(Key('category-$salute')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('icon-pill')));
    await settle(tester);
    expect(await tester.runAsync(() => scalar(db, 'SELECT icon FROM categories WHERE id = ?', [salute])), 'pill');

    await tester.tap(find.byKey(const Key('new-rule')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('rule-pattern')), 'ricarica');
    await tester.tap(find.byKey(const Key('rule-category')));
    await settle(tester);
    await tester.tap(find.text('Giroconti').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('rule-save')));
    await settle(tester);
    expect(find.textContaining('non con una regola'), findsOneWidget);
    expect(await tester.runAsync(() => scalar(db, 'SELECT count(*) FROM category_rules WHERE category_id = ?', [giro])), 0);
  });
}


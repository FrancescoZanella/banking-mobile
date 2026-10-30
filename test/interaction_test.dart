// Interazione: «Annulla» dopo un cambio di categoria, scorrimento sulla riga,
// selezione multipla in Movimenti, modalità «Smista».
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/domain/transactions.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/sort_screen.dart';
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
  Future<Object?> categoryOf(String id) => scalar(db, 'SELECT category_id FROM transactions WHERE id = ?', [id]);
  Future<Object?> sourceOf(String id) => scalar(db, 'SELECT category_source FROM transactions WHERE id = ?', [id]);

  final dismissed = <String>[];

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    dismissed.clear();
    final services = AppServices(
      db: db,
      secrets: MemorySecretStore(),
      api: FakeApi(),
      pickPem: () async => null,
      openBankPage: (url) async => true,
      dismissNotification: (id) async => dismissed.add(id),
    );
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Services(services: services, child: MaterialApp(home: Scaffold(body: page))));
    await settle(tester);
  }

  group('«Annulla»', () {
    test('rimette la categoria di prima, anche quella automatica', () async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('20', ref: 'a', name: 'Negozio Strano')], '2026-01-01');
      final before = (await categoryOf('$acc|e|a'), await sourceOf('$acc|e|a'));
      final undo = await categorySnapshot(db, ['$acc|e|a']);
      await setCategory(db, '$acc|e|a', await categoryId('Salute'));
      expect(await sourceOf('$acc|e|a'), 'manual');
      await undoCategory(db, undo);
      expect((await categoryOf('$acc|e|a'), await sourceOf('$acc|e|a')), before);
    });

    test('con la regola: la toglie e gli altri movimenti tornano come prima', () async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('4', ref: 'a', name: 'Panetteria Rossi'),
        tx('6', ref: 'b', name: 'Panetteria Rossi'),
      ], '2026-01-01');
      await recategorize(db);
      final other = await categoryOf('$acc|e|b');
      final undo = await categorySnapshot(db, ['$acc|e|a'], rulePattern: rulePattern('Panetteria Rossi'));
      await setCategory(db, '$acc|e|a', await categoryId('Spesa alimentare'), makeRule: true);
      expect(await scalar(db, "SELECT count(*) FROM category_rules WHERE pattern = 'panetteria rossi'"), 1);

      await undoCategory(db, undo);
      expect(await scalar(db, "SELECT count(*) FROM category_rules WHERE pattern = 'panetteria rossi'"), 0);
      expect(await categoryOf('$acc|e|b'), other);
      expect(await sourceOf('$acc|e|a'), 'auto');
    });

    test('regola già esistente: torna alla categoria di prima', () async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('4', ref: 'a', name: 'Bar Sport')], '2026-01-01');
      final salute = await categoryId('Salute'), bar = await categoryId('Ristoranti e bar');
      await db.insert('category_rules', {'category_id': bar, 'field': 'text', 'pattern': 'bar sport', 'priority': 10});
      await recategorize(db);
      final undo = await categorySnapshot(db, ['$acc|e|a'], rulePattern: 'bar sport');
      await setCategory(db, '$acc|e|a', salute, makeRule: true);
      await undoCategory(db, undo);
      expect(await scalar(db, "SELECT category_id FROM category_rules WHERE pattern = 'bar sport'"), bar);
      expect(await categoryOf('$acc|e|a'), bar);
    });

    test('più movimenti insieme: stessa categoria, poi annullata', () async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('1', ref: 'a', name: 'X1'), tx('2', ref: 'b', name: 'X2')], '2026-01-01');
      final ids = ['$acc|e|a', '$acc|e|b'];
      final before = [for (final id in ids) await categoryOf(id)];
      final undo = await categorySnapshot(db, ids);
      final salute = await categoryId('Salute');
      await setCategoryMany(db, ids, salute);
      expect([for (final id in ids) await categoryOf(id)], [salute, salute]);
      await undoCategory(db, undo);
      expect([for (final id in ids) await categoryOf(id)], before);
    });
  });

  testWidgets('Movimenti: selezione multipla con pressione lunga, categoria a tutti, «Annulla»', (tester) async {
    late int acc;
    await tester.runAsync(() async {
      acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('10', ref: 'a', name: 'Negozio Uno', day: '2026-10-02'),
        tx('5', ref: 'b', name: 'Negozio Due', day: '2026-10-02'),
        tx('7', ref: 'c', name: 'Negozio Tre', day: '2026-10-03'),
      ], '2026-01-01');
    });
    await pumpPage(tester, const TransactionsScreen());
    expect(find.byKey(const Key('selection-bar')), findsNothing);

    await tester.longPress(find.byKey(ValueKey('tx-$acc|e|a')));
    await settle(tester);
    expect(find.text('1 selezionato'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('tx-$acc|e|b')));
    await settle(tester);
    expect(find.text('2 selezionati'), findsOneWidget);

    final salute = await tester.runAsync(() => categoryId('Salute'));
    await tester.tap(find.byKey(const Key('selection-category')));
    await settle(tester);
    await tester.tap(find.byKey(Key('pick-$salute')));
    await settle(tester);
    expect(find.byKey(const Key('selection-bar')), findsNothing);
    expect(await tester.runAsync(() => categoryOf('$acc|e|a')), salute);
    expect(await tester.runAsync(() => categoryOf('$acc|e|b')), salute);
    expect(await tester.runAsync(() => sourceOf('$acc|e|c')), isNot('manual'));
    expect(dismissed, unorderedEquals(['$acc|e|a', '$acc|e|b']));
    expect(find.text('Salute · 2 movimenti'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await settle(tester);
    expect(await tester.runAsync(() => sourceOf('$acc|e|a')), isNot('manual'));
    expect(await tester.runAsync(() => sourceOf('$acc|e|b')), isNot('manual'));
  });

  testWidgets('scorrendo una riga verso sinistra si sceglie la categoria', (tester) async {
    late int acc;
    await tester.runAsync(() async {
      acc = await addAccount(db);
      await storeTransactions(db, acc, [tx('10', ref: 'a', name: 'Negozio Strano')], '2026-01-01');
    });
    await pumpPage(tester, const TransactionsScreen());
    await tester.drag(find.byKey(ValueKey('tx-$acc|e|a')), const Offset(-600, 0));
    await settle(tester);
    final viaggi = await tester.runAsync(() => categoryId('Svago e viaggi'));
    await tester.tap(find.byKey(Key('pick-$viaggi')));
    await settle(tester);
    expect(await tester.runAsync(() => categoryOf('$acc|e|a')), viaggi);
    expect(find.text('Categoria: Svago e viaggi'), findsOneWidget);
    expect(find.text('Negozio Strano'), findsOneWidget); // la riga resta al suo posto
  });

  testWidgets('Smista: uno alla volta, «Indietro» annulla, «Salta», fine', (tester) async {
    late int acc;
    final now = today();
    String daysAgo(int n) => iso(addDays(now, -n));
    await tester.runAsync(() async {
      acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('10', ref: 'a', name: 'Negozio Uno', day: daysAgo(1)),
        tx('5', ref: 'b', name: 'Negozio Due', day: daysAgo(2)),
      ], '2026-01-01');
    });
    await pumpPage(tester, const SortScreen());
    expect(find.text('1 di 2'), findsOneWidget);
    final first = find.text('Negozio Uno').evaluate().isNotEmpty ? 'a' : 'b';
    final second = first == 'a' ? 'b' : 'a';

    // Senza scelte precedenti le 6 proposte sono in ordine alfabetico: c'è «Abbonamenti».
    final chosen = await tester.runAsync(() => categoryId('Abbonamenti'));
    await tester.tap(find.byKey(Key('sort-cat-$chosen')));
    await settle(tester);
    expect(find.text('2 di 2'), findsOneWidget);
    expect(await tester.runAsync(() => categoryOf('$acc|e|$first')), chosen);
    expect(dismissed, ['$acc|e|$first']);

    await tester.tap(find.byKey(const Key('sort-back')));
    await settle(tester);
    expect(find.text('1 di 2'), findsOneWidget);
    expect(await tester.runAsync(() => sourceOf('$acc|e|$first')), isNot('manual'));

    await tester.tap(find.byKey(const Key('sort-skip')));
    await settle(tester);
    await tester.tap(find.byKey(Key('sort-cat-$chosen')));
    await settle(tester);
    expect(await tester.runAsync(() => categoryOf('$acc|e|$second')), chosen);
    expect(find.text('Tutto smistato!'), findsOneWidget);
    expect(find.text('1 movimento categorizzato.'), findsOneWidget);
  });
}

// Parità con tests/test_budget.py della versione web.
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/core/money.dart';
import 'package:bankingmobile/core/periods.dart';
import 'package:bankingmobile/data/database.dart';
import 'package:bankingmobile/domain/budget.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

final todayRef = day(2026, 10, 26);

Future<Database> seeded() async {
  final db = await openTestDb();
  final acc = await addAccount(db, bankKey: 'zeta', uid: 'u1', iban: 'IT11');
  String d(int m, int dd) => '2026-${m.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}';
  final rows = [
    for (var m = 6; m <= 9; m++) tx('13.99', ref: 'n$m', name: 'Netflix', day: d(m, 3)),
    tx('15.99', ref: 'n10', name: 'Netflix', day: '2026-10-03'), // aumento
    for (var m = 7; m <= 10; m++) tx('40', ref: 'e$m', name: 'Esselunga', day: d(m, 10)),
    for (var m = 3; m <= 6; m++) tx('20', ref: 'g$m', name: 'Vecchia palestra', day: d(m, 1)),
    tx('300', ref: 'sp', name: 'Esselunga', day: '2026-10-20'),
  ];
  await storeTransactions(db, acc, rows, '2026-01-01');
  await recategorize(db);
  return db;
}

void main() {
  test('parse_euro', () {
    expect(parseEuro('250'), 25000);
    expect(parseEuro('1.600,50 €'), 160050);
    expect(parseEuro('12.5'), 1250);
    expect((parseEuro('1.600'), parseEuro('1.234.567')), (160000, 123456700));
    expect(parseEuro('0'), 0);
    expect((parseEuro('abc'), parseEuro('-5'), parseEuro('')), (null, null, null));
  });

  test('forecast and states', () {
    final october = periodFor(PeriodKind.month, todayRef);
    expect(forecast(26000, october, todayRef), 31000); // 260 € in 26 giorni → 310 €
    expect(forecast(500, periodFor(PeriodKind.month, day(2026, 9, 1)), todayRef), 500);
    expect(status(45000, 41200, 0).state, BudgetState.warn);
    expect(status(25000, 29800, 0).state, BudgetState.over);
    expect(status(30000, 12000, 0).state, BudgetState.ok);
  });

  test('budget overview and alerts', () async {
    final db = await seeded();
    final spesa = await scalar(db, "SELECT id FROM categories WHERE name = 'Spesa alimentare'");
    await db.insert('budgets', {'category_id': spesa, 'amount_cents': 30000});
    await setSetting(db, 'budget_total', '40000');
    final data = await overview(db, todayRef);
    expect(data.daysLeft, 5);
    final cat = data.categories.first;
    expect((cat.name, cat.status.spent, cat.status.state), ('Spesa alimentare', 34000, BudgetState.over));
    expect((data.total!.spent, data.total!.state), (34000 + 1599, BudgetState.warn));
    expect((await alerts(db, todayRef)).map((a) => a.name), ['Totale del mese', 'Spesa alimentare']);
    await db.close();
  });

  test('subscriptions detection and ignore', () async {
    final db = await seeded();
    var subs = await subscriptions(db, todayRef);
    final names = subs.items.map((s) => s.name).toList();
    // La palestra non addebita da giugno: non è più attiva.
    expect(names, isNot(contains('Vecchia palestra')));
    final netflix = subs.items.firstWhere((s) => s.name == 'Netflix');
    expect((netflix.amount, netflix.previous), (1599, 1399));
    expect(netflix.next.isAfter(day(2026, 10, 30)), isTrue);
    // Esselunga: importi troppo diversi (ultima spesa 300 €), non è un abbonamento.
    expect(names, isNot(contains('Esselunga')));

    await ignoreSubscription(db, 'Netflix');
    subs = await subscriptions(db, todayRef);
    expect(subs.items.map((s) => s.name), isNot(contains('Netflix')));
    expect(subs.ignored, ['netflix']);
    await restoreSubscription(db, 'netflix');
    expect((await subscriptions(db, todayRef)).items.map((s) => s.name), contains('Netflix'));
    await db.close();
  });
}

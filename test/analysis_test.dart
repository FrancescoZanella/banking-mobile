// Parità con tests/test_analysis.py della versione web.
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/core/periods.dart';
import 'package:bankingmobile/domain/analysis.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

final todayRef = day(2026, 10, 26); // lunedì

void main() {
  test('period bounds and labels', () {
    final month = periodFor(PeriodKind.month, todayRef);
    expect((month.start, month.end, month.label), (day(2026, 10, 1), day(2026, 11, 1), 'ottobre 2026'));
    final week = periodFor(PeriodKind.week, day(2026, 10, 28));
    expect((week.start, week.end), (day(2026, 10, 26), day(2026, 11, 2)));
    expect(week.label, '26 ottobre – 1 novembre 2026');
    final year = periodFor(PeriodKind.year, todayRef);
    expect((year.start, year.end, year.label), (day(2026, 1, 1), day(2027, 1, 1), '2026'));
    expect(previous(periodFor(PeriodKind.month, day(2026, 1, 15))).label, 'dicembre 2025');
    expect(previous(month).versus, 'a settembre');
    expect(previous(year).versus, 'al 2025');
  });

  test('comparable window same day of previous period', () {
    final month = periodFor(PeriodKind.month, todayRef);
    expect(comparableWindow(month, todayRef), (day(2026, 9, 1), day(2026, 9, 27)));
    // 31 marzo: il confronto si ferma alla fine di febbraio.
    final march = periodFor(PeriodKind.month, day(2026, 3, 31));
    expect(comparableWindow(march, day(2026, 3, 31)), (day(2026, 2, 1), day(2026, 3, 1)));
    // Periodo passato: confronto pieno con il precedente.
    final august = periodFor(PeriodKind.month, day(2026, 8, 10));
    expect(comparableWindow(august, todayRef), (day(2026, 7, 1), day(2026, 8, 1)));
  });

  group('con dati', () {
    late Database db;
    setUp(() async {
      db = await openTestDb();
      final acc = await addAccount(db, bankKey: 'zeta', uid: 'u1', iban: 'IT11');
      await addAccount(db, bankKey: 'theta', uid: 'u2', iban: 'IT02');
      final hidden = await addAccount(db, bankKey: 'theta', uid: 'u3', iban: 'IT03');
      await db.update('accounts', {'hidden': 1}, where: 'id = ?', whereArgs: [hidden]);
      await storeTransactions(db, acc, [
        tx('10', ref: 'a', name: 'Esselunga', day: '2026-10-02'),
        tx('5', ref: 'b', name: 'Esselunga', day: '2026-10-05'),
        tx('20', ref: 'c', name: 'Bar', day: '2026-09-03'),
        tx('100', indicator: 'CRDT', ref: 'd', name: 'Stipendio', day: '2026-10-03'), // entrata: esclusa
        tx('50', ref: 'e', name: 'Me', iban: 'IT02', day: '2026-10-04'), // giroconto: escluso
      ], '2026-01-01');
      await storeTransactions(db, hidden, [tx('999', ref: 'h', name: 'X', day: '2026-10-06')], '2026-01-01');
      await recategorize(db);
    });
    tearDown(() => db.close());

    test('totals, cumulative, categories, merchants', () async {
      final month = periodFor(PeriodKind.month, todayRef);
      final until = elapsedEnd(month, todayRef);
      expect(await totalSpend(db, month.start, until), 1500);
      final curve = await cumulative(db, month, until);
      expect(curve.length, 26);
      expect((curve.first, curve[1], curve.last), (0, 1000, 1500));

      final cats = await categories(db, month.start, until, day(2026, 9, 1), day(2026, 9, 27));
      final spesa = cats.firstWhere((c) => c.name == 'Spesa alimentare');
      expect((spesa.total, spesa.n, spesa.pct.round()), (1500, 2, 100));
      expect(spesa.delta, 1500);

      final top = await topMerchants(db, month.start, until);
      expect(top.map((m) => (m['name'], m['total'], m['n'])), [('Esselunga', 1500, 2)]);
      expect((top.first['last_key'] as String).startsWith('2026-10-05|'), isTrue);

      final bars = {for (final (m, s) in await monthlyBars(db, day(2026, 10, 1))) m: s};
      expect((bars[day(2026, 10, 1)], bars[day(2026, 9, 1)]), (1500, 2000));
    });
  });
}

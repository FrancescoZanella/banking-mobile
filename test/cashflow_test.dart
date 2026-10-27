// Parità con tests/test_cashflow.py della versione web.
import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/domain/cashflow.dart';
import 'package:bankingmobile/domain/categorize.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final todayRef = day(2026, 10, 26);

void main() {
  test('detect recurring monthly salary', () {
    final salary = [for (var m = 5; m <= 10; m++) (day(2026, m, 27), 200000 + (m % 2) * 1000)];
    final result = detectRecurring(salary);
    expect(result, isNotNull);
    expect(result!.interval, inInclusiveRange(28, 32));
    expect(result.next.isAfter(day(2026, 10, 27)), isTrue);
  });

  test('detect recurring rejects irregular or few', () {
    expect(detectRecurring([(day(2026, 9, 1), 100), (day(2026, 10, 1), 100)]), isNull);
    final weekly = [for (final d in [1, 8, 15, 22]) (day(2026, 10, d), 500)];
    expect(detectRecurring(weekly), isNull);
    final varying = [
      for (final (m, a) in [(7, 1000), (8, 5000), (9, 900), (10, 3000)]) (day(2026, m, 5), a),
    ];
    expect(detectRecurring(varying), isNull);
  });

  test('totals, rate and sources', () async {
    final db = await openTestDb();
    final acc = await addAccount(db, bankKey: 'theta', uid: 'u1', iban: 'IT01');
    await addAccount(db, bankKey: 'zeta', uid: 'u2', iban: 'IT12');
    final rows = [
      for (var m = 6; m <= 9; m++)
        tx('2000', indicator: 'CRDT', ref: 's$m', name: 'ACME SPA',
            day: '2026-${m.toString().padLeft(2, '0')}-27', remittance: ['Stipendio']),
      tx('2000', indicator: 'CRDT', ref: 's10', name: 'ACME SPA', day: '2026-10-24', remittance: ['Stipendio']),
      tx('60', indicator: 'CRDT', ref: 'r', name: 'Referral', day: '2026-10-10'),
      tx('400', ref: 'sp', name: 'Esselunga', day: '2026-10-12'),
      tx('300', ref: 'g', name: 'Me', iban: 'IT12', day: '2026-10-13'), // giroconto, escluso
    ];
    await storeTransactions(db, acc, rows, '2026-01-01');
    await recategorize(db);

    final t = await totals(db, day(2026, 10, 1), day(2026, 10, 27));
    expect((t.income, t.expense, t.net), (206000, 40000, 166000));
    expect(savingsRate(t.income, t.net)!.round(), 81);
    expect(savingsRate(0, -100), isNull);

    final sources = await incomeSources(db, day(2026, 10, 1), day(2026, 10, 27), todayRef);
    expect(sources.map((s) => s.party), ['ACME SPA', 'Referral']);
    expect((sources[0].recurring != null, sources[1].recurring), (true, null));
    expect(sources[0].lastKey.startsWith('2026-10-24|'), isTrue);

    final series = await monthly(db, day(2026, 10, 1));
    expect((series.length, series.last.$2.income), (12, 206000));
    await db.close();
  });
}

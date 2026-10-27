/// Analisi delle spese per periodo (settimana, mese, anno).
///
/// Tutti gli intervalli sono [start, end). Spesa = uscite non giroconto dei
/// conti visibili, in centesimi positivi.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/periods.dart';
import 'reports.dart';

Future<int> totalSpend(DatabaseExecutor db, DateTime start, DateTime end) async {
  final row = await db.rawQuery(
    'SELECT coalesce(-sum(amount_cents), 0) AS s FROM transactions '
    'WHERE $spendSql AND booking_date >= ? AND booking_date < ?',
    [iso(start), iso(end)],
  );
  return row.first['s'] as int;
}

/// Spesa cumulata in centesimi: per giorno (settimana/mese) o per mese (anno).
Future<List<int>> cumulative(DatabaseExecutor db, Period period, DateTime until) async {
  final Map<int, int> byKey;
  final int last;
  final int keys;
  if (period.kind == PeriodKind.year) {
    final rows = await db.rawQuery(
      'SELECT substr(booking_date, 6, 2) AS k, -sum(amount_cents) AS s FROM transactions '
      'WHERE $spendSql AND booking_date >= ? AND booking_date < ? GROUP BY k',
      [iso(period.start), iso(until)],
    );
    byKey = {for (final r in rows) int.parse(r['k'] as String): r['s'] as int};
    last = until.isBefore(period.end) ? addDays(until, -1).month : 12;
    keys = 12;
  } else {
    final rows = await db.rawQuery(
      'SELECT booking_date AS k, -sum(amount_cents) AS s FROM transactions '
      'WHERE $spendSql AND booking_date >= ? AND booking_date < ? GROUP BY k',
      [iso(period.start), iso(until)],
    );
    byKey = {
      for (final r in rows)
        if (parseIsoDay(r['k'] as String?) case final d?)
          (period.kind == PeriodKind.month ? d.day : d.weekday): r['s'] as int,
    };
    last = daysBetween(period.start, until);
    keys = period.days;
  }
  final values = <int>[];
  var running = 0;
  for (var key = 1; key <= keys && key <= last; key++) {
    running += byKey[key] ?? 0;
    values.add(running);
  }
  return values;
}

/// Spesa degli ultimi n mesi fino a `lastMonthStart` incluso, dal più vecchio.
Future<List<(DateTime, int)>> monthlyBars(DatabaseExecutor db, DateTime lastMonthStart,
    {int n = 12}) async {
  final months = [for (var i = n - 1; i >= 0; i--) addMonths(lastMonthStart, -i)];
  final rows = await db.rawQuery(
    'SELECT substr(booking_date, 1, 7) AS m, -sum(amount_cents) AS s FROM transactions '
    'WHERE $spendSql AND booking_date >= ? AND booking_date < ? GROUP BY m',
    [iso(months.first), iso(addMonths(months.last, 1))],
  );
  final byMonth = {for (final r in rows) r['m'] as String: r['s'] as int};
  return [for (final m in months) (m, byMonth[iso(m).substring(0, 7)] ?? 0)];
}

class CategorySpend {
  const CategorySpend(
      {required this.id,
      required this.name,
      required this.color,
      required this.icon,
      required this.total,
      required this.n,
      required this.pct,
      required this.delta});
  final int? id;
  final String name;
  final String color;
  final String icon;
  final int total;
  final int n;
  final double pct;
  final int delta;
}

Future<List<CategorySpend>> categories(DatabaseExecutor db, DateTime start, DateTime end,
    DateTime prevStart, DateTime prevEnd) async {
  Future<Map<int?, Map<String, Object?>>> grouped(DateTime a, DateTime b) async => {
        for (final r in await db.rawQuery(
          'SELECT category_id, -sum(amount_cents) AS total, count(*) AS n '
          'FROM transactions WHERE $spendSql AND booking_date >= ? AND booking_date < ? '
          'GROUP BY category_id',
          [iso(a), iso(b)],
        ))
          r['category_id'] as int?: r,
      };

  final current = await grouped(start, end), before = await grouped(prevStart, prevEnd);
  final info = {for (final r in await db.query('categories')) r['id'] as int: r};
  final sum = current.values.fold<int>(0, (s, r) => s + (r['total'] as int));
  final total = sum == 0 ? 1 : sum;
  final out = [
    for (final MapEntry(key: id, value: r) in current.entries)
      CategorySpend(
        id: id,
        name: (info[id]?['name'] as String?) ?? 'Senza categoria',
        color: (info[id]?['color'] as String?) ?? '#adb5bd',
        icon: (info[id]?['icon'] as String?) ?? 'tag',
        total: r['total'] as int,
        n: r['n'] as int,
        pct: 100 * (r['total'] as int) / total,
        delta: (r['total'] as int) - ((before[id]?['total'] as int?) ?? 0),
      ),
  ]..sort((a, b) => b.total.compareTo(a.total));
  return out;
}

/// Esercenti con più spesa; last_key apre il pannello con lo storico.
Future<List<Map<String, Object?>>> topMerchants(DatabaseExecutor db, DateTime start, DateTime end,
        {int limit = 8}) =>
    db.rawQuery(
      'SELECT counterparty AS name, -sum(amount_cents) AS total, count(*) AS n, '
      "max(booking_date || '|' || id) AS last_key FROM transactions "
      'WHERE $spendSql AND counterparty IS NOT NULL '
      'AND booking_date >= ? AND booking_date < ? '
      'GROUP BY lower(counterparty) ORDER BY total DESC LIMIT ?',
      [iso(start), iso(end), limit],
    );

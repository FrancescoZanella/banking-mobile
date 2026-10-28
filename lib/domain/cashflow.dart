/// Entrate, uscite, risparmio e riconoscimento dei movimenti ricorrenti.
/// Come per le spese, giroconti e conti nascosti sono sempre esclusi.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/periods.dart';
import 'reports.dart';

// Ricorrente: almeno 3 volte, circa ogni mese, importo simile.
const minOccurrences = 3;
const monthlyDays = (25, 35);
const amountTolerance = 0.2;

class Totals {
  const Totals(this.income, this.expense);
  final int income;
  final int expense;
  int get net => income - expense;

  @override
  bool operator ==(Object other) => other is Totals && other.income == income && other.expense == expense;

  @override
  int get hashCode => Object.hash(income, expense);
}

Future<Totals> totals(DatabaseExecutor db, DateTime start, DateTime end) async {
  final row = (await db.rawQuery(
    'SELECT coalesce(sum(CASE WHEN $incomeSql THEN amount_cents END), 0) AS income, '
    'coalesce(-sum(CASE WHEN $spendSql THEN amount_cents END), 0) AS expense '
    'FROM transactions WHERE booking_date >= ? AND booking_date < ?',
    [iso(start), iso(end)],
  ))
      .first;
  return Totals(row['income'] as int, row['expense'] as int);
}

double? savingsRate(int income, int net) => income > 0 ? 100 * net / income : null;

/// [(inizio mese, totali), ...] dal più vecchio.
Future<List<(DateTime, Totals)>> monthly(DatabaseExecutor db, DateTime lastMonthStart, {int n = 12}) async {
  final months = [for (var i = n - 1; i >= 0; i--) addMonths(lastMonthStart, -i)];
  return [for (final m in months) (m, await totals(db, m, addMonths(m, 1)))];
}

double? averageRate(List<(DateTime, Totals)> series) {
  final income = series.fold<int>(0, (s, e) => s + e.$2.income);
  final net = series.fold<int>(0, (s, e) => s + e.$2.net);
  return savingsRate(income, net);
}

double _median(List<num> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid].toDouble() : (sorted[mid - 1] + sorted[mid]) / 2;
}

class Recurring {
  const Recurring(this.interval, this.typical, this.next);
  final int interval;
  final double typical;
  final DateTime next;
}

/// Dato [(data, centesimi)], restituisce la cadenza se è mensile, altrimenti null.
Recurring? detectRecurring(List<(DateTime, int)> datesAmounts) {
  if (datesAmounts.length < minOccurrences) return null;
  final items = [...datesAmounts]..sort((a, b) {
      final byDate = a.$1.compareTo(b.$1);
      return byDate != 0 ? byDate : a.$2.compareTo(b.$2);
    });
  final months = {for (final i in items) (i.$1.year, i.$1.month)};
  if (months.length < minOccurrences) return null;
  final gaps = [for (var i = 1; i < items.length; i++) daysBetween(items[i - 1].$1, items[i].$1)];
  final interval = _median(gaps);
  if (interval < monthlyDays.$1 || interval > monthlyDays.$2) return null;
  final typical = _median([for (final i in items) i.$2.abs()]);
  final recent = items.sublist(items.length - minOccurrences);
  if (recent.any((i) => (i.$2.abs() - typical).abs() > amountTolerance * typical)) return null;
  final rounded = roundHalfEven(interval);
  return Recurring(rounded, typical, addDays(items.last.$1, rounded));
}

String partyKey(String? name) => (name ?? '').trim().toLowerCase();

/// Movimenti da `since` raggruppati per controparte (o descrizione), dal più vecchio.
Future<Map<String, List<Map<String, Object?>>>> byParty(
    DatabaseExecutor db, String where, DateTime since) async {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final r in await db.rawQuery(
    'SELECT id, booking_date, amount_cents, category_id, '
    'coalesce(counterparty, description) AS party '
    'FROM transactions WHERE $where AND booking_date >= ? '
    'AND coalesce(counterparty, description) IS NOT NULL '
    'ORDER BY booking_date, id',
    [iso(since)],
  )) {
    groups.putIfAbsent(partyKey(r['party'] as String?), () => []).add(r);
  }
  return groups;
}

List<(DateTime, int)> datedAmounts(List<Map<String, Object?>> rows) => [
      for (final r in rows)
        if (parseIsoDay(r['booking_date'] as String?) case final d?) (d, r['amount_cents'] as int),
    ];

class IncomeSource {
  const IncomeSource(this.party, this.total, this.n, this.lastKey, this.icon, this.color, this.recurring);
  final String party;
  final int total;
  final int n;
  final String lastKey;
  final String icon;
  final String color;
  final Recurring? recurring;
}

/// Entrate del periodo per mittente, con le ricorrenti riconosciute sull'ultimo anno.
Future<List<IncomeSource>> incomeSources(
    DatabaseExecutor db, DateTime start, DateTime end, DateTime today,
    {int limit = 10}) async {
  final history = await byParty(db, incomeSql, addDays(today, -400));
  final rows = await db.rawQuery(
    'SELECT coalesce(t.counterparty, t.description) AS party, sum(t.amount_cents) AS total, '
    "count(*) AS n, max(t.booking_date || '|' || t.id) AS last_key, "
    "coalesce(c.icon, 'coin') AS icon, coalesce(c.color, '#80b918') AS color "
    'FROM transactions t LEFT JOIN categories c ON c.id = t.category_id '
    'WHERE t.is_internal = 0 AND t.amount_cents > 0 AND t.$visibleSql '
    'AND t.booking_date >= ? AND t.booking_date < ? '
    'GROUP BY lower(coalesce(t.counterparty, t.description)) ORDER BY total DESC LIMIT ?',
    [iso(start), iso(end), limit],
  );
  return [
    for (final r in rows)
      IncomeSource(
        r['party'] as String,
        r['total'] as int,
        r['n'] as int,
        r['last_key'] as String,
        r['icon'] as String,
        r['color'] as String,
        detectRecurring(datedAmounts(history[partyKey(r['party'] as String?)] ?? [])),
      ),
  ];
}

class CategoryFlow {
  const CategoryFlow(this.id, this.name, this.color, this.icon, this.total, this.n, this.pct);
  final int? id;
  final String name;
  final String color;
  final String icon;

  /// Centesimi, sempre positivi.
  final int total;
  final int n;
  final double pct;
}

/// Uscite ed entrate del periodo divise per categoria, dalla più grande.
/// I giroconti non ci sono: vedi [movedBetweenAccounts].
Future<({List<CategoryFlow> expense, List<CategoryFlow> income})> byCategory(
    DatabaseExecutor db, DateTime start, DateTime end) async {
  Future<List<CategoryFlow>> side(String sign) async {
    final rows = await db.rawQuery(
      "SELECT t.category_id AS id, coalesce(c.name, 'Senza categoria') AS name, "
      "coalesce(c.color, '#adb5bd') AS color, coalesce(c.icon, 'tag') AS icon, "
      'abs(sum(t.amount_cents)) AS total, count(*) AS n '
      'FROM transactions t LEFT JOIN categories c ON c.id = t.category_id '
      'WHERE t.is_internal = 0 AND t.amount_cents $sign 0 AND t.$visibleSql '
      'AND t.booking_date >= ? AND t.booking_date < ? '
      'GROUP BY t.category_id ORDER BY total DESC',
      [iso(start), iso(end)],
    );
    final sum = rows.fold<int>(0, (s, r) => s + (r['total'] as int));
    return [
      for (final r in rows)
        CategoryFlow(r['id'] as int?, r['name'] as String, r['color'] as String, r['icon'] as String,
            r['total'] as int, r['n'] as int, sum == 0 ? 0 : 100 * (r['total'] as int) / sum),
    ];
  }

  return (expense: await side('<'), income: await side('>'));
}

/// Soldi spostati tra i tuoi conti nel periodo: neutri sul totale, mostrati a
/// parte. Ogni giroconto ha un'uscita e un'entrata; se uno dei due conti non è
/// collegato se ne vede uno solo, quindi si prende il lato più grande.
Future<({int cents, int n})> movedBetweenAccounts(DatabaseExecutor db, DateTime start, DateTime end) async {
  final row = (await db.rawQuery(
    'SELECT coalesce(-sum(CASE WHEN amount_cents < 0 THEN amount_cents END), 0) AS out_c, '
    'coalesce(sum(CASE WHEN amount_cents > 0 THEN amount_cents END), 0) AS in_c, '
    'sum(CASE WHEN amount_cents < 0 THEN 1 ELSE 0 END) AS out_n, '
    'sum(CASE WHEN amount_cents > 0 THEN 1 ELSE 0 END) AS in_n '
    'FROM transactions WHERE is_internal = 1 AND $visibleSql AND booking_date >= ? AND booking_date < ?',
    [iso(start), iso(end)],
  ))
      .first;
  final out = row['out_c'] as int, inc = row['in_c'] as int;
  return out >= inc
      ? (cents: out, n: (row['out_n'] as int?) ?? 0)
      : (cents: inc, n: (row['in_n'] as int?) ?? 0);
}

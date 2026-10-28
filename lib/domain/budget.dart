/// Budget mensili e abbonamenti riconosciuti tra le uscite.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/periods.dart';
import '../data/database.dart';
import 'cashflow.dart';
import 'reports.dart';

const warnPct = 80;

/// Un abbonamento è attivo se l'ultimo addebito non è più vecchio di così.
const activeDays = 45;

/// Aumento di prezzo segnalato oltre questa soglia (2%).
const priceIncrease = 0.02;

/// Proiezione a fine mese del ritmo di spesa attuale.
int forecast(int spent, Period period, DateTime today) {
  if (!period.contains(today)) return spent;
  final elapsed = daysBetween(period.start, today) + 1;
  return roundHalfEven(spent / elapsed * period.days);
}

enum BudgetState { ok, warn, over }

class BudgetStatus {
  BudgetStatus(this.limit, this.spent, this.forecast)
      : pct = 100 * spent / limit,
        state = spent > limit
            ? BudgetState.over
            : (100 * spent / limit >= warnPct ? BudgetState.warn : BudgetState.ok);
  final int limit;
  final int spent;
  final int forecast;
  final double pct;
  final BudgetState state;
  int get remaining => limit - spent;
}

BudgetStatus status(int limit, int spent, int projected) => BudgetStatus(limit, spent, projected);

class CategoryBudget {
  const CategoryBudget(this.categoryId, this.name, this.color, this.icon, this.status);
  final int categoryId;
  final String name;
  final String color;
  final String icon;
  final BudgetStatus status;
}

class BudgetOverview {
  const BudgetOverview(this.period, this.daysLeft, this.total, this.categories);
  final Period period;
  final int daysLeft;
  final BudgetStatus? total;
  final List<CategoryBudget> categories;
}

/// Budget del mese corrente: totale (se impostato) e per categoria.
Future<BudgetOverview> overview(DatabaseExecutor db, DateTime today) async {
  final period = periodFor(PeriodKind.month, today);
  final tomorrow = addDays(today, 1);
  final until = tomorrow.isBefore(period.end) ? tomorrow : period.end;
  final spent = {
    for (final r in await db.rawQuery(
      'SELECT category_id, -sum(amount_cents) AS total FROM transactions '
      'WHERE $spendSql AND booking_date >= ? AND booking_date < ? GROUP BY category_id',
      [iso(period.start), iso(until)],
    ))
      r['category_id'] as int?: r['total'] as int,
  };
  final categories = [
    for (final r in await db.rawQuery(
      "SELECT b.amount_cents, c.id, c.name, c.color, coalesce(c.icon, 'tag') AS icon "
      'FROM budgets b JOIN categories c ON c.id = b.category_id ORDER BY c.name',
    ))
      CategoryBudget(
        r['id'] as int,
        r['name'] as String,
        r['color'] as String,
        r['icon'] as String,
        status(r['amount_cents'] as int, spent[r['id']] ?? 0,
            forecast(spent[r['id']] ?? 0, period, today)),
      ),
  ]..sort((a, b) => b.status.pct.compareTo(a.status.pct));

  BudgetStatus? total;
  final totalLimit = int.tryParse(await getSetting(db, 'budget_total', '0') ?? '0') ?? 0;
  if (totalLimit > 0) {
    final allSpent = spent.values.fold<int>(0, (s, v) => s + v);
    total = status(totalLimit, allSpent, forecast(allSpent, period, today));
  }
  return BudgetOverview(period, daysBetween(today, period.end) - 1, total, categories);
}

class BudgetAlert {
  const BudgetAlert(this.name, this.status);
  final String name;
  final BudgetStatus status;
}

/// Budget all'80% o superati, per l'avviso in Home.
Future<List<BudgetAlert>> alerts(DatabaseExecutor db, DateTime today) async {
  final data = await overview(db, today);
  return [
    if (data.total case final t? when t.state != BudgetState.ok) BudgetAlert('Totale del mese', t),
    for (final c in data.categories)
      if (c.status.state != BudgetState.ok) BudgetAlert(c.name, c.status),
  ];
}

class Subscription {
  const Subscription(this.key, this.name, this.amount, this.previous, this.next, this.txId, this.icon, this.color);
  final String key;
  final String name;
  final int amount;
  final int? previous;
  final DateTime next;
  final String txId;
  final String icon;
  final String color;
}

class Subscriptions {
  const Subscriptions(this.items, this.ignored);
  final List<Subscription> items;
  final List<String> ignored;
  int get monthly => items.fold(0, (s, i) => s + i.amount);
}

/// Uscite ricorrenti ancora attive, esclusi i falsi positivi segnalati.
Future<Subscriptions> subscriptions(DatabaseExecutor db, DateTime today) async {
  final ignored = {for (final r in await db.query('subscription_ignores')) r['party'] as String};
  final info = {for (final r in await db.query('categories')) r['id'] as int: r};
  final out = <Subscription>[];
  final groups = await byParty(db, spendSql, addDays(today, -400));
  for (final MapEntry(key: key, value: rows) in groups.entries) {
    if (ignored.contains(key)) continue;
    final recurring = detectRecurring(datedAmounts(rows));
    final last = rows.last;
    final lastDay = parseIsoDay(last['booking_date'] as String?);
    if (recurring == null || lastDay == null || daysBetween(lastDay, today) > activeDays) continue;
    final amount = -(last['amount_cents'] as int);
    final before = -(rows[rows.length - 2]['amount_cents'] as int);
    final cat = info[last['category_id']];
    out.add(Subscription(
      key,
      last['party'] as String,
      amount,
      amount > before * (1 + priceIncrease) ? before : null,
      recurring.next,
      last['id'] as String,
      (cat?['icon'] as String?) ?? 'receipt',
      (cat?['color'] as String?) ?? '#adb5bd',
    ));
  }
  out.sort((a, b) => a.next.compareTo(b.next));
  return Subscriptions(out, ignored.toList()..sort());
}

Future<void> ignoreSubscription(DatabaseExecutor db, String name) => db.rawInsert(
      'INSERT OR IGNORE INTO subscription_ignores (party, created_at) VALUES (?, ?)',
      [partyKey(name), utcNow()],
    );

Future<void> restoreSubscription(DatabaseExecutor db, String key) =>
    db.delete('subscription_ignores', where: 'party = ?', whereArgs: [key]);

/// Esito di un'azione delle pagine Budget e Categorie, come i flash del web.
class Outcome {
  const Outcome(this.text, {this.ok = true});
  final String text;
  final bool ok;
}

/// Spese che possono avere un budget, senza quelle che lo hanno già.
Future<List<Map<String, Object?>>> freeCategories(DatabaseExecutor db) => db.rawQuery(
      "SELECT id, name FROM categories WHERE kind = 'expense' "
      'AND id NOT IN (SELECT category_id FROM budgets) ORDER BY name',
    );

/// Budget del mese: [target] è 'total' oppure l'id di una categoria di spesa.
/// Importo 0 = rimuovi.
Future<Outcome> saveBudget(DatabaseExecutor db, String target, String? amount) async {
  final cents = parseEuro(amount);
  if (cents == null) return const Outcome('Importo non valido: scrivi per esempio 250 oppure 1.600,50.', ok: false);
  if (target == 'total') {
    await setSetting(db, 'budget_total', '$cents');
  } else {
    final id = int.tryParse(target);
    final ok = id != null &&
        (await db.rawQuery("SELECT 1 FROM categories WHERE id = ? AND kind = 'expense'", [id])).isNotEmpty;
    if (!ok) return const Outcome('Si può dare un budget solo a una categoria di spesa.', ok: false);
    if (cents == 0) {
      await db.delete('budgets', where: 'category_id = ?', whereArgs: [id]);
    } else {
      await db.rawInsert(
        'INSERT INTO budgets (category_id, amount_cents) VALUES (?, ?) '
        'ON CONFLICT(category_id) DO UPDATE SET amount_cents = excluded.amount_cents',
        [id, cents],
      );
    }
  }
  return Outcome(cents > 0 ? 'Budget salvato.' : 'Budget rimosso.');
}

Future<Outcome> deleteBudget(DatabaseExecutor db, String target) async {
  if (target == 'total') {
    await setSetting(db, 'budget_total', '0');
  } else {
    await db.delete('budgets', where: 'category_id = ?', whereArgs: [int.tryParse(target)]);
  }
  return const Outcome('Budget rimosso.');
}

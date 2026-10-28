/// Aggregazioni per Home e Conti. I giroconti sono neutri sui totali di tutti i
/// conti insieme (i soldi restano tuoi); contano solo guardando un conto alla volta.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/config.dart';
import '../core/dates.dart';
import '../core/periods.dart';
import '../sync/sync.dart';

/// I conti nascosti continuano a sincronizzarsi ma restano fuori dai report.
const visibleSql = 'account_id NOT IN (SELECT id FROM accounts WHERE hidden = 1)';

/// Non investimenti: comprare titoli è risparmio, non spesa (e venderli non è un'entrata).
const noInvestmentSql =
    '(category_id IS NULL OR category_id NOT IN (SELECT id FROM categories WHERE investment = 1))';

/// Come [noInvestmentSql], per le query con la tabella dei movimenti chiamata `t`.
const noInvestmentT =
    '(t.category_id IS NULL OR t.category_id NOT IN (SELECT id FROM categories WHERE investment = 1))';

/// Uscite che contano come spesa: non giroconti, non investimenti, conti visibili.
const spendSql = 'is_internal = 0 AND amount_cents < 0 AND $noInvestmentSql AND $visibleSql';

/// Entrate che contano: non giroconti, non investimenti, conti visibili.
const incomeSql = 'is_internal = 0 AND amount_cents > 0 AND $noInvestmentSql AND $visibleSql';

/// Ordine dei movimenti: dal giorno più recente; nello stesso giorno (le banche
/// non danno l'ora) prima quelli scaricati per ultimi.
const txOrder = 't.booking_date DESC, t.created_at DESC, t.rowid DESC';

(String, String) monthBounds(DateTime month) {
  final start = DateTime.utc(month.year, month.month);
  return (iso(start), iso(addMonths(start, 1)));
}

/// Conti con banca, consenso e saldo preferito.
Future<List<Map<String, Object?>>> accountsOverview(DatabaseExecutor db) async {
  final accounts = await db.rawQuery(
    'SELECT a.*, b.label AS bank_label, c.valid_until, c.status AS consent_status '
    'FROM accounts a JOIN banks b ON b.key = a.bank_key '
    'LEFT JOIN consents c ON c.id = a.consent_id '
    'ORDER BY b.label, a.id',
  );
  final out = <Map<String, Object?>>[];
  for (final acc in accounts) {
    final latest = await db.rawQuery(
      'SELECT * FROM balances WHERE account_id = ? AND fetched_at = '
      '(SELECT max(fetched_at) FROM balances WHERE account_id = ?)',
      [acc['id'], acc['id']],
    );
    out.add({...acc, 'balance': preferredBalance(latest)});
  }
  return out;
}

Map<String, int> totalsByCurrency(List<Map<String, Object?>> accounts) {
  final totals = <String, int>{};
  for (final acc in accounts) {
    final balance = acc['balance'] as Map<String, Object?>?;
    if (balance == null) continue;
    final currency = (balance['currency'] as String?) ?? 'EUR';
    totals[currency] = (totals[currency] ?? 0) + (balance['amount_cents'] as int);
  }
  return totals;
}

/// Entrate, uscite e numero di movimenti del mese (giroconti esclusi).
Future<Map<String, int>> monthSummary(DatabaseExecutor db, DateTime month) async {
  final (start, end) = monthBounds(month);
  final row = (await db.rawQuery(
    'SELECT coalesce(sum(CASE WHEN amount_cents > 0 THEN amount_cents END), 0) AS income, '
    'coalesce(sum(CASE WHEN amount_cents < 0 THEN -amount_cents END), 0) AS expense, '
    'count(*) AS n FROM transactions '
    'WHERE is_internal = 0 AND $noInvestmentSql AND $visibleSql AND booking_date >= ? AND booking_date < ?',
    [start, end],
  ))
      .first;
  return {'income': row['income'] as int, 'expense': row['expense'] as int, 'n': row['n'] as int};
}

Future<List<Map<String, Object?>>> spendingByCategory(DatabaseExecutor db, DateTime month) async {
  final (start, end) = monthBounds(month);
  return db.rawQuery(
    "SELECT coalesce(c.name, 'Senza categoria') AS name, "
    "coalesce(c.color, '#adb5bd') AS color, coalesce(c.icon, 'tag') AS icon, "
    '-sum(t.amount_cents) AS total '
    'FROM transactions t LEFT JOIN categories c ON c.id = t.category_id '
    'WHERE t.is_internal = 0 AND $noInvestmentT AND t.amount_cents < 0 AND t.$visibleSql '
    'AND t.booking_date >= ? AND t.booking_date < ? '
    'GROUP BY c.id ORDER BY total DESC',
    [start, end],
  );
}

/// Saldo totale a fine mese, ricostruito all'indietro dal saldo attuale.
Future<({List<DateTime> months, List<int> values})> balanceTrend(
    DatabaseExecutor db, List<Map<String, Object?>> accounts,
    {int n = 12, String currency = 'EUR', DateTime? today}) async {
  final t = today ?? DateTime.now();
  final last = DateTime.utc(t.year, t.month);
  final months = [for (var i = n - 1; i >= 0; i--) addMonths(last, -i)];
  final ids = [
    for (final a in accounts)
      if (a['balance'] != null &&
          (((a['balance'] as Map)['currency'] as String?) ?? 'EUR') == currency)
        a['id'] as int,
  ];
  if (ids.isEmpty) return (months: months, values: <int>[]);
  final current = accounts
      .where((a) => ids.contains(a['id']))
      .fold<int>(0, (s, a) => s + ((a['balance'] as Map)['amount_cents'] as int));
  final marks = List.filled(ids.length, '?').join(',');
  final values = <int>[];
  for (final m in months) {
    final monthEnd = iso(addMonths(m, 1));
    final after = (await db.rawQuery(
      'SELECT coalesce(sum(amount_cents), 0) AS s FROM transactions '
      'WHERE account_id IN ($marks) AND booking_date >= ?',
      [...ids, monthEnd],
    ))
        .first['s'] as int;
    values.add(current - after);
  }
  return (months: months, values: values);
}

class ConsentAlert {
  const ConsentAlert(this.key, this.label, this.days, {required this.expired});
  final String key;
  final String label;
  final int days;
  final bool expired;
}

/// Banche con consenso scaduto o in scadenza entro 14 giorni.
Future<List<ConsentAlert>> consentAlerts(DatabaseExecutor db, {DateTime? now}) async {
  final n = (now ?? DateTime.now()).toUtc();
  const warn = Duration(days: AppConfig.expiryWarningDays);
  final alerts = <ConsentAlert>[];
  final rows = await db.rawQuery(
    'SELECT b.key, b.label, c.valid_until, c.status FROM banks b '
    'JOIN consents c ON c.bank_key = b.key '
    'WHERE c.id = (SELECT max(id) FROM consents WHERE bank_key = b.key)',
  );
  for (final r in rows) {
    if (r['status'] == 'revoked') continue;
    final until = DateTime.parse(r['valid_until'] as String);
    final key = r['key'] as String, label = r['label'] as String;
    if (r['status'] != 'active' || !until.isAfter(n)) {
      alerts.add(ConsentAlert(key, label, 0, expired: true));
    } else if (until.difference(n) <= warn) {
      alerts.add(ConsentAlert(key, label, until.difference(n).inDays, expired: false));
    }
  }
  return alerts;
}

const txSelect =
    'SELECT t.*, b.label AS bank_label, coalesce(a.nickname, a.name) AS account_name, '
    'a.currency AS account_currency, c.name AS category_name, c.kind AS category_kind, '
    'coalesce(c.investment, 0) AS category_investment, '
    "coalesce(c.color, '#adb5bd') AS category_color, coalesce(c.icon, 'tag') AS category_icon "
    'FROM transactions t JOIN accounts a ON a.id = t.account_id '
    'JOIN banks b ON b.key = a.bank_key LEFT JOIN categories c ON c.id = t.category_id';

/// Ultimi movimenti dei conti visibili, per il feed della Home.
Future<List<Map<String, Object?>>> recentTransactions(DatabaseExecutor db, {int limit = 40}) =>
    db.rawQuery(
      '$txSelect WHERE a.hidden = 0 '
      'ORDER BY $txOrder LIMIT ?',
      [limit],
    );

/// [(data, [movimenti]), ...] mantenendo l'ordine.
List<(String?, List<Map<String, Object?>>)> groupByDay(List<Map<String, Object?>> rows) {
  final groups = <(String?, List<Map<String, Object?>>)>[];
  for (final row in rows) {
    final d = row['booking_date'] as String?;
    if (groups.isEmpty || groups.last.$1 != d) groups.add((d, []));
    groups.last.$2.add(row);
  }
  return groups;
}

class TransactionHistory {
  const TransactionHistory(this.count, this.total, this.first, this.recent);
  final int count;
  final int total;
  final String? first;
  final List<Map<String, Object?>> recent;
}

/// Movimento con lo storico della stessa controparte (pannello di dettaglio).
Future<(Map<String, Object?>?, TransactionHistory?)> transactionDetail(
    DatabaseExecutor db, String txId) async {
  final rows = await db.rawQuery('$txSelect WHERE t.id = ?', [txId]);
  if (rows.isEmpty) return (null, null);
  final tx = rows.first;
  final counterparty = tx['counterparty'] as String?;
  if (counterparty == null || counterparty.isEmpty) return (tx, null);
  final same = await db.rawQuery(
    '$txSelect WHERE lower(t.counterparty) = lower(?) ORDER BY $txOrder',
    [counterparty],
  );
  return (
    tx,
    TransactionHistory(
      same.length,
      same.fold<int>(0, (s, r) => s + (r['amount_cents'] as int)),
      same.isEmpty ? null : same.last['booking_date'] as String?,
      same.where((r) => r['id'] != tx['id']).take(6).toList(),
    ),
  );
}

/// Movimenti: filtri, totali, CSV e cambio categoria. Come routes/transactions.py.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/periods.dart';
import 'categorize.dart';
import 'reports.dart';

/// «Mostra altri» allarga la lista di questo numero di movimenti.
const pageSize = 100;

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Scorciatoie del chip «Periodo»: etichetta e (dal, al inclusi) da oggi.
final Map<String, (String, (DateTime, DateTime) Function(DateTime))> periodShortcuts = {
  'month': ('Questo mese', (d) => (DateTime.utc(d.year, d.month), d)),
  'prev': (
    'Mese scorso',
    (d) => (previous(periodFor(PeriodKind.month, d)).start, addDays(DateTime.utc(d.year, d.month), -1)),
  ),
  '3m': ('Ultimi 3 mesi', (d) => (addDays(d, -91), d)),
  'year': ("Quest'anno", (d) => (DateTime.utc(d.year), d)),
};

/// "12,50" o "12.5" → centesimi; null se non è un numero.
int? amountCents(String? value) {
  final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
  return parsed == null || parsed.isNaN || parsed.isInfinite ? null : (parsed * 100).round();
}

/// Filtri della lista Movimenti (i parametri della pagina web). Conti e
/// categorie si possono scegliere in più insieme.
class TxFilter {
  const TxFilter({
    this.q = '',
    this.accounts = const {},
    this.categories = const {},
    this.period,
    this.from,
    this.to,
    this.direction,
    this.min,
    this.max,
    this.hidden = false,
  });

  final String q;
  final Set<int> accounts;

  /// Id delle categorie, più 'none' per «Senza categoria».
  final Set<String> categories;
  final String? period;
  final String? from;
  final String? to;

  /// 'in' o 'out'; null = entrambi.
  final String? direction;
  final String? min;
  final String? max;

  /// Include i conti nascosti.
  final bool hidden;

  static const _unset = Object();

  TxFilter copyWith({
    String? q,
    Set<int>? accounts,
    Set<String>? categories,
    Object? period = _unset,
    Object? from = _unset,
    Object? to = _unset,
    Object? direction = _unset,
    Object? min = _unset,
    Object? max = _unset,
    bool? hidden,
  }) =>
      TxFilter(
        q: q ?? this.q,
        accounts: accounts ?? this.accounts,
        categories: categories ?? this.categories,
        period: period == _unset ? this.period : period as String?,
        from: from == _unset ? this.from : from as String?,
        to: to == _unset ? this.to : to as String?,
        direction: direction == _unset ? this.direction : direction as String?,
        min: min == _unset ? this.min : min as String?,
        max: max == _unset ? this.max : max as String?,
        hidden: hidden ?? this.hidden,
      );

  bool get _hasRange => (from ?? '').isNotEmpty || (to ?? '').isNotEmpty;

  /// Un conto solo: i giroconti contano come movimenti veri.
  bool get singleAccount => accounts.length == 1;

  /// Il periodo tradotto in dal/al; un intervallo esplicito vince sulla scorciatoia.
  (String?, String?) range([DateTime? now]) {
    final shortcut = periodShortcuts[period];
    if (shortcut != null && !_hasRange) {
      final (start, end) = shortcut.$2(today(now));
      return (iso(start), iso(end));
    }
    return (from, to);
  }

  /// "Azzera filtri" tiene solo la ricerca.
  TxFilter cleared() => TxFilter(q: q);

  /// Nessun filtro e nessuna ricerca: la lista mostra tutto.
  bool get isEmpty =>
      q.trim().isEmpty &&
      accounts.isEmpty &&
      categories.isEmpty &&
      period == null &&
      !_hasRange &&
      direction == null &&
      (min ?? '').isEmpty &&
      (max ?? '').isEmpty &&
      !hidden;
}

/// Query SQL con i filtri; stesso ordine e stesse colonne del web.
(String, List<Object?>) buildQuery(TxFilter f, [DateTime? now]) {
  final where = <String>[], params = <Object?>[];
  String marks(int n) => List.filled(n, '?').join(', ');
  if (f.accounts.isNotEmpty) {
    where.add('t.account_id IN (${marks(f.accounts.length)})');
    params.addAll(f.accounts);
  }
  final ids = [for (final c in f.categories) ?int.tryParse(c)];
  final none = f.categories.contains('none');
  if (none || ids.isNotEmpty) {
    where.add('(${[
      if (none) 't.category_id IS NULL',
      if (ids.isNotEmpty) 't.category_id IN (${marks(ids.length)})',
    ].join(' OR ')})');
    params.addAll(ids);
  }
  final (from, to) = f.range(now);
  if (_dateRe.hasMatch(from ?? '')) {
    where.add('t.booking_date >= ?');
    params.add(from);
  }
  if (_dateRe.hasMatch(to ?? '')) {
    where.add('t.booking_date <= ?');
    params.add(to);
  }
  final q = f.q.trim();
  if (q.isNotEmpty) {
    where.add('(t.counterparty LIKE ? OR t.description LIKE ?)');
    params.addAll(['%$q%', '%$q%']);
  }
  if (amountCents(f.min) case final low?) {
    where.add('abs(t.amount_cents) >= ?');
    params.add(low);
  }
  if (amountCents(f.max) case final high?) {
    where.add('abs(t.amount_cents) <= ?');
    params.add(high);
  }
  if (f.direction == 'out') where.add('t.amount_cents < 0');
  if (f.direction == 'in') where.add('t.amount_cents > 0');
  if (!f.hidden) where.add('a.hidden = 0');

  final sql = where.isEmpty ? txSelect : '$txSelect WHERE ${where.join(' AND ')}';
  return ('$sql ORDER BY $txOrder', params);
}

class TxPage {
  const TxPage(this.days, this.count, this.spent, this.received, this.shown);

  /// (giorno, movimenti, totale del giorno; giroconti solo filtrando un conto solo).
  final List<(String?, List<Map<String, Object?>>, int)> days;
  final int count;
  final int spent;
  final int received;
  final int shown;

  bool get hasMore => count > shown;
}

/// Una «pagina» della lista: i primi [page] × [pageSize] movimenti e i totali.
Future<TxPage> loadTransactions(DatabaseExecutor db, TxFilter f, {int page = 1, DateTime? now}) async {
  final (sql, params) = buildQuery(f, now);
  // Giroconti: neutri sui totali di tutti i conti, reali guardando un conto solo.
  // Investimenti: mai uscite o spese (restano solo nell'elenco). Giroconti: fuori
  // dai totali di tutti i conti, veri guardando un conto solo.
  final internal = ' AND $noInvestmentSql${f.singleAccount ? '' : ' AND is_internal = 0'}';
  final summary = (await db.rawQuery(
    'SELECT count(*) AS n, '
    'coalesce(-sum(CASE WHEN amount_cents < 0$internal THEN amount_cents END), 0) AS spent, '
    'coalesce(sum(CASE WHEN amount_cents > 0$internal THEN amount_cents END), 0) AS received '
    'FROM ($sql)',
    params,
  ))
      .first;
  final rows = await db.rawQuery('$sql LIMIT ?', [...params, page * pageSize]);
  return TxPage(
    [
      for (final (day, items) in groupByDay(rows))
        (
          day,
          items,
          items
              .where((t) => t['category_investment'] != 1 && (f.singleAccount || t['is_internal'] != 1))
              .fold(0, (s, t) => s + (t['amount_cents'] as int)),
        ),
    ],
    summary['n'] as int,
    summary['spent'] as int,
    summary['received'] as int,
    rows.length,
  );
}

String? _shortDate(String? value) {
  final d = _dateRe.hasMatch(value ?? '') ? parseIsoDay(value) : null;
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${two(d.year % 100)}';
}

/// Etichette dei filtri attivi (gruppo → testo della pillola).
Map<String, String> chipLabels(TxFilter f, List<Map<String, Object?>> accounts,
    List<Map<String, Object?>> categories) {
  final labels = <String, String>{};
  if (f.accounts.isNotEmpty) {
    final a = accounts.where((a) => f.accounts.contains(a['id'])).toList();
    labels['account'] = a.length == 1 ? '${a.first['bank']} · ${a.first['label']}' : '${f.accounts.length} conti';
  }
  if (f.categories.length == 1) {
    final only = f.categories.first;
    final c = categories.where((c) => '${c['id']}' == only);
    labels['category'] = only == 'none' ? 'Senza categoria' : (c.isEmpty ? 'Categoria' : c.first['name'] as String);
  } else if (f.categories.isNotEmpty) {
    labels['category'] = '${f.categories.length} categorie';
  }
  if (periodShortcuts.containsKey(f.period) && !f._hasRange) {
    labels['period'] = periodShortcuts[f.period]!.$1;
  } else if (f._hasRange) {
    final parts = [_shortDate(f.from), _shortDate(f.to)].whereType<String>();
    labels['period'] = parts.isEmpty ? 'Periodo' : parts.join(' – ');
  }
  if (f.direction == 'in' || f.direction == 'out') {
    labels['direction'] = f.direction == 'in' ? 'Entrate' : 'Uscite';
  }
  if ((f.min ?? '').isNotEmpty || (f.max ?? '').isNotEmpty) {
    final low = amountCents(f.min), high = amountCents(f.max);
    labels['amount'] = [if (low != null) 'da ${money(low)}', if (high != null) 'a ${money(high)}'].join(' ');
  }
  if (f.hidden) labels['extra'] = 'Con conti nascosti';
  return labels;
}

/// Toglie un gruppo di filtri (la ✕ sulla sua pillola).
TxFilter withoutGroup(TxFilter f, String group) => switch (group) {
      'account' => f.copyWith(accounts: const {}),
      'category' => f.copyWith(categories: const {}),
      'period' => f.copyWith(period: null, from: null, to: null),
      'direction' => f.copyWith(direction: null),
      'amount' => f.copyWith(min: null, max: null),
      'extra' => f.copyWith(hidden: false),
      _ => f,
    };

/// Conti per il filtro «Conti», anche quelli nascosti.
Future<List<Map<String, Object?>>> filterAccounts(DatabaseExecutor db) => db.rawQuery(
      'SELECT a.id, coalesce(a.nickname, a.name, b.label) AS label, b.label AS bank, a.hidden '
      'FROM accounts a JOIN banks b ON b.key = a.bank_key ORDER BY b.label, a.id',
    );

/// Categorie dalla più usata alla meno usata (menu del dettaglio e filtro).
Future<List<Map<String, Object?>>> allCategories(DatabaseExecutor db) => db.rawQuery(
      'SELECT c.*, (SELECT count(*) FROM transactions t WHERE t.category_id = c.id) AS uses '
      'FROM categories c ORDER BY uses DESC, c.name',
    );

/// Evita formule eseguite da Excel (CSV injection) da descrizioni bancarie.
String _csvSafe(String? value) {
  final v = value ?? '';
  return v.isNotEmpty && '=+-@'.contains(v[0]) ? "'$v" : v;
}

String _csvField(String value) =>
    RegExp('[";\r\n]').hasMatch(value) ? '"${value.replaceAll('"', '""')}"' : value;

/// CSV con «;» e BOM, come /transactions.csv: tutti i movimenti filtrati.
Future<String> exportCsv(DatabaseExecutor db, TxFilter f, {DateTime? now}) async {
  final (sql, params) = buildQuery(f, now);
  final out = StringBuffer('﻿');
  void row(List<String> values) => out.write('${values.map(_csvField).join(';')}\r\n');
  row(['data', 'banca', 'conto', 'controparte', 'descrizione', 'importo', 'valuta', 'categoria', 'stato', 'giroconto']);
  for (final r in await db.rawQuery(sql, params)) {
    final cents = r['amount_cents'] as int;
    row([
      r['booking_date'] as String? ?? '',
      r['bank_label'] as String,
      r['account_name'] as String? ?? '',
      _csvSafe(r['counterparty'] as String?),
      _csvSafe(r['description'] as String?),
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100},${(cents.abs() % 100).toString().padLeft(2, '0')}',
      r['currency'] as String? ?? '',
      r['category_name'] as String? ?? '',
      r['status'] as String? ?? '',
      r['is_internal'] == 1 ? 'sì' : '',
    ]);
  }
  return out.toString();
}

/// Cambio categoria dal dettaglio. [categoryId] null = torna automatica.
/// Restituisce il messaggio da mostrare, se c'è.
Future<String?> setCategory(Database db, String txId, int? categoryId, {bool makeRule = false}) =>
    db.transaction((t) async {
      final txs = await t.query('transactions', where: 'id = ?', whereArgs: [txId]);
      if (txs.isEmpty) return null;
      if (categoryId == null) {
        await t.rawUpdate('UPDATE transactions SET category_source = NULL WHERE id = ?', [txId]);
        await recategorize(t);
        return null;
      }
      final cats = await t.query('categories', where: 'id = ?', whereArgs: [categoryId]);
      if (cats.isEmpty) return null;
      final category = cats.first;
      final transfer = category['kind'] == 'transfer';
      await _setManual(t, txId, category);
      final counterparty = txs.first['counterparty'] as String?;
      final pattern = rulePattern(counterparty);
      if (makeRule && transfer) {
        return 'Segnato come giroconto. Per i giroconti non si creano regole: '
            'vanno indicati movimento per movimento.';
      }
      if (makeRule && pattern.length >= 3) {
        await t.rawInsert(
          'INSERT INTO category_rules (category_id, field, pattern, priority) '
          "VALUES (?, 'text', ?, 10) ON CONFLICT(field, pattern) "
          'DO UPDATE SET category_id = excluded.category_id, priority = 10',
          [categoryId, pattern],
        );
        await recategorize(t);
        return 'Regola creata: «$counterparty» → ${category['name']}.';
      }
      return null;
    });

/// Testo della regola creata da «Applica a tutti i movimenti di …».
String rulePattern(String? counterparty) => (counterparty ?? '').trim().toLowerCase();

/// Categoria scelta a mano: un giroconto diventa interno, il resto no.
Future<void> _setManual(DatabaseExecutor t, String txId, Map<String, Object?> category) => t.rawUpdate(
      "UPDATE transactions SET category_id = ?, category_source = 'manual', is_internal = ? WHERE id = ?",
      [category['id'], category['kind'] == 'transfer' ? 1 : 0, txId],
    );

/// Stessa categoria a più movimenti (selezione multipla), senza regole.
Future<void> setCategoryMany(Database db, Iterable<String> txIds, int categoryId) => db.transaction((t) async {
      final cats = await t.query('categories', where: 'id = ?', whereArgs: [categoryId]);
      if (cats.isEmpty) return;
      for (final id in txIds) {
        await _setManual(t, id, cats.first);
      }
    });

/// Com'erano dei movimenti (ed eventualmente una regola) prima di un cambio di
/// categoria: serve ad «Annulla».
class CategoryUndo {
  CategoryUndo._(this._rows, this._rulePattern, this._rule);
  final List<Map<String, Object?>> _rows;
  final String? _rulePattern;

  /// La regola con lo stesso testo che c'era prima, se c'era.
  final Map<String, Object?>? _rule;
}

/// Fotografia prima del cambio. [rulePattern]: il testo della regola che il
/// cambio potrebbe creare o modificare.
Future<CategoryUndo> categorySnapshot(DatabaseExecutor db, List<String> txIds, {String? rulePattern}) async {
  final rows = await db.rawQuery(
    'SELECT id, category_id, category_source, is_internal FROM transactions '
    'WHERE id IN (${List.filled(txIds.length, '?').join(', ')})',
    txIds,
  );
  final rules = rulePattern == null
      ? const <Map<String, Object?>>[]
      : await db.query('category_rules', where: "field = 'text' AND pattern = ?", whereArgs: [rulePattern]);
  return CategoryUndo._(rows, rulePattern, rules.firstOrNull);
}

/// «Annulla»: rimette movimenti e regola com'erano.
Future<void> undoCategory(Database db, CategoryUndo undo) => db.transaction((t) async {
      for (final r in undo._rows) {
        await t.rawUpdate(
          'UPDATE transactions SET category_id = ?, category_source = ?, is_internal = ? WHERE id = ?',
          [r['category_id'], r['category_source'], r['is_internal'], r['id']],
        );
      }
      final pattern = undo._rulePattern;
      if (pattern == null) return;
      if (undo._rule case final rule?) {
        await t.rawUpdate(
          "UPDATE category_rules SET category_id = ?, priority = ? WHERE field = 'text' AND pattern = ?",
          [rule['category_id'], rule['priority'], pattern],
        );
      } else {
        await t.rawDelete("DELETE FROM category_rules WHERE field = 'text' AND pattern = ?", [pattern]);
      }
      // La regola tolta o ripristinata cambia anche gli altri movimenti automatici.
      await recategorize(t);
    });

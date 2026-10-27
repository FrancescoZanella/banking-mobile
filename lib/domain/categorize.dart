/// Categorizzazione: override manuale > giroconto > regole testo/MCC > default.
///
/// Un giroconto si riconosce solo in modi affidabili: l'IBAN della controparte è
/// uno dei tuoi conti, la controparte sei tu (il tuo nome di intestatario), oppure
/// lo hai messo tu in una categoria di tipo giroconto.
library;

import 'package:sqflite_common/sqlite_api.dart';

// Solo lettere (anche accentate): in Dart \w è solo ASCII, quindi \p{L}.
final _word = RegExp(r'\p{L}+', unicode: true);

List<String> _words(String? text) =>
    [for (final m in _word.allMatches((text ?? '').toLowerCase())) m.group(0)!];

/// Nomi degli intestatari dei tuoi conti, come insiemi di parole (2–4 parole).
Future<List<Set<String>>> ownNames(DatabaseExecutor db) async {
  final names = <Set<String>>[];
  for (final r in await db.rawQuery('SELECT DISTINCT name FROM accounts WHERE name IS NOT NULL')) {
    final words = _words(r['name'] as String?);
    if (words.length >= 2 && words.length <= 4) {
      final set = words.toSet();
      if (!names.any((n) => n.length == set.length && n.containsAll(set))) names.add(set);
    }
  }
  return names;
}

Iterable<List<String>> _permutations(List<String> items) sync* {
  if (items.length <= 1) {
    yield items;
    return;
  }
  for (var i = 0; i < items.length; i++) {
    final rest = [...items]..removeAt(i);
    for (final p in _permutations(rest)) {
      yield [items[i], ...p];
    }
  }
}

/// La controparte sei tu: nome identico (in qualsiasi ordine), oppure, se la
/// banca non fornisce la controparte, nome e cognome di seguito nella descrizione.
bool isOwnParty(String? counterparty, String? description, List<Set<String>> names) {
  if (counterparty != null && counterparty.isNotEmpty) {
    final words = _words(counterparty).toSet();
    return names.any((n) => n.length == words.length && n.containsAll(words));
  }
  final text = ' ${_words(description).join(' ')} ';
  for (final name in names) {
    for (final order in _permutations(name.toList())) {
      if (text.contains(' ${order.join(' ')} ')) return true;
    }
  }
  return false;
}

class _Rule {
  const _Rule(this.field, this.pattern, this.categoryId);
  final String field;
  final String pattern;
  final int categoryId;
}

Future<List<_Rule>> _loadRules(DatabaseExecutor db) async {
  // Le regole non possono rendere un movimento un giroconto.
  final rows = await db.rawQuery(
    'SELECT r.field, r.pattern, r.category_id FROM category_rules r '
    "JOIN categories c ON c.id = r.category_id WHERE c.kind != 'transfer' "
    'ORDER BY r.priority DESC, length(r.pattern) DESC, r.id',
  );
  return [
    for (final r in rows)
      _Rule(r['field'] as String, (r['pattern'] as String).toLowerCase(), r['category_id'] as int),
  ];
}

int? _pickCategory(Map<String, Object?> tx, List<_Rule> rules, Map<String, int> ids) {
  if (tx['is_internal'] == 1) return ids['Giroconti'];
  final text = ' ${tx['counterparty'] ?? ''} ${tx['description'] ?? ''} '.toLowerCase();
  final mcc = (tx['mcc'] as String?) ?? '';
  for (final rule in rules) {
    if (rule.field == 'text' && text.contains(rule.pattern)) return rule.categoryId;
    if (rule.field == 'mcc' && mcc.isNotEmpty && mcc == rule.pattern) return rule.categoryId;
  }
  return (tx['amount_cents'] as int) > 0 ? ids['Altre entrate'] : ids['Altre spese'];
}

/// Segna come giroconti i movimenti verso/da un tuo conto o verso/da te stesso.
/// I movimenti categorizzati a mano non si toccano: lì decide la categoria.
Future<void> detectInternalTransfers(DatabaseExecutor db) async {
  final ownIbans = {
    for (final r in await db.rawQuery('SELECT iban FROM accounts WHERE iban IS NOT NULL'))
      (r['iban'] as String).replaceAll(' ', '').toUpperCase(),
  };
  final names = await ownNames(db);
  final internal = <String>[];
  for (final r in await db.rawQuery(
      'SELECT id, counterparty, counterparty_iban, description FROM transactions '
      "WHERE category_source IS NOT 'manual'")) {
    final iban = ((r['counterparty_iban'] as String?) ?? '').replaceAll(' ', '').toUpperCase();
    if (ownIbans.contains(iban) ||
        isOwnParty(r['counterparty'] as String?, r['description'] as String?, names)) {
      internal.add(r['id'] as String);
    }
  }
  await db.rawUpdate(
      "UPDATE transactions SET is_internal = 0 WHERE category_source IS NOT 'manual'");
  final batch = db.batch();
  for (final id in internal) {
    batch.rawUpdate('UPDATE transactions SET is_internal = 1 WHERE id = ?', [id]);
  }
  await batch.commit(noResult: true);
}

/// Ricalcola giroconti e categorie automatiche (le manuali non si toccano).
Future<void> recategorize(DatabaseExecutor db) async {
  await detectInternalTransfers(db);
  final rules = await _loadRules(db);
  final ids = {
    for (final r in await db.rawQuery('SELECT id, name FROM categories'))
      r['name'] as String: r['id'] as int,
  };
  final rows = await db.rawQuery(
    'SELECT id, counterparty, description, mcc, amount_cents, is_internal '
    "FROM transactions WHERE category_source IS NOT 'manual'",
  );
  final batch = db.batch();
  for (final r in rows) {
    batch.rawUpdate(
      "UPDATE transactions SET category_id = ?, category_source = 'auto' WHERE id = ?",
      [_pickCategory(r, rules, ids), r['id']],
    );
  }
  await batch.commit(noResult: true);
}

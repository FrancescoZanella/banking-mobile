/// Categorie e regole automatiche: le azioni della pagina Categorie del web.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../data/defaults.dart';
import 'budget.dart' show Outcome;
import 'categorize.dart';

const kinds = {'expense': 'spesa', 'income': 'entrata', 'transfer': 'giroconto'};

final _colorRe = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Categorie con il numero di movimenti, come le elenca il web.
Future<List<Map<String, Object?>>> categoriesWithCount(DatabaseExecutor db) => db.rawQuery(
      'SELECT c.*, (SELECT count(*) FROM transactions t WHERE t.category_id = c.id) AS n '
      'FROM categories c ORDER BY c.kind, c.name',
    );

Future<List<Map<String, Object?>>> rules(DatabaseExecutor db) => db.rawQuery(
      'SELECT r.*, c.name AS category_name FROM category_rules r '
      'JOIN categories c ON c.id = r.category_id ORDER BY c.name, r.field, r.pattern',
    );

Future<Outcome> createCategory(DatabaseExecutor db,
    {required String name, required String kind, required String color, String? icon}) async {
  final trimmed = name.trim();
  final clean = trimmed.substring(0, trimmed.length < 60 ? trimmed.length : 60);
  final chosen = (icon == null || icon.isEmpty) ? defaultIcon : icon;
  if (clean.isEmpty || !kinds.containsKey(kind) || !_colorRe.hasMatch(color) || !iconChoices.contains(chosen)) {
    return const Outcome('Dati della categoria non validi.', ok: false);
  }
  if ((await db.query('categories', where: 'name = ?', whereArgs: [clean])).isNotEmpty) {
    return const Outcome('Esiste già una categoria con questo nome.', ok: false);
  }
  await db.insert('categories', {'name': clean, 'kind': kind, 'color': color, 'icon': chosen});
  return Outcome('Categoria «$clean» aggiunta.');
}

/// Solo icone dell'elenco: false (e nessuna modifica) per le altre.
Future<bool> setIcon(DatabaseExecutor db, int categoryId, String icon) async {
  if (!iconChoices.contains(icon)) return false;
  await db.update('categories', {'icon': icon}, where: 'id = ?', whereArgs: [categoryId]);
  return true;
}

/// I movimenti della categoria tornano alla categorizzazione automatica.
Future<void> deleteCategory(Database db, int categoryId) => db.transaction((t) async {
      await t.rawUpdate('UPDATE transactions SET category_source = NULL WHERE category_id = ?', [categoryId]);
      await t.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
      await recategorize(t);
    });

Future<Outcome> createRule(Database db, {required String field, required String pattern, required int categoryId}) =>
    db.transaction((t) async {
      final lowered = pattern.trim().toLowerCase();
      final clean = lowered.substring(0, lowered.length < 80 ? lowered.length : 80);
      if (!(field == 'text' || field == 'mcc') || clean.length < 2) {
        return const Outcome('Regola non valida.', ok: false);
      }
      final category = await t.query('categories', where: 'id = ?', whereArgs: [categoryId]);
      if (category.isEmpty) return const Outcome('Regola non valida.', ok: false);
      if (category.first['kind'] == 'transfer') {
        return const Outcome(
            "I giroconti si riconoscono solo dall'IBAN dei tuoi conti o scegliendo "
            'la categoria a mano sul movimento, non con una regola.',
            ok: false);
      }
      await t.rawInsert(
        'INSERT INTO category_rules (category_id, field, pattern, priority) VALUES (?, ?, ?, 5) '
        'ON CONFLICT(field, pattern) DO UPDATE SET category_id = excluded.category_id',
        [categoryId, field, clean],
      );
      await recategorize(t);
      return const Outcome('Regola salvata e movimenti ricategorizzati.');
    });

Future<void> deleteRule(Database db, int ruleId) => db.transaction((t) async {
      await t.delete('category_rules', where: 'id = ?', whereArgs: [ruleId]);
      await recategorize(t);
    });

/// Movimenti «da categorizzare»: quelli che le regole non hanno saputo
/// classificare. Alimentano le notifiche e il riquadro in Home.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import 'reports.dart';

/// Categorie di ripiego: un movimento finito qui è «dubbio».
const fallbackCategories = ['Altre spese', 'Altre entrate'];

/// Notifiche solo per movimenti recenti: niente raffiche dopo giorni senza sync.
const notifyMaxAgeDays = 7;

/// Il riquadro in Home guarda all'ultimo mese.
const boxDays = 30;

/// Movimenti visibili, non giroconti, non scelti a mano, senza categoria o in
/// una categoria di ripiego.
final _doubtful = 'a.hidden = 0 AND t.is_internal = 0 '
    "AND t.category_source IS NOT 'manual' "
    'AND (t.category_id IS NULL OR t.category_id IN (SELECT id FROM categories WHERE name IN '
    "(${fallbackCategories.map((c) => "'$c'").join(', ')})))";

/// Per il riquadro in Home: i dubbi dell'ultimo mese, dal più recente.
Future<List<Map<String, Object?>>> toCategorize(DatabaseExecutor db, {DateTime? now}) => db.rawQuery(
      '$txSelect WHERE $_doubtful AND t.booking_date >= ? '
      'ORDER BY t.booking_date DESC, t.id',
      [iso(addDays(today(now), -boxDays))],
    );

/// Da notificare: dubbi recenti non ancora segnalati. Lo storico scaricato
/// collegando o rinnovando una banca è già segnato come notificato.
Future<List<Map<String, Object?>>> toNotify(DatabaseExecutor db, {DateTime? now}) => db.rawQuery(
      '$txSelect WHERE $_doubtful AND t.notified_at IS NULL '
      'AND (t.booking_date IS NULL OR t.booking_date >= ?) '
      'ORDER BY t.booking_date, t.id',
      [iso(addDays(today(now), -notifyMaxAgeDays))],
    );

/// Segna i movimenti come notificati: non verranno più segnalati.
Future<void> markNotified(DatabaseExecutor db, Iterable<String> ids, {DateTime? now}) async {
  final batch = db.batch();
  for (final id in ids) {
    batch.rawUpdate('UPDATE transactions SET notified_at = ? WHERE id = ?', [utcNow(now), id]);
  }
  await batch.commit(noResult: true);
}

/// Orari della sincronizzazione automatica: le 7, le 14 e le 23 ora italiana
/// (scelta dell'utente del 30/10/2026). Sono le uniche: niente sync
/// all'apertura né a mano, così si resta sotto il limite PSD2 di ~4 accessi
/// al giorno senza l'utente presente.
library;

const syncHours = [7, 14, 23];

/// Ultima domenica del mese alle 01:00 UTC: l'ora in cui l'UE cambia ora.
DateTime _changeover(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, last.day - last.weekday % 7, 1);
}

/// Scarto dell'ora italiana da UTC: +2 con l'ora legale (dall'ultima domenica
/// di marzo all'ultima di ottobre), +1 il resto dell'anno.
Duration italyOffset(DateTime utc) {
  final summer = !utc.isBefore(_changeover(utc.year, 3)) && utc.isBefore(_changeover(utc.year, 10));
  return Duration(hours: summer ? 2 : 1);
}

/// Il prossimo orario di sincronizzazione dopo [now], in UTC.
DateTime nextSyncSlot(DateTime now) {
  final utc = now.toUtc();
  final local = utc.add(italyOffset(utc));
  for (var day = 0; day < 3; day++) {
    for (final hour in syncHours) {
      final wall = DateTime.utc(local.year, local.month, local.day + day, hour);
      // Mai a cavallo del cambio d'ora (avviene alle 2-3 di notte).
      final slot = wall.subtract(italyOffset(wall.subtract(const Duration(hours: 1))));
      if (slot.isAfter(utc)) return slot;
    }
  }
  throw StateError('nessun orario di sincronizzazione');
}

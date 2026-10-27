/// Date "di calendario" senza ora: sempre DateTime UTC a mezzanotte, così
/// somme di giorni e confronti non risentono dell'ora legale.
library;

const monthsIt = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio',
  'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
];

DateTime day(int year, int month, int dayOfMonth) => DateTime.utc(year, month, dayOfMonth);

DateTime today([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}

DateTime addDays(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day + days);

int daysBetween(DateTime from, DateTime to) => to.difference(from).inDays;

/// 2026-10-03 → "2026-10-03" (come `date.isoformat()`).
String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "2026-10-03" (anche con l'ora dopo) → data; null se non valida.
DateTime? parseIsoDay(String? value) {
  if (value == null || value.length < 10) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final result = DateTime.utc(y, mo, d);
  return result.month == mo && result.day == d ? result : null;
}

/// Timestamp UTC ISO al secondo, come `db.utcnow()` del web.
String utcNow([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc();
  return '${iso(DateTime.utc(n.year, n.month, n.day))}T'
      '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:'
      '${n.second.toString().padLeft(2, '0')}+00:00';
}

/// "Oggi", "Ieri", "24 ottobre" (con l'anno se non è quello corrente).
String dayLabel(String? value, [DateTime? ref]) {
  if (value == null || value.isEmpty) return 'Senza data';
  final d = parseIsoDay(value);
  if (d == null) return value;
  final t = today(ref);
  if (d == t) return 'Oggi';
  if (daysBetween(d, t) == 1) return 'Ieri';
  final label = '${d.day} ${monthsIt[d.month - 1]}';
  return d.year == t.year ? label : '$label ${d.year}';
}

/// "2026-10-03" → "03/10/2026".
String dateIt(String? value) {
  if (value == null || value.isEmpty) return '—';
  final d = parseIsoDay(value);
  if (d == null) return value;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Timestamp UTC salvato nel DB → data e ora locali.
String localTime(String? value) {
  if (value == null || value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final l = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String daysLeft(int days) {
  if (days <= 0) return 'scade oggi';
  return days == 1 ? 'scade domani' : 'scade tra $days giorni';
}

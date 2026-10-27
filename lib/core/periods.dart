import 'dates.dart';

enum PeriodKind { week, month, year }

/// Periodo [start, end) di una settimana, un mese o un anno.
class Period {
  const Period(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime start;
  final DateTime end; // escluso

  int get days => daysBetween(start, end);

  String get label {
    if (kind == PeriodKind.year) return '${start.year}';
    if (kind == PeriodKind.month) return '${monthsIt[start.month - 1]} ${start.year}';
    final last = addDays(end, -1);
    if (start.month == last.month) {
      return '${start.day}–${last.day} ${monthsIt[last.month - 1]} ${last.year}';
    }
    return '${start.day} ${monthsIt[start.month - 1]} – '
        '${last.day} ${monthsIt[last.month - 1]} ${last.year}';
  }

  /// Nome breve, per «vs …» e per «Speso a …».
  String get short {
    if (kind == PeriodKind.month) return monthsIt[start.month - 1];
    if (kind == PeriodKind.year) return '${start.year}';
    return 'sett. prima';
  }

  /// Con la preposizione giusta: «rispetto a settembre / al 2025 / …».
  String get versus {
    if (kind == PeriodKind.month) return 'a $short';
    if (kind == PeriodKind.year) return 'al $short';
    return 'alla settimana prima';
  }

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is Period && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

DateTime addMonths(DateTime d, int months) {
  final index = d.year * 12 + d.month - 1 + months;
  return DateTime.utc(index ~/ 12, index % 12 + 1, 1);
}

Period periodFor(PeriodKind kind, DateTime ref) {
  switch (kind) {
    case PeriodKind.week:
      final start = addDays(ref, -(ref.weekday - 1)); // lunedì
      return Period(kind, start, addDays(start, 7));
    case PeriodKind.year:
      return Period(kind, DateTime.utc(ref.year), DateTime.utc(ref.year + 1));
    case PeriodKind.month:
      final start = DateTime.utc(ref.year, ref.month);
      return Period(kind, start, addMonths(start, 1));
  }
}

Period previous(Period p) => periodFor(p.kind, addDays(p.start, -1));

Period following(Period p) => periodFor(p.kind, p.end);

/// Fine del tratto già trascorso: oggi incluso, o tutto il periodo se passato.
DateTime elapsedEnd(Period p, DateTime today) => p.contains(today) ? addDays(today, 1) : p.end;

/// Stesso tratto del periodo precedente: «allo stesso giorno» del mese prima.
(DateTime, DateTime) comparableWindow(Period p, DateTime today) {
  final prev = previous(p);
  if (!p.contains(today)) return (prev.start, prev.end);
  final length = daysBetween(p.start, today) + 1;
  final end = addDays(prev.start, length);
  return (prev.start, end.isBefore(prev.end) ? end : prev.end);
}

List<String> axisLabels(Period p) {
  if (p.kind == PeriodKind.year) return [for (final m in monthsIt) m.substring(0, 3)];
  if (p.kind == PeriodKind.week) return const ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
  return [for (var d = 1; d <= (p.days > 31 ? p.days : 31); d++) '$d'];
}

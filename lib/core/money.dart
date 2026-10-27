/// Importi: sempre centesimi interi, mai double.
library;

const _symbols = {'EUR': '€', 'USD': r'$', 'GBP': '£', 'CHF': 'CHF'};

/// Importo della banca ("12.34", -5.5, …) in centesimi con segno.
///
/// L'indicatore DBIT/CRDT, se presente, decide il segno; arrotondamento
/// commerciale al centesimo (0.005 → 1), come `Decimal.ROUND_HALF_UP`.
int toCents(Object? amount, [String? indicator]) {
  final text = amount?.toString().trim() ?? '';
  final match = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$').firstMatch(text);
  if (match == null || (match.group(2)!.isEmpty && (match.group(3) ?? '').isEmpty)) {
    throw FormatException('Importo non valido: $amount');
  }
  final negative = match.group(1) == '-';
  final whole = BigInt.parse(match.group(2)!.isEmpty ? '0' : match.group(2)!);
  final fraction = (match.group(3) ?? '').padRight(3, '0');
  var cents = whole * BigInt.from(100) + BigInt.parse(fraction.substring(0, 2));
  if (int.parse(fraction[2]) >= 5) cents += BigInt.one;
  final value = cents.toInt();
  if (indicator == 'DBIT') return -value;
  if (indicator == 'CRDT') return value;
  return negative ? -value : value;
}

/// 123456 → "1.234,56 €".
String money(int? cents, [String? currency = 'EUR']) {
  if (cents == null) return '—';
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
    grouped.write(whole[i]);
  }
  final frac = (abs % 100).toString().padLeft(2, '0');
  final code = currency ?? 'EUR';
  return '$sign$grouped,$frac ${_symbols[code] ?? code}';
}

String maskIban(String? iban) {
  if (iban == null || iban.isEmpty) return '—';
  return '${iban.substring(0, iban.length < 4 ? iban.length : 4)} •••• '
      '${iban.substring(iban.length < 4 ? 0 : iban.length - 4)}';
}

/// Arrotondamento all'intero con le metà verso il pari (come `round()` di Python).
int roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final diff = value - floor;
  if (diff > 0.5) return floor.toInt() + 1;
  if (diff < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}

/// Limite dei budget: 10 milioni di euro.
const maxBudgetCents = 1000000000;

/// "1.600", "1600,50", "250 €" → centesimi; null se non valido o negativo.
int? parseEuro(String? input) {
  var text = (input ?? '').replaceAll('€', '').replaceAll(' ', '').trim();
  if (text.contains(',')) {
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(text)) {
    text = text.replaceAll('.', ''); // «1.600» all'italiana = milleseicento
  }
  final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(text);
  if (match == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  // Come Decimal.to_integral_value: arrotonda al centesimo più vicino.
  var cents = BigInt.parse(match.group(1)!) * BigInt.from(100) +
      BigInt.parse(fraction.substring(0, 2));
  if (fraction.length > 2 && int.parse(fraction[2]) >= 5) cents += BigInt.one;
  if (cents > BigInt.from(maxBudgetCents)) return null;
  return cents.toInt();
}

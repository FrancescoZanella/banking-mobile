import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app/services.dart';
import 'theme.dart';

/// Componenti grafici condivisi: avatar degli esercenti, importi nascondibili,
/// sagome di caricamento, numeri animati e schermate vuote.

// ── Avatar degli esercenti ─────────────────────────────────────────────────

/// Colori degli avatar: uno fisso per esercente, scelto dal nome.
const _avatarColors = [
  Color(0xFF7C83FF),
  Color(0xFFE76F51),
  Color(0xFF2A9D8F),
  Color(0xFFF4A261),
  Color(0xFF457B9D),
  Color(0xFF9C27B0),
  Color(0xFF43AA8B),
  Color(0xFFBC4749),
  Color(0xFF277DA1),
  Color(0xFF90BE6D),
];

/// «ESSELUNGA MILANO» → «EM», «Netflix» → «NE». Solo lettere e cifre.
String merchantInitials(String name) {
  final words = name.split(RegExp(r'[^A-Za-zÀ-ÿ0-9]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final text = words.length == 1 ? words.first.substring(0, words.first.length.clamp(1, 2)) : words[0][0] + words[1][0];
  return text.toUpperCase();
}

/// Colore stabile per lo stesso esercente (FNV-1a sul nome in minuscolo).
Color merchantColor(String name) {
  var hash = 0x811c9dc5;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return _avatarColors[hash % _avatarColors.length];
}

/// Cerchio con le iniziali dell'esercente e, in basso a destra, il badge con
/// l'icona della categoria (se data). Niente loghi da internet: nessun dato esce dal telefono.
class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar({super.key, required this.name, this.categoryIcon, this.categoryColor, this.size = 40});
  final String name;
  final IconData? categoryIcon;
  final Color? categoryColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = merchantColor(name);
    final badge = size * .44;
    final (icon, iconColor) = (categoryIcon, categoryColor);
    return SizedBox(
      width: size + 2,
      height: size + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: .22), shape: BoxShape.circle),
            child: Text(
              merchantInitials(name),
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * .36, letterSpacing: .5),
            ),
          ),
          if (icon != null && iconColor != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(iconColor.withValues(alpha: .3), AppColors.surface),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Icon(icon, size: badge * .58, color: iconColor),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Importi nascondibili ───────────────────────────────────────────────────

/// Sfoca [child] quando «Nascondi importi» è attivo. Per i lettori di schermo
/// il contenuto sparisce del tutto.
class Sensitive extends StatelessWidget {
  const Sensitive({super.key, required this.child, this.sigma = 7});
  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Services.of(context).hideAmounts,
    builder: (context, hidden, child) => hidden
        ? ExcludeSemantics(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
              child: child,
            ),
          )
        : child!,
    child: child,
  );
}

/// Un testo con un importo: come [Text], ma si sfoca con «Nascondi importi».
/// La chiave va al [Text] interno, così i test lo trovano come prima.
class Amount extends StatelessWidget {
  const Amount(this.data, {Key? key, this.style, this.textAlign, this.maxLines, this.overflow})
    : _textKey = key,
      super(key: null);
  final String data;
  final Key? _textKey;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Sensitive(
    child: Text(data, key: _textKey, style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow),
  );
}

/// Occhio per attivare o togliere «Nascondi importi».
class HideAmountsButton extends StatelessWidget {
  const HideAmountsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: services.hideAmounts,
      builder: (context, hidden, _) => IconButton(
        key: const Key('hide-amounts'),
        tooltip: hidden ? 'Mostra importi' : 'Nascondi importi',
        icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.muted),
        onPressed: () => services.setHideAmounts(!hidden),
      ),
    );
  }
}

// ── Numeri animati ─────────────────────────────────────────────────────────

/// Importo che «scorre» fino al valore quando cambia (la prima volta da zero).
class AnimatedAmount extends StatelessWidget {
  const AnimatedAmount(this.cents, {super.key, required this.format, this.style, this.textKey});
  final int cents;
  final String Function(int cents) format;
  final TextStyle? style;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: cents.toDouble()),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => Amount(format(value.round()), key: textKey, style: style),
  );
}

// ── Sagome di caricamento ──────────────────────────────────────────────────

/// Sagome grigie che pulsano al posto della rotellina, nella forma della pagina:
/// una scheda grande in alto e righe come quelle dei movimenti.
class SkeletonPage extends StatefulWidget {
  const SkeletonPage({super.key, this.hero = true, this.rows = 6, this.embedded = false});
  final bool hero;
  final int rows;

  /// Dentro una lista che scorre già (Analisi, Flussi): niente scorrimento proprio.
  final bool embedded;

  @override
  State<SkeletonPage> createState() => _SkeletonPageState();
}

class _SkeletonPageState extends State<SkeletonPage> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: .45,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height, {double radius = 6}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(radius)),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Caricamento',
    child: FadeTransition(
      opacity: _pulse,
      child: _wrap(
        Column(
          key: const Key('skeleton'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hero) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(110, 12),
                      const SizedBox(height: 12),
                      _bar(190, 30),
                      const SizedBox(height: 18),
                      Row(children: [_bar(120, 70, radius: 14), const SizedBox(width: 10), _bar(120, 70, radius: 14)]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < widget.rows; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            _bar(40, 40, radius: 20),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _bar(i.isEven ? 150 : 110, 12),
                                  const SizedBox(height: 8),
                                  _bar(i.isEven ? 90 : 130, 10),
                                ],
                              ),
                            ),
                            _bar(56, 12),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _wrap(Widget column) => widget.embedded
      ? column
      : SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: column,
        );
}

// ── Schermate vuote ────────────────────────────────────────────────────────

/// Icona in un cerchio, una frase e, se serve, un suggerimento o un'azione.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.hint, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: .14), shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.accent, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 10), TextButton(onPressed: onAction, child: Text(action!))],
      ],
    ),
  );
}

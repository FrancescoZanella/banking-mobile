import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../domain/to_categorize.dart';
import '../domain/transactions.dart';
import 'categorize_ui.dart';
import 'polish.dart';
import 'theme.dart';
import 'widgets.dart';

/// Quante categorie mostrare come pulsanti grandi in «Smista».
const sortQuickCount = 6;

/// «Smista»: i movimenti da categorizzare uno alla volta, con le categorie più
/// scelte come pulsanti grandi. Un tocco salva e passa al successivo;
/// «Indietro» annulla l'ultima scelta.
class SortScreen extends StatefulWidget {
  const SortScreen({super.key});

  @override
  State<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends State<SortScreen> {
  /// I movimenti all'apertura: la lista non cambia mentre si smista.
  List<Map<String, Object?>>? _rows;
  Map<bool, List<Map<String, Object?>>> _quick = const {};
  int _index = 0;
  int _done = 0;
  bool _makeRule = false;
  bool _busy = false;

  /// Per «Indietro»: posizione e stato prima di ogni scelta.
  final _history = <(int, CategoryUndo?)>[];

  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    _load();
  }

  Future<void> _load() async {
    final db = Services.of(context).db;
    final rows = await toCategorize(db);
    final quick = {
      for (final income in [false, true]) income: await quickCategories(db, income: income, limit: sortQuickCount),
    };
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _quick = quick;
    });
  }

  Map<String, Object?>? get _current {
    final rows = _rows;
    return rows != null && _index < rows.length ? rows[_index] : null;
  }

  Future<void> _choose(int categoryId) async {
    final t = _current;
    if (t == null || _busy) return;
    final s = Services.of(context);
    final txId = t['id'] as String;
    setState(() => _busy = true);
    final undo = await categorySnapshot(s.db, [txId],
        rulePattern: _makeRule ? rulePattern(t['counterparty'] as String?) : null);
    await setCategory(s.db, txId, categoryId, makeRule: _makeRule);
    await s.dismissNotification(txId);
    s.sync.notifyChanged();
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _history.add((_index, undo));
      _index++;
      _done++;
      _makeRule = false;
      _busy = false;
    });
  }

  Future<void> _other() async {
    final t = _current;
    if (t == null) return;
    final categoryId = await pickCategory(context, income: (t['amount_cents'] as int) > 0);
    if (categoryId != null) await _choose(categoryId);
  }

  void _skip() => setState(() {
        _history.add((_index, null));
        _index++;
        _makeRule = false;
      });

  Future<void> _back() async {
    if (_history.isEmpty || _busy) return;
    final (index, undo) = _history.removeLast();
    final s = Services.of(context);
    if (undo != null) {
      await undoCategory(s.db, undo);
      s.sync.notifyChanged();
      _done--;
    }
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final t = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smista'),
        actions: [
          if (_history.isNotEmpty)
            TextButton.icon(
              key: const Key('sort-back'),
              onPressed: _back,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Indietro'),
            ),
        ],
      ),
      body: rows == null
          ? const SkeletonPage(rows: 2)
          : t == null
              ? _finished(rows.length)
              : _card(t, rows.length),
    );
  }

  Widget _finished(int total) => Center(
        child: EmptyState(
          key: const Key('sort-done'),
          icon: Icons.celebration_outlined,
          title: total == 0 ? 'Niente da smistare' : 'Tutto smistato!',
          hint: total == 0
              ? 'Tutti i movimenti dell\'ultimo mese hanno una categoria.'
              : '$_done ${_done == 1 ? 'movimento categorizzato' : 'movimenti categorizzati'}.',
          action: 'Fine',
          onAction: () => Navigator.of(context).pop(),
        ),
      );

  Widget _card(Map<String, Object?> t, int total) {
    final cents = t['amount_cents'] as int;
    final quick = _quick[cents > 0] ?? const [];
    final counterparty = t['counterparty'] as String?;
    final description = t['description'] as String?;
    final day = t['booking_date'] as String?;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _index / total,
              minHeight: 5,
              backgroundColor: AppColors.surface2,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('${_index + 1} di $total', key: const Key('sort-progress'), style: const TextStyle(color: AppColors.muted)),
      ]),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween(begin: const Offset(.25, 0), end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Card(
          key: ValueKey(t['id']),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(children: [
              TxAvatar(tx: t, size: 64),
              const SizedBox(height: 12),
              Text(txTitle(t),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              if (counterparty != null && description != null && description != counterparty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
              const SizedBox(height: 8),
              Amount(signedMoney(cents, t['currency'] as String?),
                  style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w700, color: cents > 0 ? AppColors.pos : AppColors.text)),
              const SizedBox(height: 4),
              Text(
                [
                  dayLabel(day),
                  t['bank_label'] as String,
                  if (t['status'] == 'PDNG') 'in attesa',
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted),
              ),
              if (t['category_name'] case final String current)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Ora: $current', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 20),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3,
        children: [
          for (final c in quick)
            _CategoryButton(
              key: Key('sort-cat-${c['id']}'),
              name: c['name'] as String,
              icon: c['icon'] as String?,
              color: c['color'] as String?,
              onTap: _busy ? null : () => _choose(c['id'] as int),
            ),
          _CategoryButton(
            key: const Key('sort-other'),
            name: 'Altra categoria…',
            onTap: _busy ? null : _other,
          ),
        ],
      ),
      if (counterparty != null && rulePattern(counterparty).length >= 3)
        CheckboxListTile(
          key: const Key('sort-rule'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _makeRule,
          onChanged: (v) => setState(() => _makeRule = v ?? false),
          title: Text('Applica a tutti i movimenti di «$counterparty»', style: const TextStyle(fontSize: 14)),
        ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          key: const Key('sort-skip'),
          onPressed: _busy ? null : _skip,
          child: const Text('Salta per ora'),
        ),
      ),
    ]);
  }
}

/// Pulsante grande di una categoria in «Smista».
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({super.key, required this.name, this.icon, this.color, required this.onTap});
  final String name;
  final String? icon;
  final String? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              if (color != null)
                CategoryAvatar(icon: icon, color: color, size: 30)
              else
                const Icon(Icons.more_horiz, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ),
            ]),
          ),
        ),
      );
}

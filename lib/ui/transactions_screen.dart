import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../domain/transactions.dart';
import 'categorize_ui.dart';
import 'polish.dart';
import 'theme.dart';
import 'widgets.dart';

/// Condivide il CSV (nel telefono: foglio di condivisione di Android).
typedef ShareCsv = Future<void> Function(String csv);

Future<void> shareCsvFile(String csv) => SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: 'movimenti.csv')],
      fileNameOverrides: ['movimenti.csv'],
    ));

/// Movimenti: ricerca, pannello dei filtri, totali, raggruppamento per giorno,
/// «Mostra altri» ed export CSV. Come transactions.html del web.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.initial = const TxFilter(), this.shareCsv = shareCsvFile});
  final TxFilter initial;
  final ShareCsv shareCsv;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _Lists {
  _Lists(this.accounts, this.categories);
  final List<Map<String, Object?>> accounts;
  final List<Map<String, Object?>> categories;
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late TxFilter _filter = widget.initial;
  late final _search = TextEditingController(text: widget.initial.q);
  Timer? _debounce;
  int _page = 1;
  Future<(TxPage, _Lists)>? _data;
  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = Services.of(context);
    if (_services != services) {
      _services?.sync.removeListener(_reload);
      _services = services..sync.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _services?.sync.removeListener(_reload);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final data = _load(Services.of(context));
    setState(() {
      _data = data;
    });
  }

  Future<(TxPage, _Lists)> _load(AppServices s) async => (
        await loadTransactions(s.db, _filter, page: _page),
        _Lists(await filterAccounts(s.db), await allCategories(s.db)),
      );

  /// Nuovi filtri: la lista riparte dai primi movimenti.
  void _apply(TxFilter f) {
    _filter = f;
    _page = 1;
    _selected.clear(); // niente movimenti selezionati e poi nascosti dai filtri
    _reload();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _apply(_filter.copyWith(q: value)));
  }

  Future<void> _export() async {
    final csv = await exportCsv(Services.of(context).db, _filter);
    await widget.shareCsv(csv);
  }

  /// Selezione multipla: id → importo (per proporre prima le categorie giuste).
  final _selected = <String, int>{};

  void _toggle(Map<String, Object?> t) => setState(() {
        final id = t['id'] as String;
        if (_selected.remove(id) == null) _selected[id] = t['amount_cents'] as int;
      });

  void _selectAll(TxPage page) => setState(() {
        for (final (_, items, _) in page.days) {
          for (final t in items) {
            _selected[t['id'] as String] = t['amount_cents'] as int;
          }
        }
      });

  Future<void> _categorizeSelected() async {
    final signs = {for (final cents in _selected.values) cents > 0};
    final categoryId = await pickCategory(context,
        income: signs.length == 1 ? signs.single : null,
        title: 'Categoria per ${_selected.length} movimenti');
    if (categoryId == null || !mounted) return;
    await applyCategory(context, _selected.keys.toList(), categoryId);
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(TxPage, _Lists)>(
      future: _data,
      builder: (context, snap) {
        final data = snap.data;
        // Indietro chiude la selezione invece di lasciare la pagina.
        return PopScope(
          canPop: _selected.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Stack(children: [
            _scroll(snap, data),
            if (_selected.isNotEmpty && data != null) _selectionBar(data.$1),
          ]),
        );
      },
    );
  }

  /// Barra in basso durante la selezione multipla.
  Widget _selectionBar(TxPage page) => Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: Material(
          key: const Key('selection-bar'),
          color: AppColors.surface3,
          elevation: 6,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(children: [
              IconButton(
                key: const Key('selection-close'),
                tooltip: 'Chiudi selezione',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              ),
              Expanded(
                child: Text('${_selected.length} selezionat${_selected.length == 1 ? 'o' : 'i'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(key: const Key('select-all'), onPressed: () => _selectAll(page), child: const Text('Tutti')),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: const Key('selection-category'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _categorizeSelected,
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Categoria'),
              ),
            ]),
          ),
        ),
      );

  Widget _scroll(AsyncSnapshot<(TxPage, _Lists)> snap, (TxPage, _Lists)? data) => CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList.list(children: [
            Row(children: [
              const Expanded(child: Text('Movimenti', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700))),
              IconButton(
                key: const Key('export-csv'),
                tooltip: 'Esporta CSV',
                icon: const Icon(Icons.ios_share),
                onPressed: _export,
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('tx-search'),
                  controller: _search,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cerca esercente o descrizione',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              _apply(_filter.copyWith(q: ''));
                            },
                          ),
                  ),
                ),
              ),
              if (data != null) ...[const SizedBox(width: 8), _filterButton(data.$2)],
            ]),
            if (data != null) _pills(data.$2),
            const SizedBox(height: 12),
            if (data != null) _tiles(data.$1),
          ]),
        ),
        if (snap.hasError)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Impossibile caricare i movimenti.')),
          )
        else if (data == null)
          const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: SkeletonPage(embedded: true, hero: false)))
        else ..._list(data.$1),
      ]);

  /// Pulsante «Filtri» accanto alla ricerca, con il numero di filtri attivi.
  Widget _filterButton(_Lists lists) {
    final n = chipLabels(_filter, lists.accounts, lists.categories).length;
    return IconButton.filled(
      key: const Key('open-filters'),
      tooltip: 'Filtri',
      style: IconButton.styleFrom(
        backgroundColor: n > 0 ? AppColors.accent : AppColors.surface2,
        foregroundColor: AppColors.text,
        fixedSize: const Size(48, 48),
      ),
      onPressed: () => _openFilters(lists),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        backgroundColor: AppColors.text,
        textColor: AppColors.bg,
        child: const Icon(Icons.tune),
      ),
    );
  }

  /// Filtri attivi come pillole piccole che vanno a capo; la ✕ toglie il gruppo.
  Widget _pills(_Lists lists) {
    final labels = chipLabels(_filter, lists.accounts, lists.categories);
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final MapEntry(key: group, value: label) in labels.entries)
          InputChip(
            key: Key('chip-$group'),
            label: Text(label),
            labelStyle: const TextStyle(fontSize: 13),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.surface2,
            side: BorderSide.none,
            shape: const StadiumBorder(),
            deleteIcon: const Icon(Icons.close, size: 14),
            onPressed: () => _openFilters(lists),
            onDeleted: () => _apply(withoutGroup(_filter, group)),
          ),
        ActionChip(
          key: const Key('clear-filters'),
          label: const Text('Azzera', style: TextStyle(color: AppColors.accent, fontSize: 13)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          onPressed: () => _apply(_filter.cleared()),
        ),
      ]),
    );
  }

  Future<void> _openFilters(_Lists lists) async {
    final result = await showModalBottomSheet<TxFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _FiltersSheet(filter: _filter, lists: lists),
    );
    if (mounted && result != null) _apply(result);
  }

  Widget _tiles(TxPage page) {
    Widget tile(String label, String value, {Color? color, bool amount = true}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  child: amount
                      ? Amount(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color))
                      : Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
                ),
              ]),
            ),
          ),
        );
    return Row(children: [
      tile('Uscite', money(page.spent)),
      const SizedBox(width: 8),
      tile('Entrate', money(page.received), color: AppColors.pos),
      const SizedBox(width: 8),
      tile('Movimenti', '${page.count}', amount: false),
    ]);
  }

  List<Widget> _list(TxPage page) => [
        if (page.days.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Center(
                  child: _filter.isEmpty
                      ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Nessun movimento')
                      : EmptyState(
                          icon: Icons.search_off,
                          title: 'Nessun movimento con questi filtri',
                          hint: 'Prova a togliere qualche filtro.',
                          action: 'Azzera filtri',
                          onAction: () => _apply(_filter.cleared()),
                        ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: page.days.length,
            itemBuilder: (context, i) {
              final (day, items, total) = page.days[i];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DayHeader(day, total: total),
                Card(
                  key: Key('day-${day ?? 'none'}'),
                  child: Column(children: [
                    for (final t in items)
                      FeedItem(
                        tx: t,
                        onChanged: _reload,
                        selected: _selected.isEmpty ? null : _selected.containsKey(t['id']),
                        onSelect: () => _toggle(t),
                        onLongPress: () => _toggle(t),
                      ),
                  ]),
                ),
              ]);
            },
          ),
        ),
        if (page.hasMore)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(children: [
                OutlinedButton(
                  key: const Key('show-more'),
                  onPressed: () {
                    _page++;
                    _reload();
                  },
                  child: const Text('Mostra altri'),
                ),
                Text('${page.shown} di ${page.count}', style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
          ),
        // Spazio per la barra della selezione multipla, che copre il fondo.
        SliverToBoxAdapter(child: SizedBox(height: _selected.isEmpty ? 32 : 96)),
      ];
}

/// Tutti i filtri in un pannello: si sceglie con calma, poi «Mostra risultati».
/// Conti e categorie a scelta multipla.
class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.filter, required this.lists});
  final TxFilter filter;
  final _Lists lists;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late TxFilter _f = widget.filter;
  late final _min = TextEditingController(text: widget.filter.min ?? '');
  late final _max = TextEditingController(text: widget.filter.max ?? '');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _set(TxFilter f) => setState(() => _f = f);

  Set<T> _toggle<T>(Set<T> set, T value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  Future<void> _pickRange() async {
    final from = parseIsoDay(_f.from), to = parseIsoDay(_f.to);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(2000),
      lastDate: today(),
      initialDateRange: from != null && to != null && !to.isBefore(from) ? DateTimeRange(start: from, end: to) : null,
      helpText: 'Dal / al',
    );
    if (range == null || !mounted) return;
    _set(_f.copyWith(period: null, from: iso(range.start), to: iso(range.end)));
  }

  TxFilter _result() {
    String? value(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return _f.copyWith(min: value(_min), max: value(_max));
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final custom = (f.from ?? '').isNotEmpty || (f.to ?? '').isNotEmpty;
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        );
    Widget pill(String label, bool selected, VoidCallback onTap, {Key? key, Widget? avatar}) => FilterChip(
          key: key,
          label: Text(label),
          avatar: avatar,
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          backgroundColor: AppColors.surface2,
          selectedColor: AppColors.accent,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          onSelected: (_) => onTap(),
        );
    Widget pills(List<Widget> children) => Wrap(spacing: 6, runSpacing: 6, children: children);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Filtri', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                title('Periodo'),
                pills([
                  for (final MapEntry(key: key, value: (label, _)) in periodShortcuts.entries)
                    pill(label, f.period == key && !custom,
                        () => _set(f.copyWith(period: f.period == key && !custom ? null : key, from: null, to: null))),
                  pill(custom ? chipLabels(f, const [], const [])['period']! : 'Dal / al…', custom, _pickRange,
                      key: const Key('pick-range')),
                ]),
                title('Tipo'),
                SegmentedButton<String>(
                  key: const Key('direction'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Tutti')),
                    ButtonSegment(value: 'out', label: Text('Uscite')),
                    ButtonSegment(value: 'in', label: Text('Entrate')),
                  ],
                  selected: {f.direction ?? 'all'},
                  onSelectionChanged: (v) => _set(f.copyWith(direction: v.first == 'all' ? null : v.first)),
                ),
                title('Conti'),
                pills([
                  for (final a in widget.lists.accounts)
                    pill('${a['bank']} · ${a['label']}${a['hidden'] == 1 ? ' (nascosto)' : ''}',
                        f.accounts.contains(a['id']), () => _set(f.copyWith(accounts: _toggle(f.accounts, a['id'] as int))),
                        key: Key('acc-${a['id']}')),
                ]),
                title('Categorie'),
                pills([
                  pill('Senza categoria', f.categories.contains('none'),
                      () => _set(f.copyWith(categories: _toggle(f.categories, 'none'))),
                      key: const Key('cat-none')),
                  for (final c in widget.lists.categories)
                    pill(c['name'] as String, f.categories.contains('${c['id']}'),
                        () => _set(f.copyWith(categories: _toggle(f.categories, '${c['id']}'))),
                        key: Key('cat-${c['id']}'),
                        avatar: CategoryAvatar(icon: c['icon'] as String?, color: c['color'] as String?, size: 20)),
                ]),
                title('Importo'),
                Row(children: [
                  Expanded(
                    child: TextField(
                        key: const Key('amount-min'),
                        controller: _min,
                        keyboardType: keyboard,
                        decoration: const InputDecoration(hintText: 'Da (€)', isDense: true)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                        key: const Key('amount-max'),
                        controller: _max,
                        keyboardType: keyboard,
                        decoration: const InputDecoration(hintText: 'A (€)', isDense: true)),
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('show-hidden'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostra conti nascosti'),
                  value: f.hidden,
                  onChanged: (v) => _set(f.copyWith(hidden: v)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              TextButton(
                key: const Key('reset-filters'),
                onPressed: () {
                  _min.clear();
                  _max.clear();
                  _set(f.cleared());
                },
                child: const Text('Azzera'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('apply-filters'),
                  onPressed: () => Navigator.pop(context, _result()),
                  child: const Text('Mostra risultati'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

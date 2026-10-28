import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../domain/transactions.dart';
import 'theme.dart';
import 'widgets.dart';

/// Condivide il CSV (nel telefono: foglio di condivisione di Android).
typedef ShareCsv = Future<void> Function(String csv);

Future<void> shareCsvFile(String csv) => SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: 'movimenti.csv')],
      fileNameOverrides: ['movimenti.csv'],
    ));

/// Movimenti: ricerca, chip di filtro, totali, raggruppamento per giorno,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(TxPage, _Lists)>(
      future: _data,
      builder: (context, snap) {
        final data = snap.data;
        return CustomScrollView(slivers: [
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
              TextField(
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
              const SizedBox(height: 10),
              if (data != null) _chips(data.$2),
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
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else ..._list(data.$1),
        ]);
      },
    );
  }

  Widget _chips(_Lists lists) {
    final f = _filter;
    final labels = chipLabels(f, lists.accounts, lists.categories);
    Widget chip(String key, IconData icon, String label, Widget Function(BuildContext) panel, TxFilter Function() clear) {
      final active = labels[key];
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          key: Key('chip-$key'),
          selected: active != null,
          showCheckmark: false,
          avatar: Icon(icon, size: 16),
          label: Text(active ?? label),
          onSelected: (_) => _openPanel(active ?? label, panel, active != null ? clear : null),
        ),
      );
    }

    final (from, to) = (f.from, f.to);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        // In testa, non in fondo alla riga: sul telefono resta sempre visibile.
        if (labels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              key: const Key('clear-filters'),
              avatar: const Icon(Icons.close, size: 16),
              label: const Text('Azzera filtri'),
              onPressed: () => _apply(f.cleared()),
            ),
          ),
        chip('account', Icons.account_balance_outlined, 'Conto', (ctx) => _options(ctx, [
              for (final a in lists.accounts)
                _Opt('${a['bank']} · ${a['label']}${a['hidden'] == 1 ? ' (nascosto)' : ''}', f.account == a['id'],
                    () => f.copyWith(account: a['id'])),
            ]), () => f.copyWith(account: null)),
        chip('category', Icons.category_outlined, 'Categoria', (ctx) => _options(ctx, [
              _Opt('Senza categoria', f.category == 'none', () => f.copyWith(category: 'none')),
              for (final c in lists.categories)
                _Opt(c['name'] as String, f.category == '${c['id']}', () => f.copyWith(category: '${c['id']}'),
                    leading: CategoryAvatar(icon: c['icon'] as String?, color: c['color'] as String?, size: 28)),
            ]), () => f.copyWith(category: null)),
        chip('period', Icons.calendar_today_outlined, 'Periodo', (ctx) => _options(ctx, [
              for (final e in periodShortcuts.entries)
                _Opt(e.value.$1, f.period == e.key && from == null && to == null,
                    () => f.copyWith(period: e.key, from: null, to: null)),
              _Opt('Dal / al…', from != null || to != null, () => f, pickRange: true),
            ]), () => f.copyWith(period: null, from: null, to: null)),
        chip('direction', Icons.swap_vert, 'Tipo', (ctx) => _options(ctx, [
              _Opt('Uscite', f.direction == 'out', () => f.copyWith(direction: 'out'),
                  leading: const Icon(Icons.north_east)),
              _Opt('Entrate', f.direction == 'in', () => f.copyWith(direction: 'in'),
                  leading: const Icon(Icons.south_west)),
            ]), () => f.copyWith(direction: null)),
        chip('amount', Icons.euro, 'Importo', (ctx) => _AmountPanel(filter: f), () => f.copyWith(min: null, max: null)),
        chip('extra', Icons.tune, 'Altro', (ctx) => _options(ctx, [
              _Opt('Mostra conti nascosti', f.hidden, () => f.copyWith(hidden: !f.hidden),
                  leading: Icon(f.hidden ? Icons.check_box : Icons.check_box_outline_blank)),
            ]), () => f.copyWith(hidden: false)),
      ]),
    );
  }

  /// Pannello di un chip: restituisce i nuovi filtri, oppure null se annullato.
  Future<void> _openPanel(String title, Widget Function(BuildContext) panel, TxFilter Function()? clear) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            Flexible(child: panel(ctx)),
            if (clear != null)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Togli filtro'),
                onTap: () => Navigator.pop(ctx, clear()),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (result is TxFilter) _apply(result);
    if (result == _pickRangeSignal) await _pickRange();
  }

  Widget _options(BuildContext ctx, List<_Opt> options) => ListView(
        shrinkWrap: true,
        children: [
          for (final o in options)
            ListTile(
              leading: o.leading,
              title: Text(o.label),
              trailing: o.selected ? const Icon(Icons.check, color: AppColors.accent) : null,
              onTap: () => Navigator.pop(ctx, o.pickRange ? _pickRangeSignal : o.apply()),
            ),
        ],
      );

  Future<void> _pickRange() async {
    final now = today();
    final from = parseIsoDay(_filter.from), to = parseIsoDay(_filter.to);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(2000),
      lastDate: now,
      initialDateRange: from != null && to != null && !to.isBefore(from) ? DateTimeRange(start: from, end: to) : null,
      helpText: 'Dal / al',
    );
    if (range == null) return;
    _apply(_filter.copyWith(period: null, from: iso(range.start), to: iso(range.end)));
  }

  Widget _tiles(TxPage page) {
    Widget tile(String label, String value, {Color? color}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  child: Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
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
      tile('Movimenti', '${page.count}'),
    ]);
  }

  List<Widget> _list(TxPage page) => [
        if (page.days.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nessun movimento con questi filtri.', style: TextStyle(color: AppColors.muted)),
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
                  child: Column(children: [for (final t in items) FeedItem(tx: t, onChanged: _reload)]),
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
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ];
}

const _pickRangeSignal = 'pick-range';

class _Opt {
  _Opt(this.label, this.selected, this.apply, {this.leading, this.pickRange = false});
  final String label;
  final bool selected;
  final TxFilter Function() apply;
  final Widget? leading;
  final bool pickRange;
}

/// Chip «Importo»: da / a in euro.
class _AmountPanel extends StatefulWidget {
  const _AmountPanel({required this.filter});
  final TxFilter filter;

  @override
  State<_AmountPanel> createState() => _AmountPanelState();
}

class _AmountPanelState extends State<_AmountPanel> {
  late final _min = TextEditingController(text: widget.filter.min ?? '');
  late final _max = TextEditingController(text: widget.filter.max ?? '');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    String? value(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: TextField(
                key: const Key('amount-min'),
                controller: _min,
                keyboardType: keyboard,
                decoration: const InputDecoration(hintText: 'Da (€)')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
                key: const Key('amount-max'),
                controller: _max,
                keyboardType: keyboard,
                decoration: const InputDecoration(hintText: 'A (€)')),
          ),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('amount-apply'),
          onPressed: () => Navigator.pop(context, widget.filter.copyWith(min: value(_min), max: value(_max))),
          child: const Text('Applica'),
        ),
      ]),
    );
  }
}

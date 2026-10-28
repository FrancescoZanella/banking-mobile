import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../core/periods.dart';
import '../domain/analysis.dart' as analysis;
import '../domain/reports.dart';
import '../domain/transactions.dart';
import 'charts.dart';
import 'theme.dart';
import 'transactions_screen.dart';
import 'widgets.dart';

/// Ultimo mese delle barre: quello finale del periodo, mai oltre il mese in corso.
DateTime barsEnd(Period period, DateTime today) {
  final last = addDays(period.end, -1);
  final lastMonth = DateTime.utc(last.year, last.month);
  final thisMonth = DateTime.utc(today.year, today.month);
  return lastMonth.isBefore(thisMonth) ? lastMonth : thisMonth;
}

/// La barra del mese è nel periodo scelto (evidenziata).
bool monthInPeriod(DateTime monthStart, Period period) => period.kind == PeriodKind.year
    ? monthStart.year == period.start.year
    : monthStart == DateTime.utc(period.start.year, period.start.month);

String shortMonth(DateTime m) => monthsIt[m.month - 1].substring(0, 3);

/// Apre Movimenti con dei filtri già scelti (dalle righe di Analisi).
void openTransactions(BuildContext context, TxFilter filter) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(), body: TransactionsScreen(initial: filter)),
    ));

/// Analisi spese: periodo, confronto allo stesso giorno, curva cumulata,
/// 12 mesi, categorie, esercenti. Come analysis.html del web.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, this.now});

  /// Data di oggi, fissabile nei test.
  final DateTime? now;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisData {
  _AnalysisData({
    required this.spent,
    required this.delta,
    required this.categories,
    required this.merchants,
    required this.bars,
    required this.current,
    required this.previous,
    required this.alerts,
  });
  final int spent;
  final int delta;
  final List<analysis.CategorySpend> categories;
  final List<Map<String, Object?>> merchants;
  final List<(DateTime, int)> bars;
  final List<int> current;
  final List<int> previous;
  final List<ConsentAlert> alerts;
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late Period _period = periodFor(PeriodKind.month, today(widget.now));
  Future<_AnalysisData>? _data;
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
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final data = _load(Services.of(context).db);
    setState(() {
      _data = data;
    });
  }

  void _select(Period p) {
    _period = p;
    _reload();
  }

  Future<_AnalysisData> _load(DatabaseExecutor db) async {
    final now = today(widget.now);
    final period = _period, prev = previous(period);
    final until = elapsedEnd(period, now);
    final (cmpStart, cmpEnd) = comparableWindow(period, now);
    final spent = await analysis.totalSpend(db, period.start, until);
    return _AnalysisData(
      spent: spent,
      delta: spent - await analysis.totalSpend(db, cmpStart, cmpEnd),
      categories: await analysis.categories(db, period.start, until, cmpStart, cmpEnd),
      merchants: await analysis.topMerchants(db, period.start, until),
      // Barre dal mese di partenza dei dati, al massimo 12 mesi.
      bars: await analysis.monthlyBars(db, barsEnd(period, now), n: monthsFromStart(barsEnd(period, now))),
      current: await analysis.cumulative(db, period, until),
      previous: await analysis.cumulative(db, prev, prev.end),
      alerts: await consentAlerts(db),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncing = Services.of(context).sync.running;
    return FutureBuilder<_AnalysisData>(
      future: _data,
      builder: (context, snap) {
        final data = snap.data;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (data != null) for (final a in data.alerts) ConsentBanner(alert: a),
              const Text('Analisi spese', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              PeriodBar(
                period: _period,
                now: widget.now,
                kinds: const [(PeriodKind.week, 'Settimana'), (PeriodKind.month, 'Mese'), (PeriodKind.year, 'Anno')],
                onChanged: _select,
              ),
              if (syncing)
                const Text('Sincronizzazione in corso…', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              if (snap.hasError)
                const Text('Impossibile caricare l\'analisi.')
              else if (data == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                _summary(data),
                const SizedBox(height: 16),
                _months(data),
                const SizedBox(height: 16),
                _categories(data),
                const SizedBox(height: 16),
                _merchants(data),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _summary(_AnalysisData d) {
    final p = _period, prev = previous(p);
    final current = p.contains(today(widget.now));
    final what = switch (p.kind) {
      PeriodKind.month => 'a ${p.short}',
      PeriodKind.year => 'nel ${p.short}',
      PeriodKind.week => current ? 'questa settimana' : 'nella settimana',
    };
    final sameDay = current ? ' allo stesso giorno' : '';
    final delta = d.delta;
    // Prima del 1 agosto 2026 non ci sono dati: niente confronto con un periodo vuoto.
    final compare = comparisonAvailable(p);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Speso ${current ? 'finora ' : ''}$what', style: const TextStyle(color: AppColors.muted)),
          Text(money(d.spent),
              key: const Key('analysis-spent'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1)),
          const SizedBox(height: 4),
          if (!compare)
            const Text('Nessun confronto: i dati partono dal 1 agosto 2026',
                key: Key('no-comparison'), style: TextStyle(color: AppColors.muted))
          else if (delta == 0)
            Text('Uguale rispetto ${prev.versus}$sameDay', style: const TextStyle(color: AppColors.muted))
          else
            Row(children: [
              Icon(delta < 0 ? Icons.south_east : Icons.north_east,
                  size: 16, color: delta < 0 ? AppColors.pos : AppColors.neg),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${money(delta.abs())} ${delta < 0 ? 'in meno' : 'in più'} rispetto ${prev.versus}$sameDay',
                  style: TextStyle(color: delta < 0 ? AppColors.pos : AppColors.neg),
                ),
              ),
            ]),
          const SizedBox(height: 16),
          CumulativeChart(
            labels: axisLabels(p),
            current: d.current,
            previous: compare ? d.previous : const [],
            currentLabel: p.label,
            previousLabel: prev.label,
          ),
        ]),
      ),
    );
  }

  Widget _months(_AnalysisData d) {
    final nonzero = [for (final (_, total) in d.bars) if (total != 0) total];
    final average = nonzero.isEmpty ? 0 : nonzero.reduce((a, b) => a + b) / nonzero.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Spesa per mese', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          Text('Media ${money(average.round())} al mese · tocca una barra per aprire il mese',
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 14),
          MonthBarsChart(
            labels: [for (final (m, _) in d.bars) shortMonth(m)],
            values: [for (final (_, total) in d.bars) total],
            selected: [for (final (m, _) in d.bars) monthInPeriod(m, _period)],
            onTap: (i) => _select(periodFor(PeriodKind.month, d.bars[i].$1)),
          ),
        ]),
      ),
    );
  }

  Widget _categories(_AnalysisData d) {
    final prev = previous(_period);
    final compare = comparisonAvailable(_period);
    final from = iso(_period.start), to = iso(addDays(_period.end, -1));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Categorie', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (d.categories.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Nessuna spesa in questo periodo.', style: TextStyle(color: AppColors.muted)),
            ),
          for (final c in d.categories)
            InkWell(
              key: Key('category-${c.id ?? 'none'}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openTransactions(
                context,
                TxFilter(category: c.id == null ? 'none' : '${c.id}', direction: 'out', from: from, to: to),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  CategoryAvatar(icon: c.icon, color: c.color, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(text: c.name, children: [
                              TextSpan(text: ' · ${c.n} mov.', style: const TextStyle(color: AppColors.muted)),
                            ]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(money(c.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: c.pct / 100,
                          minHeight: 5,
                          backgroundColor: AppColors.surface2,
                          color: hexColor(c.color),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text('${c.pct.round()}% del totale',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ),
                        if (compare)
                        Text(
                          c.delta == 0
                              ? 'uguale vs ${prev.short}'
                              : '${c.delta > 0 ? '+' : '−'}${money(c.delta.abs())} vs ${prev.short}',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.delta == 0 ? AppColors.muted : (c.delta < 0 ? AppColors.pos : AppColors.neg),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _merchants(_AnalysisData d) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Dove spendi di più', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (d.merchants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nessun esercente in questo periodo.', style: TextStyle(color: AppColors.muted)),
              ),
            for (final m in d.merchants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text.rich(TextSpan(text: m['name'] as String, children: [
                  TextSpan(text: '  ×${m['n']}', style: const TextStyle(color: AppColors.muted)),
                ])),
                trailing: Text(money(m['total'] as int), style: const TextStyle(fontWeight: FontWeight.w600)),
                // last_key = "data|id": il pannello si apre sull'ultimo movimento.
                onTap: () async {
                  final key = m['last_key'] as String;
                  if (await showTransactionDetail(context, key.substring(key.indexOf('|') + 1))) _reload();
                },
              ),
          ]),
        ),
      );
}

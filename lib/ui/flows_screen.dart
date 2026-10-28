import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../core/periods.dart';
import '../domain/cashflow.dart' as cashflow;
import '../domain/reports.dart';
import '../domain/transactions.dart';
import 'analysis_screen.dart' show barsEnd, monthInPeriod, openTransactions, shortMonth;
import 'charts.dart';
import 'theme.dart';
import 'widgets.dart';

/// Entrate e flusso di cassa: totali, tasso di risparmio, uscite ed entrate per
/// categoria, mesi, patrimonio, fonti delle entrate con le ricorrenti. Come
/// flows.html del web, più la ripartizione per categoria e la settimana.
class FlowsScreen extends StatefulWidget {
  const FlowsScreen({super.key, this.now});

  /// Data di oggi, fissabile nei test.
  final DateTime? now;

  @override
  State<FlowsScreen> createState() => _FlowsScreenState();
}

class _FlowsData {
  _FlowsData(this.totals, this.byCategory, this.moved, this.series, this.trend, this.sources, this.alerts);
  final cashflow.Totals totals;
  final ({List<cashflow.CategoryFlow> expense, List<cashflow.CategoryFlow> income}) byCategory;
  final ({int cents, int n}) moved;
  final List<(DateTime, cashflow.Totals)> series;
  final ({List<DateTime> months, List<int> values}) trend;
  final List<cashflow.IncomeSource> sources;
  final List<ConsentAlert> alerts;
}

class _FlowsScreenState extends State<FlowsScreen> {
  late Period _period = periodFor(PeriodKind.month, today(widget.now));
  Future<_FlowsData>? _data;
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

  Future<_FlowsData> _load(DatabaseExecutor db) async {
    final now = today(widget.now);
    final period = _period;
    final until = elapsedEnd(period, now);
    final visible = [for (final a in await accountsOverview(db)) if (a['hidden'] != 1) a];
    final lastMonth = barsEnd(period, now);
    return _FlowsData(
      await cashflow.totals(db, period.start, until),
      await cashflow.byCategory(db, period.start, until),
      await cashflow.movedBetweenAccounts(db, period.start, until),
      // Grafici dal mese di partenza dei dati, al massimo 12 mesi.
      await cashflow.monthly(db, lastMonth, n: monthsFromStart(lastMonth)),
      await balanceTrend(db, visible, today: now, n: monthsFromStart(DateTime.utc(now.year, now.month))),
      await cashflow.incomeSources(db, period.start, until, now),
      await consentAlerts(db),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncing = Services.of(context).sync.running;
    return FutureBuilder<_FlowsData>(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (data != null) for (final a in data.alerts) ConsentBanner(alert: a),
                const Text('Entrate e flusso di cassa',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                PeriodBar(
                  period: _period,
                  now: widget.now,
                  kinds: const [(PeriodKind.week, 'Settimana'), (PeriodKind.month, 'Mese'), (PeriodKind.year, 'Anno')],
                  onChanged: _select,
                ),
                if (syncing) const Text('Sincronizzazione in corso…', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                if (snap.hasError)
                  const Text('Impossibile caricare i flussi.')
                else if (data == null)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else ...[
                  _tiles(data),
                  const SizedBox(height: 16),
                  _categories('Uscite per categoria', data.byCategory.expense, 'out',
                      'Nessuna uscita in questo periodo.', const Key('expense-by-category')),
                  const SizedBox(height: 16),
                  _categories('Entrate per categoria', data.byCategory.income, 'in',
                      'Nessuna entrata in questo periodo.', const Key('income-by-category')),
                  if (data.moved.n > 0) ...[const SizedBox(height: 16), _moved(data.moved)],
                  const SizedBox(height: 16),
                  _flows(data),
                  const SizedBox(height: 16),
                  _networth(data),
                  const SizedBox(height: 16),
                  _sources(data),
                ],
              ],
            ),
          );
        },
    );
  }

  Widget _tiles(_FlowsData d) {
    final t = d.totals;
    final soFar = _period.contains(today(widget.now)) ? ' finora' : '';
    final rate = cashflow.savingsRate(t.income, t.net);
    final average = cashflow.averageRate(d.series);
    Widget tile(String label, Widget value, [String? note]) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 4),
              value,
              if (note != null) Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
        );
    const big = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    final Widget rateText = rate == null
        ? const Text('—', style: big)
        : rate < 0
            ? const Text('Uscite oltre le entrate',
                style: TextStyle(color: AppColors.neg, fontWeight: FontWeight.w600, fontSize: 13))
            : Text('${rate.round()}%', key: const Key('savings-rate'), style: big);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.75,
      children: [
        tile('Entrate$soFar', Text(money(t.income), style: big.copyWith(color: AppColors.pos))),
        tile('Uscite$soFar', Text(money(t.expense), style: big)),
        tile(
          'Risparmiato',
          Text(signedMoney(t.net),
              key: const Key('saved'),
              style: big.copyWith(color: t.net > 0 ? AppColors.pos : (t.net < 0 ? AppColors.neg : null))),
        ),
        tile('Tasso di risparmio', rateText,
            average == null ? null : 'media 12 mesi ${average >= 0 ? '${average.round()}%' : 'negativa'}'),
      ],
    );
  }

  /// Uscite o entrate del periodo per categoria; tocco → Movimenti filtrati.
  Widget _categories(String title, List<cashflow.CategoryFlow> rows, String direction, String empty, Key key) {
    final from = iso(_period.start), to = iso(addDays(_period.end, -1));
    final total = rows.fold<int>(0, (s, c) => s + c.total);
    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            Text(money(total),
                style: TextStyle(fontWeight: FontWeight.w600, color: direction == 'in' ? AppColors.pos : null)),
          ]),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(empty, style: const TextStyle(color: AppColors.muted)),
            ),
          for (final c in rows)
            InkWell(
              key: Key('flow-$direction-${c.id ?? 'none'}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openTransactions(
                context,
                TxFilter(category: c.id == null ? 'none' : '${c.id}', direction: direction, from: from, to: to),
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
                      Text('${c.pct.round()}% del totale', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  /// Giroconti del periodo: fuori da entrate e uscite, ma visibili.
  Widget _moved(({int cents, int n}) moved) => Card(
        key: const Key('moved-between-accounts'),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: const CategoryAvatar(icon: 'arrows-exchange', color: '#ced4da'),
          title: const Text('Spostato tra i tuoi conti'),
          subtitle: Text('${moved.n} ${moved.n == 1 ? 'giroconto' : 'giroconti'} · fuori da entrate e uscite',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          trailing: Text(money(moved.cents), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _flows(_FlowsData d) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Entrate e uscite per mese', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const Text('la linea è il risparmio del mese · tocca un mese per aprirlo',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            FlowsChart(
              labels: [for (final (m, _) in d.series) shortMonth(m)],
              income: [for (final (_, t) in d.series) t.income],
              expense: [for (final (_, t) in d.series) t.expense],
              net: [for (final (_, t) in d.series) t.net],
              selected: [for (final (m, _) in d.series) monthInPeriod(m, _period)],
              onTap: (i) => _select(periodFor(PeriodKind.month, d.series[i].$1)),
            ),
          ]),
        ),
      );

  Widget _networth(_FlowsData d) {
    final values = d.trend.values;
    final delta = values.isEmpty ? null : values.last - values.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Andamento del patrimonio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          Text(
            'Saldo totale in euro a fine mese, ricostruito dai movimenti'
            '${delta != null ? ' · ${signedMoney(delta)} da ${shortMonth(d.trend.months.first)}' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (values.isEmpty)
            const Text('Nessun saldo in euro disponibile.', style: TextStyle(color: AppColors.muted))
          else
            NetWorthChart(labels: [for (final m in d.trend.months) shortMonth(m)], values: values),
        ]),
      ),
    );
  }

  Widget _sources(_FlowsData d) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Da dove arrivano le entrate', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            if (d.sources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nessuna entrata in questo periodo.', style: TextStyle(color: AppColors.muted)),
              ),
            for (final s in d.sources)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: CategoryAvatar(icon: s.icon, color: s.color),
                title: Text(s.party, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  s.recurring != null
                      ? 'Ricorrente · ogni mese · prossima ~${dateIt(iso(s.recurring!.next))}'
                      : '${s.n} ${s.n == 1 ? 'movimento' : 'movimenti'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                trailing: Text(money(s.total), style: const TextStyle(color: AppColors.pos, fontWeight: FontWeight.w600)),
                onTap: () async {
                  final key = s.lastKey;
                  if (await showTransactionDetail(context, key.substring(key.indexOf('|') + 1))) _reload();
                },
              ),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../domain/budget.dart' as budget;
import '../domain/reports.dart';
import '../domain/to_categorize.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home: patrimonio, schede dei conti, avvisi, mese in corso, feed per giorno.
/// Come home.html del web.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onShowAll, this.onShowAnalysis, this.onShowAccounts, this.onShowBudget});

  /// «Vedi tutti» → Movimenti; «Analisi» → Analisi; «Collega una banca» → Conti;
  /// «Vedi budget» → Budget.
  final VoidCallback? onShowAll;
  final VoidCallback? onShowAnalysis;
  final VoidCallback? onShowAccounts;
  final VoidCallback? onShowBudget;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  _HomeData(this.accounts, this.summary, this.categories, this.days, this.budgetAlerts, this.alerts, this.toCategorize);
  final List<Map<String, Object?>> accounts;
  final Map<String, int> summary;
  final List<Map<String, Object?>> categories;
  final List<(String?, List<Map<String, Object?>>)> days;
  final List<budget.BudgetAlert> budgetAlerts;
  final List<ConsentAlert> alerts;
  final List<Map<String, Object?>> toCategorize;
}

class _HomeScreenState extends State<HomeScreen> {
  Future<_HomeData>? _data;
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
    final data = _load(Services.of(context));
    setState(() {
      _data = data;
    });
  }

  Future<_HomeData> _load(AppServices s) async {
    final now = today();
    // I conti nascosti restano visibili solo nella pagina Conti.
    final accounts = [for (final a in await accountsOverview(s.db)) if (a['hidden'] != 1) a];
    return _HomeData(
      accounts,
      await monthSummary(s.db, now),
      (await spendingByCategory(s.db, now)).take(6).toList(),
      groupByDay(await recentTransactions(s.db)),
      await budget.alerts(s.db, now),
      await consentAlerts(s.db),
      await toCategorize(s.db),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncing = Services.of(context).sync.running;
    return FutureBuilder<_HomeData>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare la Home.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('Riprova')),
            ]),
          );
        }
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              for (final a in data.alerts) ConsentBanner(alert: a),
              for (final b in data.budgetAlerts) _BudgetBanner(alert: b, onShow: widget.onShowBudget),
              _hero(data, syncing),
              if (data.toCategorize.isNotEmpty) ...[const SizedBox(height: 16), _toCategorize(data.toCategorize)],
              const SizedBox(height: 16),
              _month(data.summary),
              const SizedBox(height: 16),
              _categories(data),
              const SizedBox(height: 16),
              _feed(data),
            ],
          ),
        );
      },
    );
  }

  Widget _hero(_HomeData data, bool syncing) {
    final totals = totalsByCurrency(data.accounts);
    // Valuta principale in grande, le altre sotto.
    final main = totals.containsKey('EUR') || totals.isEmpty ? 'EUR' : totals.keys.first;
    final net = data.summary['income']! - data.summary['expense']!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Patrimonio totale', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(money(totals[main] ?? 0, main),
              key: const Key('home-net-worth'),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1)),
          for (final e in totals.entries)
            if (e.key != main) Text('+ ${money(e.value, e.key)}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(net >= 0 ? Icons.trending_up : Icons.trending_down,
                size: 18, color: net >= 0 ? AppColors.pos : AppColors.neg),
            const SizedBox(width: 6),
            Text('${net > 0 ? '+' : ''}${money(net)} questo mese',
                style: TextStyle(color: net >= 0 ? AppColors.pos : AppColors.neg)),
          ]),
          if (syncing)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Sincronizzazione in corso…', style: TextStyle(color: AppColors.muted)),
            ),
          const SizedBox(height: 16),
          if (data.accounts.isEmpty)
            Row(children: [
              const Text('Nessun conto collegato. ', style: TextStyle(color: AppColors.muted)),
              GestureDetector(
                onTap: widget.onShowAccounts,
                child: const Text('Collega una banca', style: TextStyle(color: AppColors.accent)),
              ),
            ])
          else
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.accounts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _AccountCard(account: data.accounts[i]),
              ),
            ),
        ]),
      ),
    );
  }

  /// I movimenti che le regole non hanno saputo classificare (ultimo mese).
  Widget _toCategorize(List<Map<String, Object?>> rows) {
    const shown = 5;
    return Card(
      key: const Key('to-categorize'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Da categorizzare (${rows.length})',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const Text('Le regole non li hanno riconosciuti: tocca un movimento per scegliere la categoria.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          for (final t in rows.take(shown)) FeedItem(tx: t, onChanged: _reload),
          if (rows.length > shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text('e altri ${rows.length - shown}', style: const TextStyle(color: AppColors.muted)),
            ),
        ]),
      ),
    );
  }

  Widget _month(Map<String, int> summary) {
    Widget split(String label, int value, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(money(value), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionHead('Questo mese', action: 'Analisi', onTap: widget.onShowAnalysis),
          const Text('Speso finora', style: TextStyle(color: AppColors.muted)),
          Text(money(summary['expense']), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(children: [
            split('Entrate', summary['income']!, AppColors.pos),
            split('Uscite', summary['expense']!, AppColors.neg),
          ]),
        ]),
      ),
    );
  }

  Widget _categories(_HomeData data) {
    final expense = data.summary['expense']!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionHead('Dove spendi questo mese'),
          if (data.categories.isEmpty)
            const Text('Nessuna spesa questo mese.', style: TextStyle(color: AppColors.muted)),
          for (final c in data.categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CategoryAvatar(icon: c['icon'] as String?, color: c['color'] as String?, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(c['name'] as String, overflow: TextOverflow.ellipsis)),
                      Text(money(c['total'] as int)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: expense > 0 ? (c['total'] as int) / expense : 0,
                        minHeight: 5,
                        backgroundColor: AppColors.surface2,
                        color: hexColor(c['color'] as String),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _feed(_HomeData data) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _SectionHead('Movimenti recenti', action: 'Vedi tutti', onTap: widget.onShowAll),
            ),
            if (data.days.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('Ancora nessun movimento.', style: TextStyle(color: AppColors.muted)),
              ),
            for (final (day, items) in data.days) ...[
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: DayHeader(day)),
              for (final t in items) FeedItem(tx: t, onChanged: _reload),
            ],
          ]),
        ),
      );
}

class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          if (action != null)
            GestureDetector(onTap: onTap, child: Text(action!, style: const TextStyle(color: AppColors.accent))),
        ]),
      );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final Map<String, Object?> account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final currency = a['currency'] as String?;
    final iban = a['iban'] as String?;
    final name = (a['nickname'] ?? a['name'] ?? (iban != null ? maskIban(iban) : 'Conto ${currency ?? ''}')) as String;
    final balance = a['balance'] as Map<String, Object?>?;
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          const Icon(Icons.account_balance_outlined, size: 14, color: AppColors.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(a['bank_label'] as String,
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ]),
        Text('$name${currency != null && currency != 'EUR' ? ' · $currency' : ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(balance == null ? '—' : money(balance['amount_cents'] as int, balance['currency'] as String?),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _BudgetBanner extends StatelessWidget {
  const _BudgetBanner({required this.alert, this.onShow});
  final budget.BudgetAlert alert;
  final VoidCallback? onShow;

  @override
  Widget build(BuildContext context) {
    final s = alert.status;
    final over = s.state == budget.BudgetState.over;
    final text = over
        ? 'Budget ${alert.name}: superato di ${money(s.spent - s.limit)}'
        : 'Budget ${alert.name}: usato il ${s.pct.round()}% (${money(s.spent)} di ${money(s.limit)})';
    return NoticeBanner(
      color: over ? AppColors.neg : AppColors.warn,
      icon: Icons.track_changes,
      text: text,
      action: TextButton(onPressed: onShow, child: const Text('Vedi budget')),
    );
  }
}

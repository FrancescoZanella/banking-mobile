import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../domain/budget.dart' as budget;
import 'theme.dart';
import 'widgets.dart';

/// Budget e abbonamenti. Come budget.html del web.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, this.now});

  /// Data di oggi, fissabile nei test.
  final DateTime? now;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetData {
  _BudgetData(this.overview, this.subs, this.free);
  final budget.BudgetOverview overview;
  final budget.Subscriptions subs;
  final List<Map<String, Object?>> free;
}

class _BudgetScreenState extends State<BudgetScreen> {
  Future<_BudgetData>? _data;
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

  Future<_BudgetData> _load(DatabaseExecutor db) async {
    final now = today(widget.now);
    return _BudgetData(
      await budget.overview(db, now),
      await budget.subscriptions(db, now),
      await budget.freeCategories(db),
    );
  }

  void _flash(budget.Outcome o) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(o.text),
      backgroundColor: o.ok ? AppColors.surface3 : const Color(0xFF5A2020),
    ));
  }

  /// Dopo un'azione: aggiorna anche Home (avvisi di budget).
  Future<void> _done(budget.Outcome o) async {
    _flash(o);
    Services.of(context).sync.notifyChanged();
  }

  Future<void> _remove(String target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovere questo budget?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _done(await budget.deleteBudget(Services.of(context).db, target));
  }

  Future<void> _add(_BudgetData data) async {
    final db = Services.of(context).db;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _AddBudget(free: data.free, hasTotal: data.overview.total != null),
    );
    if (result == null || !mounted) return;
    await _done(await budget.saveBudget(db, result.$1, result.$2));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BudgetData>(
      future: _data,
      builder: (context, snap) {
        final data = snap.data;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const Text('Budget e abbonamenti', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (snap.hasError)
                const Text('Impossibile caricare i budget.')
              else if (data == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                _budgets(data),
                const SizedBox(height: 16),
                _subscriptions(data.subs),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _budgets(_BudgetData d) {
    final o = d.overview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Budget di ${o.period.short}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Text(o.daysLeft == 0 ? 'ultimo giorno' : 'ancora ${o.daysLeft} giorni',
                style: const TextStyle(color: AppColors.muted)),
          ]),
          const SizedBox(height: 12),
          if (o.total case final total?) ...[
            _BudgetRow(name: 'Totale del mese', status: total, onRemove: () => _remove('total')),
            Text('A questo ritmo: ~${money(total.forecast)} a fine mese',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          for (final c in o.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CategoryAvatar(icon: c.icon, color: c.color, size: 34),
                const SizedBox(width: 12),
                Expanded(child: _BudgetRow(name: c.name, status: c.status, onRemove: () => _remove('${c.categoryId}'))),
              ]),
            ),
          if (o.total == null && o.categories.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Nessun budget ancora. Scegli una categoria e un importo mensile.',
                  style: TextStyle(color: AppColors.muted)),
            ),
          FilledButton.icon(
            key: const Key('add-budget'),
            onPressed: () => _add(d),
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi budget'),
          ),
          const SizedBox(height: 8),
          const Text('Per cambiare un budget, rimuovilo e aggiungilo di nuovo con il nuovo importo.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _subscriptions(budget.Subscriptions subs) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Abbonamenti', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text.rich(TextSpan(
                  text: money(subs.monthly),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  children: const [TextSpan(text: ' al mese', style: TextStyle(fontSize: 14, color: AppColors.muted))],
                )),
                Text("${money(subs.monthly * 12)} all'anno · ${subs.items.length} riconosciuti",
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            if (subs.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nessun abbonamento riconosciuto: servono almeno 3 addebiti mensili simili allo stesso esercente.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            for (final s in subs.items)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: CategoryAvatar(icon: s.icon, color: s.color),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: s.previous != null
                    ? Text('prezzo aumentato: era ${money(s.previous)}',
                        style: const TextStyle(color: AppColors.warn, fontSize: 12))
                    : Text('prossimo ~${dayLabel(iso(s.next), widget.now)}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(s.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  PopupMenuButton<String>(
                    key: Key('sub-menu-${s.key}'),
                    color: AppColors.surface2,
                    onSelected: (_) async {
                      await budget.ignoreSubscription(Services.of(context).db, s.name);
                      _flash(budget.Outcome('«${s.name}» non verrà più mostrato tra gli abbonamenti.'));
                      _reload();
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'ignore', child: Text('Non è un abbonamento'))],
                  ),
                ]),
                onTap: () async {
                  if (await showTransactionDetail(context, s.txId)) _reload();
                },
              ),
            if (subs.ignored.isNotEmpty)
              ExpansionTile(
                key: const Key('ignored'),
                shape: const Border(),
                title: Text('${subs.ignored.length} esclusi da te', style: const TextStyle(color: AppColors.muted)),
                children: [
                  for (final key in subs.ignored)
                    ListTile(
                      title: Text(key),
                      trailing: TextButton(
                        onPressed: () async {
                          await budget.restoreSubscription(Services.of(context).db, key);
                          _reload();
                        },
                        child: const Text('ripristina'),
                      ),
                    ),
                ],
              ),
          ]),
        ),
      );
}

/// Una riga di budget: speso / limite, barra, stato (macro budget_row del web).
class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.name, required this.status, required this.onRemove});
  final String name;
  final budget.BudgetStatus status;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final b = status;
    final color = switch (b.state) {
      budget.BudgetState.over => AppColors.neg,
      budget.BudgetState.warn => AppColors.warn,
      budget.BudgetState.ok => AppColors.pos,
    };
    final text = switch (b.state) {
      budget.BudgetState.over => 'Superato di ${money(b.spent - b.limit)}',
      budget.BudgetState.warn => 'Restano ${money(b.remaining)} · previsione ${money(b.forecast)}',
      budget.BudgetState.ok => 'Restano ${money(b.remaining)}',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
        Text.rich(TextSpan(
          text: money(b.spent),
          style: const TextStyle(fontWeight: FontWeight.w600),
          children: [TextSpan(text: ' / ${money(b.limit)}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.normal))],
        )),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (b.pct / 100).clamp(0, 1).toDouble(),
          minHeight: 6,
          backgroundColor: AppColors.surface2,
          color: color,
        ),
      ),
      Row(children: [
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12))),
        TextButton(
          onPressed: onRemove,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.muted),
          child: const Text('rimuovi'),
        ),
      ]),
    ]);
  }
}

/// Nuovo budget: categoria (o totale del mese) e importo mensile.
class _AddBudget extends StatefulWidget {
  const _AddBudget({required this.free, required this.hasTotal});
  final List<Map<String, Object?>> free;
  final bool hasTotal;

  @override
  State<_AddBudget> createState() => _AddBudgetState();
}

class _AddBudgetState extends State<_AddBudget> {
  String? _target;
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Nuovo budget mensile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: const Key('budget-target'),
            value: _target,
            isExpanded: true,
            hint: const Text('Categoria…'),
            dropdownColor: AppColors.surface2,
            items: [
              DropdownMenuItem(
                value: 'total',
                child: Text(widget.hasTotal ? 'Totale del mese (modifica)' : 'Totale del mese'),
              ),
              for (final c in widget.free)
                DropdownMenuItem(value: '${c['id']}', child: Text(c['name'] as String)),
            ],
            onChanged: (v) => setState(() => _target = v),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('budget-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '€ al mese'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('budget-save'),
            onPressed: _target == null ? null : () => Navigator.pop(context, (_target!, _amount.text)),
            child: const Text('Aggiungi'),
          ),
        ]),
      );
}

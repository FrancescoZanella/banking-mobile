import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../core/periods.dart';
import '../domain/reports.dart';
import '../domain/transactions.dart';
import 'polish.dart';
import 'theme.dart';

/// Nomi delle icone salvati nel DB (quelli di Tabler, come sul web) → Material.
const _icons = <String, IconData>{
  'shopping-cart': Icons.shopping_cart_outlined,
  'tools-kitchen-2': Icons.restaurant,
  'coffee': Icons.local_cafe_outlined,
  'pizza': Icons.local_pizza_outlined,
  'bus': Icons.directions_bus_outlined,
  'car': Icons.directions_car_outlined,
  'gas-station': Icons.local_gas_station_outlined,
  'train': Icons.train_outlined,
  'bike': Icons.pedal_bike,
  'plane': Icons.flight,
  'beach': Icons.beach_access_outlined,
  'home': Icons.home_outlined,
  'home-bolt': Icons.home_work_outlined,
  'bolt': Icons.bolt,
  'droplet': Icons.water_drop_outlined,
  'wifi': Icons.wifi,
  'device-mobile': Icons.smartphone,
  'device-tv': Icons.tv,
  'device-gamepad-2': Icons.sports_esports_outlined,
  'music': Icons.music_note_outlined,
  'movie': Icons.movie_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'shopping-bag': Icons.shopping_bag_outlined,
  'shirt': Icons.checkroom,
  'gift': Icons.card_giftcard,
  'heart-plus': Icons.favorite_border,
  'pill': Icons.medication_outlined,
  'stethoscope': Icons.medical_services_outlined,
  'barbell': Icons.fitness_center,
  'school': Icons.school_outlined,
  'book': Icons.menu_book_outlined,
  'paw': Icons.pets,
  'baby-carriage': Icons.child_friendly_outlined,
  'users': Icons.people_outline,
  'tool': Icons.build_outlined,
  'credit-card': Icons.credit_card,
  'building-bank': Icons.account_balance_outlined,
  'cash': Icons.payments_outlined,
  'coin': Icons.monetization_on_outlined,
  'pig-money': Icons.savings_outlined,
  'briefcase': Icons.work_outline,
  'receipt': Icons.receipt_long_outlined,
  'arrows-exchange': Icons.swap_horiz,
  'chart-line': Icons.show_chart,
  'tag': Icons.sell_outlined,
};

IconData categoryIcon(String? name) => _icons[name] ?? Icons.sell_outlined;

/// Icona tonda nel colore della categoria.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.icon, required this.color, this.size = 40});
  final String? icon;
  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = hexColor(color ?? '#adb5bd');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: .18), shape: BoxShape.circle),
      child: Icon(categoryIcon(icon), color: c, size: size * .5),
    );
  }
}

/// Avatar di un movimento: iniziali dell'esercente con il badge della categoria.
/// Senza esercente né descrizione resta l'icona della categoria.
class TxAvatar extends StatelessWidget {
  const TxAvatar({super.key, required this.tx, this.size = 40});
  final Map<String, Object?> tx;
  final double size;

  @override
  Widget build(BuildContext context) {
    final title = txTitle(tx);
    final icon = tx['category_icon'] as String?, color = tx['category_color'] as String?;
    if (title == 'Movimento') return CategoryAvatar(icon: icon, color: color, size: size);
    return MerchantAvatar(
      name: title,
      categoryIcon: categoryIcon(icon),
      categoryColor: hexColor(color ?? '#adb5bd'),
      size: size,
    );
  }
}

String txTitle(Map<String, Object?> t) {
  for (final key in ['counterparty', 'description']) {
    final v = t[key] as String?;
    if (v != null && v.isNotEmpty) return v;
  }
  return 'Movimento';
}

String signedMoney(int cents, [String? currency]) => '${cents > 0 ? '+' : ''}${money(cents, currency)}';

/// Intestazione di un giorno nel feed, con il totale facoltativo.
class DayHeader extends StatelessWidget {
  const DayHeader(this.day, {super.key, this.total});
  final String? day;
  final int? total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        child: Row(children: [
          Expanded(
            child: Text(dayLabel(day),
                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          if (total != null)
            Amount(signedMoney(total!), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
      );
}

/// Una riga del feed (_feed_item.html): tocco → dettaglio.
class FeedItem extends StatelessWidget {
  const FeedItem({super.key, required this.tx, required this.onChanged});
  final Map<String, Object?> tx;

  /// Chiamata dopo un cambio di categoria dal dettaglio.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = tx;
    final cents = t['amount_cents'] as int;
    final pending = t['status'] == 'PDNG';
    final sub = [
      t['category_name'] as String? ?? 'Senza categoria',
      t['bank_label'] as String,
      if (t['account_name'] case final String name when name.isNotEmpty) name,
      if (pending) 'in attesa',
    ].join(' · ');
    return Opacity(
      opacity: pending ? .7 : 1,
      child: ListTile(
        key: ValueKey('tx-${t['id']}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: TxAvatar(tx: t),
        title: Text(txTitle(t), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(sub,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        trailing: Amount(
          signedMoney(cents, t['currency'] as String?),
          style: TextStyle(fontWeight: FontWeight.w600, color: cents > 0 ? AppColors.pos : AppColors.text),
        ),
        onTap: () async {
          if (await showTransactionDetail(context, t['id'] as String)) onChanged();
        },
      ),
    );
  }
}

/// Pannello di dettaglio a scheda (_detail.html). True se la categoria è cambiata.
Future<bool> showTransactionDetail(BuildContext context, String txId) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _TransactionDetail(txId: txId),
  );
  return changed ?? false;
}

class _TransactionDetail extends StatefulWidget {
  const _TransactionDetail({required this.txId});
  final String txId;

  @override
  State<_TransactionDetail> createState() => _TransactionDetailState();
}

class _TransactionDetailState extends State<_TransactionDetail> {
  late Future<(Map<String, Object?>?, TransactionHistory?, List<Map<String, Object?>>)> _data;
  int? _selected;
  bool _makeRule = false;
  bool _changed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data = _load();
  }

  Future<(Map<String, Object?>?, TransactionHistory?, List<Map<String, Object?>>)> _load() async {
    final db = Services.of(context).db;
    final (tx, history) = await transactionDetail(db, widget.txId);
    _selected = tx?['category_id'] as int?; // come il web: preselezionata quella attuale
    return (tx, history, await allCategories(db));
  }

  Future<void> _save() async {
    final s = Services.of(context);
    final message = await setCategory(s.db, widget.txId, _selected, makeRule: _makeRule);
    s.sync.notifyChanged(); // aggiorna Home e Movimenti
    await s.dismissNotification(widget.txId);
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    _changed = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
          }
          final (tx, history, categories) = snap.data!;
          if (tx == null) {
            return const Padding(padding: EdgeInsets.all(24), child: Text('Movimento non trovato.'));
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .85,
            maxChildSize: 1,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                      width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                _head(tx),
                const SizedBox(height: 16),
                _facts(tx),
                const SizedBox(height: 20),
                _categoryForm(tx, categories),
                if (history != null) ...[const SizedBox(height: 24), _history(tx, history)],
              ],
            ),
          );
        },
    );
  }

  Widget _head(Map<String, Object?> t) {
    final cents = t['amount_cents'] as int;
    final day = t['booking_date'] as String?;
    final label = dayLabel(day);
    return Column(children: [
      TxAvatar(tx: t, size: 56),
      const SizedBox(height: 10),
      Text(txTitle(t), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Amount(signedMoney(cents, t['currency'] as String?),
          key: const Key('detail-amount'),
          style: TextStyle(
              fontSize: 30, fontWeight: FontWeight.w700, color: cents > 0 ? AppColors.pos : AppColors.text)),
      Text(label == 'Oggi' || label == 'Ieri' ? '$label · ${dateIt(day)}' : label,
          style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        if (t['status'] == 'PDNG') const _Badge('In attesa'),
        if (t['is_internal'] == 1) const _Badge('Giroconto · fuori dai totali di tutti i conti'),
        if (t['category_investment'] == 1) const _Badge('Investimento · risparmio, non spesa'),
      ]),
    ]);
  }

  Widget _facts(Map<String, Object?> t) {
    final counterparty = t['counterparty'] as String?;
    final description = t['description'] as String?;
    final rows = <(String, String)>[
      ('Conto', '${t['bank_label']}${t['account_name'] != null ? ' · ${t['account_name']}' : ''}'),
      ('Data contabile', dateIt(t['booking_date'] as String?)),
      if (t['value_date'] != null && t['value_date'] != t['booking_date'])
        ('Data valuta', dateIt(t['value_date'] as String?)),
      if (counterparty != null && description != null && description != counterparty) ('Descrizione', description),
      if (t['counterparty_iban'] case final String iban when iban.isNotEmpty) ('IBAN controparte', maskIban(iban)),
      if (t['mcc'] case final String mcc when mcc.isNotEmpty) ('Codice esercente (MCC)', mcc),
    ];
    return Card(
      color: AppColors.surface2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(k, style: const TextStyle(color: AppColors.muted))),
                Expanded(child: Text(v, textAlign: TextAlign.end)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _categoryForm(Map<String, Object?> t, List<Map<String, Object?>> categories) {
    final counterparty = t['counterparty'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Categoria', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      DropdownButtonFormField<int?>(
        key: const Key('category-select'),
        value: _selected,
        isExpanded: true,
        dropdownColor: AppColors.surface2,
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Automatica')),
          for (final c in categories)
            DropdownMenuItem<int?>(
              value: c['id'] as int,
              child: Row(children: [
                CategoryAvatar(icon: c['icon'] as String?, color: c['color'] as String?, size: 26),
                const SizedBox(width: 10),
                Flexible(child: Text(c['name'] as String, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
        onChanged: (v) => setState(() => _selected = v),
      ),
      if (counterparty != null && counterparty.isNotEmpty)
        CheckboxListTile(
          key: const Key('make-rule'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _makeRule,
          onChanged: (v) => setState(() => _makeRule = v ?? false),
          title: Text('Applica a tutti i movimenti di «$counterparty»', style: const TextStyle(fontSize: 14)),
        ),
      if (t['category_source'] == 'manual')
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Categoria scelta a mano.', style: TextStyle(color: AppColors.muted)),
        ),
      const SizedBox(height: 8),
      FilledButton(key: const Key('save-category'), onPressed: _changed ? null : _save, child: const Text('Salva')),
    ]);
  }

  Widget _history(Map<String, Object?> t, TransactionHistory h) {
    final currency = t['currency'] as String?;
    Widget stat(String label, String value, {bool amount = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            amount
                ? Amount(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))
                : Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Con ${t['counterparty']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [stat('Movimenti', '${h.count}'), stat('Totale', money(h.total, currency), amount: true)]),
      if (h.first != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Dal ${dateIt(h.first)}', style: const TextStyle(color: AppColors.muted)),
        ),
      for (final r in h.recent)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CategoryAvatar(icon: r['category_icon'] as String?, color: r['category_color'] as String?, size: 34),
          title: Text(dayLabel(r['booking_date'] as String?)),
          subtitle: Text(r['category_name'] as String? ?? 'Senza categoria',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          trailing: Amount(signedMoney(r['amount_cents'] as int, r['currency'] as String?)),
        ),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}

/// Avviso colorato in cima alle pagine (consensi, budget).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.color, required this.icon, required this.text, this.action});
  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ?action,
        ]),
      );
}

/// Consenso scaduto o in scadenza, con «Rinnova ora» (_alerts.html).
class ConsentBanner extends StatelessWidget {
  const ConsentBanner({super.key, required this.alert});
  final ConsentAlert alert;

  Future<void> _renew(BuildContext context) async {
    final s = Services.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await s.bank.connectExisting(alert.key);
    String? error = result.error;
    if (error == null && !await s.openBankPage(Uri.parse(result.url!))) {
      error = 'Impossibile aprire la pagina della banca.';
    }
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: const Color(0xFF5A2020)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final text = a.expired
        ? 'Il consenso di ${a.label} è scaduto: i dati restano, ma non arrivano nuovi movimenti.'
        : 'Il consenso di ${a.label} ${daysLeft(a.days)}.';
    return NoticeBanner(
      color: a.expired ? AppColors.neg : AppColors.warn,
      icon: Icons.warning_amber_rounded,
      text: text,
      action: TextButton(onPressed: () => _renew(context), child: const Text('Rinnova ora')),
    );
  }
}

/// Scelta del tipo di periodo e frecce avanti/indietro (_period_bar.html).
/// Niente freccia verso il futuro oltre il periodo in corso.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.period, required this.kinds, required this.onChanged, this.now});
  final Period period;
  final List<(PeriodKind, String)> kinds;
  final ValueChanged<Period> onChanged;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final next = following(period);
    final canGoOn = !next.start.isAfter(today(now));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<PeriodKind>(
        showSelectedIcon: false,
        segments: [for (final (kind, label) in kinds) ButtonSegment(value: kind, label: Text(label))],
        selected: {period.kind},
        onSelectionChanged: (s) => onChanged(periodFor(s.first, period.start)),
      ),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(
          key: const Key('period-prev'),
          tooltip: 'Periodo precedente',
          icon: const Icon(Icons.chevron_left),
          // Niente periodi interamente prima della data di partenza dei dati.
          onPressed: period.start.isAfter(dataStartDay) ? () => onChanged(previous(period)) : null,
        ),
        Expanded(
          child: Text(period.label,
              key: const Key('period-label'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        ),
        IconButton(
          key: const Key('period-next'),
          tooltip: 'Periodo successivo',
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoOn ? () => onChanged(next) : null,
        ),
      ]),
    ]);
  }
}

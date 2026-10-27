import 'package:flutter/material.dart';

import '../app/services.dart';
import '../bank/bank_service.dart';
import '../core/config.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../domain/reports.dart';
import 'theme.dart';

/// Pagina Conti: patrimonio, collegamento banche, schede banca con stato del
/// consenso e conti, storico sincronizzazioni. Come accounts.html del web.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _Data {
  _Data(this.banks, this.consents, this.accounts, this.alerts, this.runs, this.catalog);
  final List<Map<String, Object?>> banks;
  final Map<String, Map<String, Object?>> consents;
  final List<Map<String, Object?>> accounts;
  final Map<String, ConsentAlert> alerts;
  final List<Map<String, Object?>> runs;
  final List<String>? catalog;

  Set<String> get linked => {
        for (final b in banks)
          if (consents.containsKey(b['key'])) b['aspsp_name'] as String? ?? '',
      };
}

class _AccountsScreenState extends State<AccountsScreen> {
  Future<_Data>? _data;
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

  Future<_Data> _load(AppServices s) async {
    final consents = {
      for (final r in await s.db.rawQuery(
          'SELECT * FROM consents c WHERE c.id = (SELECT max(id) FROM consents WHERE bank_key = c.bank_key)'))
        r['bank_key'] as String: r,
    };
    final runs = await s.db.rawQuery(
      'SELECT s.*, coalesce(a.nickname, a.name, b.label) AS account_label '
      'FROM sync_runs s LEFT JOIN accounts a ON a.id = s.account_id '
      'LEFT JOIN banks b ON b.key = a.bank_key ORDER BY s.id DESC LIMIT 15',
    );
    return _Data(
      await s.db.query('banks', orderBy: 'label'),
      consents,
      await accountsOverview(s.db),
      {for (final a in await consentAlerts(s.db)) a.key: a},
      runs,
      await s.bank.catalogNames(),
    );
  }

  void _flash(Flash f) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(f.text),
      backgroundColor: f.ok ? AppColors.surface3 : const Color(0xFF5A2020),
      duration: Duration(seconds: f.ok ? 4 : 8),
    ));
  }

  Future<void> _openAuth(Future<AuthStart> Function() start) async {
    final s = Services.of(context);
    final result = await start();
    if (result.error != null) return _flash(Flash(result.error!, ok: false));
    final opened = await s.openBankPage(Uri.parse(result.url!));
    if (!opened) _flash(const Flash('Impossibile aprire la pagina della banca.', ok: false));
  }

  Future<void> _connectNew(_Data data) async {
    final s = Services.of(context);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _BankPicker(catalog: data.catalog, linked: data.linked),
    );
    if (name != null) await _openAuth(() => s.bank.connectNew(name));
  }

  Future<void> _disconnect(Map<String, Object?> bank) async {
    final s = Services.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Scollegare ${bank['label']}?'),
        content: const Text('Il consenso viene revocato presso la banca; i movimenti già scaricati restano.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Scollega')),
        ],
      ),
    );
    if (ok != true) return;
    _flash(await s.bank.disconnect(bank['key'] as String));
    _reload();
  }

  Future<void> _delete(Map<String, Object?> bank) async {
    final s = Services.of(context);
    final label = bank['label'] as String;
    final typed = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text('Elimina $label'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Revoca il consenso e cancella dal telefono conti, movimenti e saldi di $label. '
                'Non si può annullare.', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('confirm-name'),
              controller: controller,
              decoration: InputDecoration(hintText: 'Scrivi «$label»'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Elimina', style: TextStyle(color: AppColors.neg)),
            ),
          ],
        );
      },
    );
    if (typed == null) return;
    _flash(await s.bank.deleteBank(bank['key'] as String, typed));
    _reload();
  }

  Future<void> _accountMenu(Map<String, Object?> account) async {
    final s = Services.of(context);
    final hidden = account['hidden'] == 1;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rinomina'),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            leading: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            title: Text(hidden ? 'Mostra nei totali e nei grafici' : 'Nascondi da totali e grafici'),
            onTap: () => Navigator.pop(context, 'hide'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'hide') {
      await s.bank.toggleHidden(account['id'] as int);
    } else {
      final controller = TextEditingController(text: account['nickname'] as String? ?? '');
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nome del conto'),
          content: TextField(
            controller: controller,
            maxLength: 40,
            decoration: InputDecoration(hintText: account['name'] as String? ?? 'Nome conto'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Rinomina')),
          ],
        ),
      );
      if (value == null) return;
      await s.bank.setNickname(account['id'] as int, value);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Conti')),
      body: FutureBuilder<_Data>(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final totals = totalsByCurrency([for (final a in data.accounts) if (a['hidden'] != 1) a]);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Column(children: [
                      const Text('Patrimonio nei conti visibili', style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 6),
                      Text(money(totals['EUR'] ?? 0, 'EUR'),
                          key: const Key('net-worth'),
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1)),
                      for (final e in totals.entries)
                        if (e.key != 'EUR')
                          Text('+ ${money(e.value, e.key)}', style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 18),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _RoundAction(
                          icon: Icons.refresh,
                          label: s.sync.running ? 'In corso…' : 'Sincronizza',
                          primary: true,
                          onTap: s.sync.running ? null : () async => _flash(await s.bank.syncNow()),
                        ),
                        _RoundAction(icon: Icons.add, label: 'Collega banca', onTap: () => _connectNew(data)),
                        _RoundAction(icon: Icons.history, label: 'Storico sync', onTap: () => _showRuns(data.runs)),
                      ]),
                      const SizedBox(height: 14),
                      Text(
                        "Aggiornamento automatico all'apertura e in background, al massimo ogni "
                        '${AppConfig.minSyncInterval.inHours} ore per conto.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ]),
                  ),
                ),
                for (final bank in data.banks) ...[
                  const SizedBox(height: 16),
                  _BankCard(
                    bank: bank,
                    consent: data.consents[bank['key']],
                    alert: data.alerts[bank['key']],
                    accounts: [for (final a in data.accounts) if (a['bank_key'] == bank['key']) a],
                    onRenew: () => _openAuth(() => s.bank.connectExisting(bank['key'] as String)),
                    onDisconnect: () => _disconnect(bank),
                    onDelete: () => _delete(bank),
                    onAccount: _accountMenu,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRuns(List<Map<String, Object?>> runs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Storico delle sincronizzazioni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (runs.isEmpty) const Text('Nessuna sincronizzazione ancora.', style: TextStyle(color: AppColors.muted)),
            for (final r in runs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${localTime(r['started_at'] as String?)} · ${r['account_label'] ?? '—'}'),
                subtitle: Text(r['kind'] == 'backfill' ? 'storico completo' : 'incrementale'),
                trailing: SizedBox(
                  width: 140,
                  child: Text(
                    r['ok'] == 1 ? '+${r['n_new']} nuovi' : '${r['error']}',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: r['ok'] == 1 ? AppColors.pos : AppColors.neg),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.catalog, required this.linked});
  final List<String>? catalog;
  final Set<String> linked;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    final names = catalog?.where((n) => n.toLowerCase().contains(_query.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .7,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Collega una banca', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Prima collega il conto alla tua app nel Control Panel di Enable Banking: la banca compare '
              'qui solo se il login va a buon fine.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            if (catalog == null)
              const Text('Elenco banche non disponibile in questo momento: riprova più tardi.',
                  key: Key('catalog-unavailable'))
            else ...[
              TextField(
                decoration: const InputDecoration(hintText: 'Cerca la banca', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  for (final name in names!)
                    ListTile(
                      title: Text(widget.linked.contains(name) ? '$name (già collegata)' : name),
                      onTap: () => Navigator.pop(context, name),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
          color: primary ? AppColors.accent : AppColors.surface2,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 52, height: 52, child: Icon(icon, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

class _BankCard extends StatelessWidget {
  const _BankCard({
    required this.bank,
    required this.consent,
    required this.alert,
    required this.accounts,
    required this.onRenew,
    required this.onDisconnect,
    required this.onDelete,
    required this.onAccount,
  });

  final Map<String, Object?> bank;
  final Map<String, Object?>? consent;
  final ConsentAlert? alert;
  final List<Map<String, Object?>> accounts;
  final VoidCallback onRenew;
  final VoidCallback onDisconnect;
  final VoidCallback onDelete;
  final void Function(Map<String, Object?>) onAccount;

  (String, Color) get _state {
    final c = consent;
    if (c == null) return ('Non collegata', AppColors.muted);
    if (c['status'] == 'revoked') return ('Scollegata · lo storico resta', AppColors.muted);
    final a = alert;
    if (a != null && a.expired) return ('Consenso scaduto', AppColors.neg);
    if (a != null) return ('Consenso: ${daysLeft(a.days)}', AppColors.warn);
    return ('Consenso valido fino al ${localTime(c['valid_until'] as String?)}', AppColors.muted);
  }

  @override
  Widget build(BuildContext context) {
    final c = consent;
    final (state, color) = _state;
    final renewLabel = c == null ? 'Collega' : (c['status'] == 'revoked' ? 'Ricollega' : 'Rinnova');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(backgroundColor: AppColors.surface2, child: Icon(Icons.account_balance, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bank['label'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text(state, key: Key('state-${bank['key']}'), style: TextStyle(color: color, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _RoundAction(
              icon: Icons.sync,
              label: renewLabel,
              primary: c == null || alert != null || c['status'] != 'active',
              onTap: onRenew,
            ),
            if (c != null && c['status'] == 'active')
              _RoundAction(icon: Icons.link_off, label: 'Scollega', onTap: onDisconnect),
            _RoundAction(icon: Icons.delete_outline, label: 'Elimina', onTap: onDelete),
          ]),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nessun conto.', style: TextStyle(color: AppColors.muted)),
            ),
          for (final a in accounts) _AccountRow(account: a, onTap: () => onAccount(a)),
        ]),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});
  final Map<String, Object?> account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final hidden = a['hidden'] == 1;
    final balance = a['balance'] as Map<String, Object?>?;
    final currency = a['currency'] as String?;
    final title = '${a['nickname'] ?? a['name'] ?? 'Conto'}'
        '${currency != null && currency != 'EUR' ? ' · $currency' : ''}';
    final sub = [
      if (a['iban'] != null) maskIban(a['iban'] as String?),
      'aggiornato ${localTime(a['last_sync_at'] as String?)}',
      if (a['uid'] == null) 'non attivo',
      if (hidden) 'nascosto',
    ].join(' · ');
    return Opacity(
      opacity: hidden ? .55 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(hidden ? Icons.visibility_off_outlined : Icons.account_balance_wallet_outlined),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        trailing: Text(
          balance == null ? '—' : money(balance['amount_cents'] as int, balance['currency'] as String?),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: onTap,
      ),
    );
  }
}

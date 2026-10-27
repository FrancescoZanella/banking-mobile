import 'package:flutter/material.dart';

import 'settings_screen.dart';
import 'theme.dart';

/// Struttura dell'app: barra in basso con 5 voci (Home, Analisi, Movimenti,
/// Budget, Altro). Le pagine arrivano nelle fasi successive.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Analisi'),
    NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Movimenti'),
    NavigationDestination(icon: Icon(Icons.track_changes_outlined), selectedIcon: Icon(Icons.track_changes), label: 'Budget'),
    NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Altro'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ComingSoon(title: 'Home', phase: 4),
      const ComingSoon(title: 'Analisi spese', phase: 5),
      const ComingSoon(title: 'Movimenti', phase: 4),
      const ComingSoon(title: 'Budget', phase: 6),
      const MorePage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

/// "Altro": Flussi, Categorie, Conti, Impostazioni.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, Widget page) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        const Text('Altro', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            item(Icons.swap_horiz, 'Flussi', const Scaffold(body: SafeArea(child: ComingSoon(title: 'Entrate e flusso di cassa', phase: 5)))),
            item(Icons.category_outlined, 'Categorie', const Scaffold(body: SafeArea(child: ComingSoon(title: 'Categorie', phase: 6)))),
            item(Icons.account_balance_outlined, 'Conti', const Scaffold(body: SafeArea(child: ComingSoon(title: 'Conti', phase: 3)))),
            item(Icons.settings_outlined, 'Impostazioni', const SettingsScreen()),
          ]),
        ),
      ],
    );
  }
}

/// Pagina segnaposto finché la sua fase non è sviluppata.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.phase});
  final String title;
  final int phase;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('In arrivo (fase $phase).', style: const TextStyle(color: AppColors.muted)),
        ]),
      );
}

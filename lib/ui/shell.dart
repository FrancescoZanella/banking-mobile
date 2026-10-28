import 'package:flutter/material.dart';

import 'accounts_screen.dart';
import 'analysis_screen.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';
import 'flows_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'transactions_screen.dart';

/// Struttura dell'app: barra in basso con 5 voci (Home, Analisi, Movimenti,
/// Budget, Altro).
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
      HomeScreen(
        onShowAll: () => setState(() => _index = 2),
        onShowAnalysis: () => setState(() => _index = 1),
        onShowBudget: () => setState(() => _index = 3),
        onShowAccounts: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountsScreen())),
      ),
      const AnalysisScreen(),
      const TransactionsScreen(),
      const BudgetScreen(),
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
            item(Icons.swap_horiz, 'Flussi', const FlowsScreen()),
            item(Icons.category_outlined, 'Categorie', const CategoriesScreen()),
            item(Icons.account_balance_outlined, 'Conti', const AccountsScreen()),
            item(Icons.settings_outlined, 'Impostazioni', const SettingsScreen()),
          ]),
        ),
      ],
    );
  }
}

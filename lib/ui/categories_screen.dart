import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/defaults.dart';
import '../domain/budget.dart' show Outcome;
import '../domain/categories.dart';
import 'theme.dart';
import 'widgets.dart';

/// Colori proposti per una nuova categoria (sul web c'è il selettore libero).
const colorChoices = [
  '#5e60ce', '#2a9d8f', '#e76f51', '#457b9d', '#f4a261', '#9c27b0', '#43aa8b',
  '#277da1', '#90be6d', '#bc4749', '#8d6e63', '#e9c46a', '#ef476f', '#adb5bd',
];

/// Categorie e regole. Come categories.html del web.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  Future<(List<Map<String, Object?>>, List<Map<String, Object?>>)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<Map<String, Object?>>, List<Map<String, Object?>>)> _load() async {
    final db = Services.of(context).db;
    return (await categoriesWithCount(db), await rules(db));
  }

  /// Dopo una modifica: ricarica e avvisa le altre pagine (categorie ricalcolate).
  void _changed([Outcome? o]) {
    if (!mounted) return;
    if (o != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(o.text),
        backgroundColor: o.ok ? AppColors.surface3 : const Color(0xFF5A2020),
      ));
    }
    Services.of(context).sync.notifyChanged();
    setState(() {
      _data = _load();
    });
  }

  Future<void> _pickIcon(Map<String, Object?> c) async {
    final icon = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Icona di ${c['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: IconPicker(
                selected: c['icon'] as String? ?? defaultIcon,
                color: c['color'] as String?,
                onPicked: (i) => Navigator.pop(context, i),
              ),
            ),
          ),
        ]),
      ),
    );
    if (icon == null || !mounted) return;
    await setIcon(Services.of(context).db, c['id'] as int, icon);
    _changed();
  }

  Future<void> _delete(Map<String, Object?> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare la categoria «${c['name']}»?'),
        content: const Text('I movimenti verranno ricategorizzati.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.neg)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await deleteCategory(Services.of(context).db, c['id'] as int);
    _changed();
  }

  Future<void> _newCategory() async {
    final result = await showModalBottomSheet<(String, String, String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _NewCategory(),
    );
    if (result == null || !mounted) return;
    final (name, kind, color, icon) = result;
    _changed(await createCategory(Services.of(context).db, name: name, kind: kind, color: color, icon: icon));
  }

  Future<void> _newRule(List<Map<String, Object?>> categories) async {
    final result = await showModalBottomSheet<(String, String, int)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _NewRule(categories: categories),
    );
    if (result == null || !mounted) return;
    final (field, pattern, categoryId) = result;
    _changed(await createRule(Services.of(context).db, field: field, pattern: pattern, categoryId: categoryId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorie e regole')),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final (categories, ruleRows) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Categorie', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    for (final c in categories)
                      ListTile(
                        key: Key('category-${c['id']}'),
                        contentPadding: const EdgeInsets.only(left: 12),
                        leading: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _pickIcon(c),
                          child: CategoryAvatar(icon: c['icon'] as String?, color: c['color'] as String?),
                        ),
                        title: Text(c['name'] as String),
                        subtitle: Text('${kinds[c['kind']]} · ${c['n']} movimenti',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        onTap: () => _pickIcon(c),
                        trailing: IconButton(
                          tooltip: 'Elimina',
                          icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                          onPressed: () => _delete(c),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Text("Tocca una categoria per cambiarne l'icona.",
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FilledButton.icon(
                        key: const Key('new-category'),
                        onPressed: _newCategory,
                        icon: const Icon(Icons.add),
                        label: const Text('Nuova categoria'),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Regole automatiche', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text(
                          'Una regola «testo» si applica se controparte o descrizione contengono il testo; '
                          '«MCC» usa il codice categoria esercente fornito da alcune banche. Le categorie '
                          'scelte a mano non vengono mai sovrascritte.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FilledButton.icon(
                        key: const Key('new-rule'),
                        onPressed: () => _newRule(categories),
                        icon: const Icon(Icons.add),
                        label: const Text('Nuova regola'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final r in ruleRows)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 12),
                        title: Text.rich(TextSpan(children: [
                          TextSpan(text: '${r['field']} ', style: const TextStyle(color: AppColors.muted)),
                          TextSpan(text: r['pattern'] as String),
                        ])),
                        subtitle: Text(r['category_name'] as String, style: const TextStyle(color: AppColors.muted)),
                        trailing: IconButton(
                          tooltip: 'Elimina regola',
                          icon: const Icon(Icons.close, color: AppColors.muted),
                          onPressed: () async {
                            await deleteRule(Services.of(context).db, r['id'] as int);
                            _changed();
                          },
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Griglia delle icone consentite (icon_picker del web).
class IconPicker extends StatelessWidget {
  const IconPicker({super.key, required this.selected, required this.onPicked, this.color});
  final String selected;
  final String? color;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final icon in iconChoices)
          InkWell(
            key: Key('icon-$icon'),
            customBorder: const CircleBorder(),
            onTap: () => onPicked(icon),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: icon == selected ? AppColors.accent : Colors.transparent, width: 2),
              ),
              child: CategoryAvatar(icon: icon, color: color ?? '#adb5bd', size: 40),
            ),
          ),
      ]);
}

class _NewCategory extends StatefulWidget {
  const _NewCategory();

  @override
  State<_NewCategory> createState() => _NewCategoryState();
}

class _NewCategoryState extends State<_NewCategory> {
  final _name = TextEditingController();
  String _kind = 'expense';
  String _color = colorChoices.first;
  String _icon = defaultIcon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Nuova categoria', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              key: const Key('category-name'),
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(hintText: 'Nome'),
            ),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Spesa')),
                ButtonSegment(value: 'income', label: Text('Entrata')),
                ButtonSegment(value: 'transfer', label: Text('Giroconto')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 14),
            const Text('Colore', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in colorChoices)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: hexColor(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: c == _color ? Colors.white : Colors.transparent, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            const Text('Icona', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 6),
            IconPicker(selected: _icon, color: _color, onPicked: (i) => setState(() => _icon = i)),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('category-save'),
              onPressed: () => Navigator.pop(context, (_name.text, _kind, _color, _icon)),
              child: const Text('Aggiungi'),
            ),
          ]),
        ),
      );
}

class _NewRule extends StatefulWidget {
  const _NewRule({required this.categories});
  final List<Map<String, Object?>> categories;

  @override
  State<_NewRule> createState() => _NewRuleState();
}

class _NewRuleState extends State<_NewRule> {
  final _pattern = TextEditingController();
  String _field = 'text';
  int? _category;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Nuova regola', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'text', label: Text('testo')),
              ButtonSegment(value: 'mcc', label: Text('MCC')),
            ],
            selected: {_field},
            onSelectionChanged: (s) => setState(() => _field = s.first),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('rule-pattern'),
            controller: _pattern,
            maxLength: 80,
            decoration: const InputDecoration(hintText: 'es. esselunga'),
          ),
          DropdownButtonFormField<int>(
            key: const Key('rule-category'),
            value: _category,
            isExpanded: true,
            hint: const Text('Categoria…'),
            dropdownColor: AppColors.surface2,
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('rule-save'),
            onPressed: _category == null ? null : () => Navigator.pop(context, (_field, _pattern.text, _category!)),
            child: const Text('Aggiungi'),
          ),
        ]),
      );
}

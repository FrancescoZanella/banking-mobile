import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../domain/transactions.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cambio di categoria condiviso da dettaglio, scorrimento, selezione multipla e
/// Smista: salva, vibra, toglie le notifiche e mostra «Annulla».

/// Elenco delle categorie in un pannello dal basso; null se chiuso senza scelta.
/// [income]: quelle dello stesso tipo del movimento vengono prima.
Future<int?> pickCategory(BuildContext context, {bool? income, String title = 'Scegli la categoria'}) async {
  final categories = await allCategories(Services.of(context).db);
  if (!context.mounted) return null;
  final kind = income == null ? null : (income ? 'income' : 'expense');
  final sorted = [
    ...categories.where((c) => c['kind'] == kind),
    ...categories.where((c) => c['kind'] != kind),
  ];
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final c in sorted)
              ListTile(
                key: Key('pick-${c['id']}'),
                leading: CategoryAvatar(icon: c['icon'] as String?, color: c['color'] as String?, size: 34),
                title: Text(c['name'] as String),
                onTap: () => Navigator.pop(ctx, c['id'] as int),
              ),
          ]),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Assegna [categoryId] ai movimenti (null = torna automatica, solo per uno).
/// [makeRule] vale solo per un movimento. Dopo il salvataggio: vibrazione,
/// notifiche tolte, pagine aggiornate e un messaggio con «Annulla».
Future<void> applyCategory(BuildContext context, List<String> txIds, int? categoryId, {bool makeRule = false}) async {
  if (txIds.isEmpty) return;
  final s = Services.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final single = txIds.length == 1;
  String? pattern;
  if (single && makeRule) {
    final rows = await s.db.query('transactions', columns: ['counterparty'], where: 'id = ?', whereArgs: [txIds.first]);
    if (rows.isNotEmpty) pattern = rulePattern(rows.first['counterparty'] as String?);
  }
  final undo = await categorySnapshot(s.db, txIds, rulePattern: pattern);
  String? message;
  if (single) {
    message = await setCategory(s.db, txIds.first, categoryId, makeRule: makeRule);
  } else if (categoryId != null) {
    await setCategoryMany(s.db, txIds, categoryId);
  }
  for (final id in txIds) {
    await s.dismissNotification(id);
  }
  s.sync.notifyChanged();
  unawaited(HapticFeedback.lightImpact());

  final name = categoryId == null
      ? 'Automatica'
      : (await s.db.query('categories', columns: ['name'], where: 'id = ?', whereArgs: [categoryId]))
          .firstOrNull?['name'];
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: const Key('category-undo'),
      content: Text(message ?? (single ? 'Categoria: $name' : '$name · ${txIds.length} movimenti')),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Annulla',
        onPressed: () async {
          await undoCategory(s.db, undo);
          s.sync.notifyChanged();
          unawaited(HapticFeedback.selectionClick());
        },
      ),
    ));
}

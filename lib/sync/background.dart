/// Sincronizzazione in background alle 7, alle 14 e alle 23 (l'equivalente
/// dell'attività pianificata di Windows della versione web), notifiche dei
/// consensi e dei movimenti da categorizzare, con i pulsanti delle categorie.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'package:sqflite_common/sqlite_api.dart';

import '../bank/enable_banking.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../data/secure_database.dart';
import '../data/secure_store.dart';
import '../domain/reports.dart';
import '../domain/to_categorize.dart';
import '../domain/transactions.dart';
import 'schedule.dart';
import 'sync.dart';

/// Vecchio lavoro periodico «ogni ~12 ore»: si cancella all'avvio.
const _oldPeriodicTask = 'banking-sync';
const _taskName = 'banking-sync-slot';
const _channelId = 'consensi';
const _movementsChannel = 'movimenti';
const _movementsGroup = 'movimenti-da-categorizzare';
const _payloadPrefix = 'tx:';
const _actionPrefix = 'cat:';
final _notifications = FlutterLocalNotificationsPlugin();

/// Programma la prossima sincronizzazione (7, 14 o 23 ora italiana). WorkManager
/// non garantisce il minuto: con il telefono in risparmio energetico può partire
/// un po' dopo. Parte solo con la rete.
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().cancelByUniqueName(_oldPeriodicTask);
  await _scheduleNext(ExistingWorkPolicy.keep);
}

/// [policy]: all'avvio dell'app `keep` (se è già in coda resta quella);
/// dentro il lavoro `update`, cioè in coda dopo quello che sta girando.
Future<void> _scheduleNext(ExistingWorkPolicy policy) {
  final now = DateTime.now().toUtc();
  return Workmanager().registerOneOffTask(
    _taskName,
    _taskName,
    initialDelay: nextSyncSlot(now).difference(now),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: policy,
  );
}

/// [onOpenTransaction] riceve l'id del movimento quando si tocca la sua notifica.
Future<void> initNotifications({bool requestPermission = false, void Function(String txId)? onOpenTransaction}) async {
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
    onDidReceiveNotificationResponse: (response) {
      final txId = _txIdFrom(response.payload);
      // I pulsanti delle categorie arrivano a [onNotificationAction].
      if (txId != null && response.actionId == null) onOpenTransaction?.call(txId);
    },
    onDidReceiveBackgroundNotificationResponse: onNotificationAction,
  );
  if (requestPermission) {
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}

String? _txIdFrom(String? payload) =>
    payload != null && payload.startsWith(_payloadPrefix) ? payload.substring(_payloadPrefix.length) : null;

/// Id della categoria del pulsante toccato, se è uno dei nostri.
int? categoryFromAction(String? actionId) =>
    actionId != null && actionId.startsWith(_actionPrefix) ? int.tryParse(actionId.substring(_actionPrefix.length)) : null;

/// Pulsante di una categoria nella notifica: la assegna al movimento senza aprire
/// l'app (solo a quello, senza creare regole). Android lo esegue in un motore
/// Flutter a parte; la notifica è già stata tolta.
@pragma('vm:entry-point')
Future<void> onNotificationAction(NotificationResponse response) async {
  final txId = _txIdFrom(response.payload), categoryId = categoryFromAction(response.actionId);
  if (txId == null || categoryId == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openSecureDatabase(KeystoreSecretStore(), background: true);
  try {
    await setCategory(db, txId, categoryId);
  } finally {
    await db.close();
  }
}

/// Movimento della notifica che ha avviato l'app (app chiusa), se c'è.
Future<String?> launchTransaction() async {
  final details = await _notifications.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp != true) return null;
  return _txIdFrom(details?.notificationResponse?.payload);
}

/// Id stabile della notifica di un movimento (gli id 1 e 2 sono riservati).
int movementNotificationId(String txId) {
  var hash = 0x811c9dc5; // FNV-1a a 32 bit
  for (final unit in txId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return 1000 + (hash & 0x3fffffff);
}

/// Una notifica per ogni movimento nuovo da categorizzare, poi segnati come
/// notificati. Sulla schermata di blocco il contenuto resta nascosto.
Future<void> notifyToCategorize(DatabaseExecutor db) async {
  final rows = await toNotify(db);
  if (rows.isEmpty) return;
  final quick = {
    for (final income in [false, true]) income: await quickCategories(db, income: income),
  };
  // Pulsanti nascosti sulla schermata di blocco insieme al contenuto (private).
  NotificationDetails details(bool income) => NotificationDetails(
        android: AndroidNotificationDetails(_movementsChannel, 'Movimenti da categorizzare',
            channelDescription: 'Movimenti nuovi che le regole non hanno saputo classificare',
            visibility: NotificationVisibility.private,
            groupKey: _movementsGroup,
            actions: [
              for (final c in quick[income]!) AndroidNotificationAction('$_actionPrefix${c['id']}', c['name'] as String),
            ]),
      );
  for (final t in rows) {
    final party = [t['counterparty'], t['description']]
        .whereType<String>()
        .firstWhere((v) => v.isNotEmpty, orElse: () => 'Movimento');
    final cents = t['amount_cents'] as int;
    await _notifications.show(
      id: movementNotificationId(t['id'] as String),
      title: '$party · ${cents > 0 ? '+' : ''}${money(cents, t['currency'] as String?)}',
      body: '${t['bank_label']}${t['status'] == 'PDNG' ? ' · in attesa' : ''} · tocca per le altre categorie',
      payload: '$_payloadPrefix${t['id']}',
      notificationDetails: details(cents > 0),
    );
  }
  if (rows.length > 1) {
    // Riepilogo del gruppo: Android lo mostra quando le notifiche sono più d'una.
    await _notifications.show(
      id: 2,
      title: '${rows.length} movimenti da categorizzare',
      body: 'Scegli la categoria dai pulsanti o tocca un movimento',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_movementsChannel, 'Movimenti da categorizzare',
            visibility: NotificationVisibility.private, groupKey: _movementsGroup, setAsGroupSummary: true),
      ),
    );
  }
  await markNotified(db, [for (final t in rows) t['id'] as String]);
}

/// Toglie la notifica di un movimento appena categorizzato.
Future<void> cancelMovementNotification(String txId) =>
    _notifications.cancel(id: movementNotificationId(txId));

/// Testo della notifica: solo nomi delle banche e giorni, mai importi.
String consentNotificationText(List<ConsentAlert> alerts) => alerts
    .map((a) => a.expired ? '${a.label} scaduto' : '${a.label} ${daysLeft(a.days)}')
    .join('; ');

Future<void> notifyConsents(List<ConsentAlert> alerts) async {
  if (alerts.isEmpty) return;
  await _notifications.show(
    id: 1,
    title: 'Consenso bancario da rinnovare',
    body: consentNotificationText(alerts),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(_channelId, 'Consensi bancari',
          channelDescription: 'Avvisi di consensi in scadenza o scaduti',
          // Contenuto nascosto nella schermata di blocco del telefono.
          visibility: NotificationVisibility.private),
    ),
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final secrets = KeystoreSecretStore();
      final db = await openSecureDatabase(secrets, background: true);
      try {
        await syncAll(db, EnableBankingClient(() => readCredentials(secrets)), onlyDue: true);
        await initNotifications();
        await notifyToCategorize(db);
        await notifyConsents(await consentAlerts(db));
      } finally {
        await db.close();
      }
    } catch (_) {
      // Un errore qui non deve fermare la catena: il prossimo orario va comunque programmato.
    } finally {
      if (task == _taskName) await _scheduleNext(ExistingWorkPolicy.update);
    }
    // Sempre «riuscito»: un fallimento annullerebbe anche il lavoro messo in coda dopo.
    return true;
  });
}

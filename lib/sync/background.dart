/// Sincronizzazione in background ad app chiusa (l'equivalente dell'attività
/// pianificata di Windows della versione web) e notifiche dei consensi.
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
import 'sync.dart';

const _taskName = 'banking-sync';
const _channelId = 'consensi';
const _movementsChannel = 'movimenti';
const _movementsGroup = 'movimenti-da-categorizzare';
const _payloadPrefix = 'tx:';
final _notifications = FlutterLocalNotificationsPlugin();

/// Registra il lavoro periodico: Android lo esegue circa ogni 12 ore, quando
/// c'è rete. I conti aggiornati da meno di 12 ore vengono comunque saltati.
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName,
    _taskName,
    frequency: const Duration(hours: 12),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// [onOpenTransaction] riceve l'id del movimento quando si tocca la sua notifica.
Future<void> initNotifications({bool requestPermission = false, void Function(String txId)? onOpenTransaction}) async {
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
    onDidReceiveNotificationResponse: (response) {
      final txId = _txIdFrom(response.payload);
      if (txId != null) onOpenTransaction?.call(txId);
    },
  );
  if (requestPermission) {
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}

String? _txIdFrom(String? payload) =>
    payload != null && payload.startsWith(_payloadPrefix) ? payload.substring(_payloadPrefix.length) : null;

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
  const details = NotificationDetails(
    android: AndroidNotificationDetails(_movementsChannel, 'Movimenti da categorizzare',
        channelDescription: 'Movimenti nuovi che le regole non hanno saputo classificare',
        visibility: NotificationVisibility.private,
        groupKey: _movementsGroup),
  );
  for (final t in rows) {
    final party = [t['counterparty'], t['description']]
        .whereType<String>()
        .firstWhere((v) => v.isNotEmpty, orElse: () => 'Movimento');
    final cents = t['amount_cents'] as int;
    await _notifications.show(
      id: movementNotificationId(t['id'] as String),
      title: '$party · ${cents > 0 ? '+' : ''}${money(cents, t['currency'] as String?)}',
      body: '${t['bank_label']}${t['status'] == 'PDNG' ? ' · in attesa' : ''} · tocca per scegliere la categoria',
      payload: '$_payloadPrefix${t['id']}',
      notificationDetails: details,
    );
  }
  if (rows.length > 1) {
    // Riepilogo del gruppo: Android lo mostra quando le notifiche sono più d'una.
    await _notifications.show(
      id: 2,
      title: '${rows.length} movimenti da categorizzare',
      body: 'Tocca un movimento per scegliere la categoria',
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
    final secrets = KeystoreSecretStore();
    final db = await openSecureDatabase(secrets);
    try {
      await syncAll(db, EnableBankingClient(() => readCredentials(secrets)), onlyDue: true);
      await initNotifications();
      await notifyToCategorize(db);
      await notifyConsents(await consentAlerts(db));
    } finally {
      await db.close();
    }
    return true;
  });
}

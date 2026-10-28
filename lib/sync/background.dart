/// Sincronizzazione in background ad app chiusa (l'equivalente dell'attività
/// pianificata di Windows della versione web) e notifiche dei consensi.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../bank/enable_banking.dart';
import '../core/dates.dart';
import '../data/secure_database.dart';
import '../data/secure_store.dart';
import '../domain/reports.dart';
import 'sync.dart';

const _taskName = 'banking-sync';
const _channelId = 'consensi';
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

Future<void> initNotifications({bool requestPermission = false}) async {
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
  );
  if (requestPermission) {
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}

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
      await notifyConsents(await consentAlerts(db));
    } finally {
      await db.close();
    }
    return true;
  });
}

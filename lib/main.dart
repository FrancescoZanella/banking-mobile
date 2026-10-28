import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/app.dart';
import 'app/return_links.dart';
import 'app/services.dart';
import 'bank/enable_banking.dart';
import 'data/secure_database.dart';
import 'data/secure_store.dart';
import 'security/app_lock.dart';
import 'sync/background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = KeystoreSecretStore();
  final db = await openSecureDatabase(secrets);
  final services = AppServices(
    db: db,
    secrets: secrets,
    api: EnableBankingClient(() => readCredentials(secrets)),
    pickPem: _pickPem,
    openBankPage: _openBankPage,
    isDeviceRooted: _isDeviceRooted,
    afterSync: notifyToCategorize,
    dismissNotification: cancelMovementNotification,
  );
  // Tocco su una notifica «da categorizzare»: si apre il dettaglio del movimento.
  final openTransactions = StreamController<String>();
  await initNotifications(requestPermission: true, onOpenTransaction: openTransactions.add);
  if (await launchTransaction() case final txId?) openTransactions.add(txId);
  await scheduleBackgroundSync();
  runApp(BankingApp(
    services: services,
    lock: AppLock(DeviceAuthenticator()),
    // Anche quando HyperOS ha chiuso l'app durante il login con la banca.
    links: returnLinks(PluginLinkSource()),
    openTransactions: openTransactions.stream,
  ));
}

/// Selettore di sistema: legge il .pem una volta e ne cancella la copia temporanea.
Future<PickedFile?> _pickPem() async {
  try {
    final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.length > 16 * 1024) return null;
    return (name: file.name, content: utf8.decode(bytes));
  } finally {
    // Il selettore copia il file nella cache dell'app: la chiave privata non deve
    // restare lì in chiaro (vive solo nel Keystore).
    await FilePicker.clearTemporaryFiles();
  }
}

const _customTabs = MethodChannel('bankingmobile/custom_tabs');

/// Login con la banca in una Custom Tab effimera di Chrome (come l'incognito):
/// pagina vera della banca, indirizzo visibile, l'app non può leggerla e nulla
/// resta nel Chrome di tutti i giorni. Ripiego: Custom Tab normale.
Future<bool> _openBankPage(Uri url) async {
  if (url.scheme != 'https') return false;
  try {
    final mode = await _customTabs.invokeMethod<String>('open', {'url': url.toString()});
    if (mode != null) return true;
  } on PlatformException {
    // ripiego sotto
  }
  return launchUrl(url, mode: LaunchMode.inAppBrowserView);
}

/// Indizi di root dal codice nativo; in caso di errore nessun avviso.
Future<bool> _isDeviceRooted() async {
  try {
    return await const MethodChannel('bankingmobile/device').invokeMethod<bool>('isRooted') ?? false;
  } on PlatformException {
    return false;
  }
}

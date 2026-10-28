import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/app.dart';
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
  );
  await initNotifications(requestPermission: true);
  await scheduleBackgroundSync();
  runApp(BankingApp(
    services: services,
    lock: AppLock(DeviceAuthenticator()),
    // Include anche il link che ha avviato l'app (ritorno dalla banca ad app chiusa).
    links: AppLinks().uriLinkStream,
  ));
}

/// Selettore di sistema: legge il .pem una volta, senza copiarlo altrove.
Future<PickedFile?> _pickPem() async {
  final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null || bytes.length > 16 * 1024) return null;
  return (name: file.name, content: utf8.decode(bytes));
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

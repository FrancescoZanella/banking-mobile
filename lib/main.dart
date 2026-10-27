import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

/// Login con la banca in una Custom Tab di Chrome: pagina vera della banca,
/// con barra degli indirizzi visibile, senza che l'app possa leggerla.
Future<bool> _openBankPage(Uri url) {
  if (url.scheme != 'https') return Future.value(false);
  return launchUrl(url, mode: LaunchMode.inAppBrowserView);
}

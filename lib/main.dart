import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'bank/enable_banking.dart';
import 'data/secure_database.dart';
import 'data/secure_store.dart';
import 'security/app_lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = KeystoreSecretStore();
  final db = await openSecureDatabase(secrets);
  final services = AppServices(
    db: db,
    secrets: secrets,
    api: EnableBankingClient(() => readCredentials(secrets)),
    pickPem: _pickPem,
  );
  runApp(BankingApp(services: services, lock: AppLock(DeviceAuthenticator())));
}

/// Selettore di sistema: legge il .pem una volta, senza copiarlo altrove.
Future<PickedFile?> _pickPem() async {
  final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null || bytes.length > 16 * 1024) return null;
  return (name: file.name, content: utf8.decode(bytes));
}

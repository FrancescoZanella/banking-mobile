import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../bank/enable_banking.dart';

/// Archivio di segreti. Sul telefono è il Keystore di Android
/// (`flutter_secure_storage`); nei test un'implementazione in memoria.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreSecretStore implements SecretStore {
  // I valori sono cifrati con una chiave del Keystore hardware, non esportabile.
  // La chiave è usabile senza sblocco (scelta di progetto): serve alla
  // sincronizzazione in background ad app chiusa.
  final _storage = const FlutterSecureStorage(aOptions: AndroidOptions());

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Chiavi usate nell'archivio.
class SecretKeys {
  static const dbKey = 'db-key';
  static const appId = 'eb-app-id';
  static const privateKey = 'eb-private-key';
}

/// Chiave del database: 256 bit casuali, creata al primo avvio.
Future<String> databaseKey(SecretStore store, [Random? random]) async {
  final existing = await store.read(SecretKeys.dbKey);
  if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) return existing;
  if (existing != null) throw StateError('Chiave del database in formato non valido.');
  final r = random ?? Random.secure();
  final key = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  await store.write(SecretKeys.dbKey, key);
  return key;
}

Future<Credentials?> readCredentials(SecretStore store) async {
  final appId = await store.read(SecretKeys.appId);
  final pem = await store.read(SecretKeys.privateKey);
  if (appId == null || pem == null) return null;
  return Credentials(appId, pem);
}

/// Controlla APP_ID e chiave privata prima di salvarli: l'APP_ID è un UUID e
/// la chiave deve essere una chiave privata RSA in formato PEM.
String? validateCredentials(String appId, String pem) {
  if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
      .hasMatch(appId.trim())) {
    return "L'APP_ID deve essere l'identificativo dell'applicazione (es. 12345678-…).";
  }
  if (!pem.contains('-----BEGIN') || !pem.contains('PRIVATE KEY-----')) {
    return 'Il file scelto non è una chiave privata (.pem).';
  }
  return null;
}

Future<void> saveCredentials(SecretStore store, String appId, String pem) async {
  await store.write(SecretKeys.appId, appId.trim());
  await store.write(SecretKeys.privateKey, pem.trim());
}

Future<void> deleteCredentials(SecretStore store) async {
  await store.delete(SecretKeys.appId);
  await store.delete(SecretKeys.privateKey);
}

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'database.dart';
import 'secure_store.dart';

const databaseFileName = 'banking.db';

/// Apre il database cifrato con SQLCipher (AES-256) nella memoria privata
/// dell'app. La chiave sta nel Keystore: senza, il file è illeggibile.
Future<cipher.Database> openSecureDatabase(SecretStore store) async {
  final key = await databaseKey(store);
  final path = p.join(await cipher.getDatabasesPath(), databaseFileName);
  final db = await cipher.openDatabase(path, password: key, singleInstance: true);
  await initDb(db);
  return db;
}

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'database.dart';
import 'secure_store.dart';

const databaseFileName = 'banking.db';

/// Apre il database cifrato con SQLCipher (AES-256) nella memoria privata
/// dell'app. La chiave sta nel Keystore: senza, il file è illeggibile.
///
/// [background]: sync pianificata e pulsanti delle notifiche. Girano nello
/// stesso processo dell'app, magari aperta: serve una connessione propria,
/// altrimenti il plugin darebbe la stessa e chiuderla chiuderebbe anche
/// quella dell'app. Se l'altra connessione sta scrivendo, si aspetta invece di fallire.
Future<cipher.Database> openSecureDatabase(SecretStore store, {bool background = false}) async {
  final key = await databaseKey(store);
  final path = p.join(await cipher.getDatabasesPath(), databaseFileName);
  final db = await cipher.openDatabase(path, password: key, singleInstance: !background);
  await db.rawQuery('PRAGMA busy_timeout = 10000');
  await initDb(db);
  return db;
}

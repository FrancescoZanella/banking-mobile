// Parità con test_core.py::test_db_is_encrypted: gira sul telefono, dove c'è SQLCipher.
import 'dart:convert';
import 'dart:io';

import 'package:bankingmobile/data/secure_database.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('il database è cifrato e illeggibile senza chiave', (tester) async {
    final path = p.join(await cipher.getDatabasesPath(), databaseFileName);
    await cipher.deleteDatabase(path);

    final store = MemorySecretStore();
    final db = await openSecureDatabase(store);
    await db.insert('settings', {'key': 'probe', 'value': 'segreto'});
    await db.close();

    // Senza password: SQLCipher non riesce a leggere nemmeno lo schema.
    await expectLater(
      () async {
        final plain = await cipher.openDatabase(path, singleInstance: false);
        try {
          await plain.rawQuery('SELECT * FROM sqlite_master');
        } finally {
          await plain.close();
        }
      },
      throwsA(anything),
    );
    // Con una chiave sbagliata, idem.
    await expectLater(
      () async {
        final wrong = await cipher.openDatabase(path, password: '00' * 32, singleInstance: false);
        try {
          await wrong.rawQuery('SELECT * FROM sqlite_master');
        } finally {
          await wrong.close();
        }
      },
      throwsA(anything),
    );
    // Il testo non compare nel file.
    final bytes = await File(path).readAsBytes();
    expect(latin1.decode(bytes, allowInvalid: true).contains('segreto'), isFalse);
    await cipher.deleteDatabase(path);
  });
}

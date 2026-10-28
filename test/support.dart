/// Equivalente di `tests/conftest.py` della versione web: DB in memoria,
/// conti e movimenti di prova con la stessa forma delle risposte API.
library;

import 'package:bankingmobile/core/dates.dart';
import 'package:bankingmobile/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const bankLabels = {'zeta': 'Zeta', 'theta': 'ThetaBank'};

Future<Database> openTestDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await initDb(db);
  for (final key in bankLabels.keys) {
    await addBank(db, key);
  }
  return db;
}

/// Come una banca collegata dalla pagina Conti: con il nome del catalogo.
Future<void> addBank(DatabaseExecutor db, String key) async {
  final label = bankLabels[key] ?? key;
  await db.rawInsert(
    "INSERT OR IGNORE INTO banks (key, label, aspsp_name, country) VALUES (?, ?, ?, 'IT')",
    [key, label, label],
  );
}

Future<int> addAccount(DatabaseExecutor db,
    {String bankKey = 'zeta', String uid = 'uid-1', String? iban, String currency = 'EUR'}) async {
  await addBank(db, bankKey);
  final now = utcNow();
  final consentId = await db.insert('consents', {
    'bank_key': bankKey,
    'session_id': 'sess-$uid',
    'valid_until': '2099-01-01T00:00:00Z',
    'status': 'active',
    'created_at': now,
  });
  return db.insert('accounts', {
    'bank_key': bankKey,
    'uid': uid,
    'consent_id': consentId,
    'iban': iban,
    'currency': currency,
    'created_at': now,
  });
}

Map<String, dynamic> tx(String amount,
    {String indicator = 'DBIT',
    String day = '2026-10-01',
    String? ref,
    String? name = 'Esselunga',
    String status = 'BOOK',
    String? iban,
    List<String>? remittance}) {
  final party = name == null ? null : {'name': name};
  final acc = iban == null ? null : {'iban': iban};
  return {
    'entry_reference': ref,
    'transaction_amount': {'amount': amount, 'currency': 'EUR'},
    'credit_debit_indicator': indicator,
    'creditor': indicator == 'DBIT' ? party : null,
    'creditor_account': indicator == 'DBIT' ? acc : null,
    'debtor': indicator == 'CRDT' ? party : null,
    'debtor_account': indicator == 'CRDT' ? acc : null,
    'status': status,
    'booking_date': day,
    'remittance_information': remittance ?? <String>[],
  };
}

Future<Object?> scalar(DatabaseExecutor db, String sql, [List<Object?>? args]) async =>
    (await db.rawQuery(sql, args)).first.values.first;

/// Al posto di pumpAndSettle: le pagine leggono il DB con I/O reale (fuori dal
/// tempo simulato) e intanto mostrano un indicatore che non si ferma mai.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

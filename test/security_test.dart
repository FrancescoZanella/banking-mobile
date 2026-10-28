// Equivalenti mobile dei test di accesso del web (test_requires_login…,
// test_wrong_password, test_logout_invalidates…, test_detail_requires_login,
// test_auth_pages_have_no_sidebar) e controlli sui segreti.
import 'dart:math';

import 'package:bankingmobile/app/app.dart';
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/bank/enable_banking.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/security/app_lock.dart';
import 'package:bankingmobile/ui/lock_screen.dart';
import 'package:bankingmobile/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

class FakeAuth implements Authenticator {
  AuthOutcome next = AuthOutcome.success;
  int calls = 0;

  @override
  Future<AuthOutcome> authenticate() async {
    calls++;
    return next;
  }
}

const testPem = '-----BEGIN PRIVATE KEY-----\nMIIBVQIBADANBgkqhkiG9w0BAQEFAASCAT8wggE7\n-----END PRIVATE KEY-----';

void main() {
  group('AppLock', () {
    test('bloccata all\'avvio, si sblocca solo con autenticazione riuscita', () async {
      final auth = FakeAuth()..next = AuthOutcome.failed;
      final lock = AppLock(auth);
      expect(lock.locked, isTrue);
      await lock.unlock();
      expect((lock.locked, lock.lastOutcome), (true, AuthOutcome.failed));
      auth.next = AuthOutcome.success;
      await lock.unlock();
      expect(lock.locked, isFalse);
    });

    test('senza blocco schermo sul telefono resta bloccata', () async {
      final lock = AppLock(FakeAuth()..next = AuthOutcome.notConfigured);
      await lock.unlock();
      expect((lock.locked, lock.lastOutcome), (true, AuthOutcome.notConfigured));
    });

    test('si blocca dopo 30 minuti di inattività, non prima', () async {
      var now = DateTime(2026, 10, 27, 10);
      final lock = AppLock(FakeAuth(), clock: () => now);
      await lock.unlock();
      now = now.add(const Duration(minutes: 29));
      lock.checkIdle();
      expect(lock.locked, isFalse);
      lock.touch(); // un tocco azzera il conteggio
      now = now.add(const Duration(minutes: 29));
      lock.checkIdle();
      expect(lock.locked, isFalse);
      now = now.add(const Duration(minutes: 1));
      lock.checkIdle();
      expect(lock.locked, isTrue);
    });
  });

  group('segreti', () {
    test('chiave del database: 256 bit casuali, creata una volta e poi riusata', () async {
      final store = MemorySecretStore();
      final key = await databaseKey(store, Random(1));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
      expect(await databaseKey(store), key);
      store.values[SecretKeys.dbKey] = 'non-valida';
      expect(() => databaseKey(store), throwsStateError);
    });

    test('credenziali validate prima del salvataggio', () {
      expect(validateCredentials('12345678-9abc-4def-8123-456789abcdef', testPem), isNull);
      expect(validateCredentials('non-un-id', testPem), isNotNull);
      expect(validateCredentials('12345678-9abc-4def-8123-456789abcdef', 'ciao'), isNotNull);
    });
  });

  group('app', () {
    late Database db;
    late AppServices services;
    late MemorySecretStore secrets;

    setUp(() async {
      db = await openTestDb();
      secrets = MemorySecretStore();
      services = AppServices(
        db: db,
        secrets: secrets,
        api: EnableBankingClient(() => readCredentials(secrets)),
        pickPem: () async => (name: 'app.pem', content: testPem),
        openBankPage: (url) async => true,
      );
    });
    tearDown(() => db.close());

    testWidgets('bloccata: solo la schermata di sblocco, nessuna pagina con dati', (tester) async {
      final auth = FakeAuth()..next = AuthOutcome.failed;
      await tester.pumpWidget(BankingApp(services: services, lock: AppLock(auth)));
      await settle(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(Shell), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Sblocco non riuscito. Riprova.'), findsOneWidget);

      auth.next = AuthOutcome.success;
      await tester.tap(find.byKey(const Key('unlock')));
      await settle(tester);
      expect(find.byType(Shell), findsOneWidget);
      for (final label in ['Home', 'Analisi', 'Movimenti', 'Budget', 'Altro']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('blocco per inattività nasconde subito i dati', (tester) async {
      var now = DateTime(2026, 10, 27, 10);
      final auth = FakeAuth();
      final lock = AppLock(auth, clock: () => now);
      await tester.pumpWidget(BankingApp(services: services, lock: lock));
      await settle(tester);
      expect(find.byType(Shell), findsOneWidget);
      // Al blocco la schermata chiede subito l'impronta: qui viene negata.
      auth.next = AuthOutcome.failed;
      now = now.add(const Duration(minutes: 31));
      lock.checkIdle();
      await settle(tester);
      expect(find.byType(Shell), findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);
    });

    testWidgets('Altro → Impostazioni: credenziali salvate solo nel Keystore', (tester) async {
      await tester.pumpWidget(BankingApp(services: services, lock: AppLock(FakeAuth())));
      await settle(tester);
      await tester.tap(find.text('Altro').last);
      await settle(tester);
      for (final label in ['Flussi', 'Categorie', 'Conti', 'Impostazioni']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Impostazioni'));
      await settle(tester);

      await tester.tap(find.byKey(const Key('save-credentials')));
      await settle(tester);
      expect(find.text('Scegli il file .pem della chiave privata.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('app-id')), '12345678-9abc-4def-8123-456789abcdef');
      await tester.tap(find.byKey(const Key('pick-pem')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-credentials')));
      await settle(tester);
      final creds = await readCredentials(secrets);
      expect((creds?.appId, creds?.privateKeyPem), ('12345678-9abc-4def-8123-456789abcdef', testPem));
      expect(find.textContaining('cancella il file .pem'), findsOneWidget);
      // Nessun segreto finisce nel database (I/O reale: fuori dal tempo simulato).
      final leaked = await tester.runAsync(
          () => scalar(db, "SELECT count(*) FROM settings WHERE value LIKE '%PRIVATE KEY%'"));
      expect(leaked, 0);
    });
  });
}

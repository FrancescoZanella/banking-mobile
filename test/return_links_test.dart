// Ritorno dalla banca quando HyperOS ha chiuso l'app durante il login (caso
// visto sul telefono il 28/10/2026: banca non salvata, solo la richiesta di sblocco).
import 'dart:async';

import 'package:bankingmobile/app/app.dart';
import 'package:bankingmobile/app/return_links.dart';
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/bank/bank_service.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/security/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bank_test.dart' show FakeApi;
import 'security_test.dart' show FakeAuth;
import 'support.dart';

/// Come il plugin: all'iscrizione ripete il link iniziale, poi i successivi.
class FakeLinks implements LinkSource {
  FakeLinks({this.initialLink, this.latestLink});
  String? initialLink;
  String? latestLink;
  final _controller = StreamController<Uri>();
  void arrive(String link) {
    latestLink = link;
    _controller.add(Uri.parse(link));
  }

  @override
  Future<String?> initial() async => initialLink;

  @override
  Future<String?> latest() async => latestLink;

  @override
  Stream<Uri> get stream async* {
    if (initialLink != null) yield Uri.parse(initialLink!);
    yield* _controller.stream;
  }
}

const vecchio = 'https://francescozanella.github.io/banking/?state=vecchio&code=x';
const nuovo = 'https://francescozanella.github.io/banking/?state=nuovo&code=y';

Future<List<String>> collect(LinkSource source, [Future<void> Function()? during]) async {
  final got = <String>[];
  final sub = returnLinks(source).listen((u) => got.add(u.toString()));
  await Future<void>.delayed(Duration.zero);
  await during?.call();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await sub.cancel();
  return got;
}

void main() {
  group('link di ritorno', () {
    test('app riavviata: vecchio link del task scartato, quello nuovo non si perde', () async {
      // Il nuovo è arrivato prima che Flutter ascoltasse: il plugin non lo ripeterebbe.
      expect(await collect(FakeLinks(initialLink: vecchio, latestLink: nuovo)), [nuovo]);
    });

    test('app aperta dal link: elaborato una volta sola', () async {
      expect(await collect(FakeLinks(initialLink: nuovo, latestLink: nuovo)), [nuovo]);
    });

    test('app già aperta: i link arrivano dallo stream', () async {
      final links = FakeLinks();
      expect(await collect(links, () async => links.arrive(nuovo)), [nuovo]);
    });

    test('nessun link: niente', () async {
      expect(await collect(FakeLinks()), isEmpty);
    });
  });

  group('app bloccata al ritorno dalla banca', () {
    late Database db;
    late FakeApi api;

    setUp(() async {
      db = await openTestDb();
      await db.delete('banks');
      api = FakeApi()
        ..session = (code) => {
              'session_id': 'sess-gamma',
              'access': {'valid_until': '2027-04-24T10:00:00Z'},
              'accounts': [
                {'uid': 'u-int', 'account_id': {'iban': 'IT99Z'}, 'currency': 'EUR'},
              ],
            };
    });
    tearDown(() => db.close());

    testWidgets("app bloccata: l'esito del ritorno compare solo dopo lo sblocco", (tester) async {
      // Un ritorno rifiutato non avvia sincronizzazioni: il test resta semplice.
      // Il salvataggio della banca a login riuscito è verificato in bank_test.
      final services = AppServices(
        db: db,
        secrets: MemorySecretStore(),
        api: api,
        pickPem: () async => null,
        openBankPage: (url) async => true,
      );
      final auth = FakeAuth()..next = AuthOutcome.failed;
      final links = StreamController<Uri>();
      await tester.pumpWidget(BankingApp(services: services, lock: AppLock(auth), links: links.stream));
      await settle(tester);
      links.add(Uri.parse('bankingmobile://callback?state=sconosciuto&code=abc'));
      await settle(tester);
      expect(find.textContaining('rifiutato'), findsNothing); // ancora bloccata

      auth.next = AuthOutcome.success;
      await tester.tap(find.byKey(const Key('unlock')));
      await settle(tester);
      expect(find.textContaining('Ritorno dalla banca rifiutato'), findsOneWidget);
      await links.close();
    });

    testWidgets('errore durante il collegamento: mostrato, mai silenzioso', (tester) async {
      final services = AppServices(
        db: db,
        secrets: MemorySecretStore(),
        api: api,
        pickPem: () async => null,
        openBankPage: (url) async => true,
      );
      await tester.runAsync(() => BankService(db, api, services.sync).connectNew('Banca Beta'));
      final state = api.started.single.$2;
      api.session = (code) => throw StateError('risposta inattesa');

      final links = StreamController<Uri>();
      await tester.pumpWidget(BankingApp(services: services, lock: AppLock(FakeAuth()), links: links.stream));
      await settle(tester);
      links.add(Uri.parse('bankingmobile://callback?state=$state&code=abc'));
      await settle(tester);
      expect(find.textContaining('Collegamento non completato'), findsOneWidget);
      await links.close();
    });
  });
}

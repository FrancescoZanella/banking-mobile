// Grafica: avatar degli esercenti, «Nascondi importi», schermate vuote.
import 'package:bankingmobile/app/services.dart';
import 'package:bankingmobile/data/secure_store.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:bankingmobile/ui/home_screen.dart';
import 'package:bankingmobile/ui/polish.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bank_test.dart' show FakeApi;
import 'support.dart';

void main() {
  test('iniziali e colore degli esercenti: brevi, stabili', () {
    expect(merchantInitials('ESSELUNGA MILANO'), 'EM');
    expect(merchantInitials('Netflix'), 'NE');
    expect(merchantInitials('  bar-centrale '), 'BC');
    expect(merchantInitials('***'), '?');
    expect(merchantColor('Esselunga'), merchantColor(' esselunga'));
  });

  group('Home', () {
    late Database db;
    late AppServices services;

    setUp(() async {
      db = await openTestDb();
      services = AppServices(
        db: db,
        secrets: MemorySecretStore(),
        api: FakeApi(),
        pickPem: () async => null,
        openBankPage: (url) async => true,
      );
    });
    tearDown(() => db.close());

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Services(
        services: services,
        child: MaterialApp(home: Scaffold(body: HomeScreen(onShowAll: () {}, onShowAnalysis: () {}))),
      ));
      await settle(tester);
    }

    testWidgets('«Nascondi importi»: sfoca gli importi e resta salvato', (tester) async {
      await tester.runAsync(() async {
        final acc = await addAccount(db);
        await storeTransactions(db, acc, [tx('12', ref: 'a', name: 'Bar Centrale')], '2026-01-01');
      });
      await pumpHome(tester);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.text('BC'), findsWidgets); // avatar con le iniziali

      await tester.tap(find.byKey(const Key('hide-amounts')));
      await settle(tester);
      expect(services.hideAmounts.value, isTrue);
      expect(find.byType(ImageFiltered), findsWidgets);

      // Alla riapertura: letto dal database.
      final reopened = AppServices(
        db: db,
        secrets: MemorySecretStore(),
        api: FakeApi(),
        pickPem: () async => null,
        openBankPage: (url) async => true,
      );
      await tester.runAsync(reopened.loadPreferences);
      expect(reopened.hideAmounts.value, isTrue);
    });

    testWidgets('senza movimenti: schermate vuote curate', (tester) async {
      await pumpHome(tester);
      expect(find.text('Ancora nessun movimento'), findsOneWidget);
      expect(find.text('Nessuna spesa questo mese'), findsOneWidget);
    });
  });
}

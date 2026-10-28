// Richieste dell'utente del 28/10/2026: categorie ordinate per uso, dati dal
// 1 agosto 2026, giroconti nei conteggi, Flussi per categoria, ordine dei movimenti.
import 'package:bankingmobile/core/config.dart';
import 'package:bankingmobile/core/periods.dart';
import 'package:bankingmobile/data/database.dart';
import 'package:bankingmobile/domain/cashflow.dart';
import 'package:bankingmobile/domain/transactions.dart';
import 'package:bankingmobile/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';
import 'to_categorize_test.dart' show TxApi;

/// Banca finta che ricorda da che data le sono stati chiesti i movimenti.
class RecordingApi extends TxApi {
  String? askedFrom;

  @override
  Future<List<Map<String, dynamic>>> getTransactions(String uid, String dateFrom,
      {String? dateTo, String strategy = 'default'}) async {
    askedFrom = dateFrom;
    return txs;
  }
}

void main() {
  late Database db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  Future<int> categoryId(String name) async =>
      await scalar(db, 'SELECT id FROM categories WHERE name = ?', [name]) as int;

  test('menu delle categorie: dalla più usata', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [
      for (var i = 0; i < 3; i++) tx('5', ref: 's$i', name: 'Uno', day: '2026-10-0${i + 1}'),
      tx('9', ref: 'r', name: 'Due', day: '2026-10-05'),
    ], '2026-08-01');
    final salute = await categoryId('Salute'), bar = await categoryId('Ristoranti e bar');
    for (var i = 0; i < 3; i++) {
      await setCategory(db, '$acc|e|s$i', salute);
    }
    await setCategory(db, '$acc|e|r', bar);

    final names = [for (final c in await allCategories(db)) c['name']];
    expect(names.take(2), ['Salute', 'Ristoranti e bar']);
    // Le mai usate dopo, in ordine alfabetico.
    final unused = names.skip(2).toList();
    expect(unused, [...unused]..sort());
  });

  group('dati dal 1 agosto 2026', () {
    test('i movimenti precedenti vengono cancellati all\'avvio', () async {
      final acc = await addAccount(db);
      await storeTransactions(db, acc, [
        tx('10', ref: 'vecchio', day: '2026-07-31'),
        tx('20', ref: 'nuovo', day: AppConfig.dataStart),
      ], '2026-01-01');
      await initDb(db);
      expect([for (final r in await db.query('transactions')) r['id']], ['$acc|e|nuovo']);
    });

    test('la sincronizzazione non chiede né salva movimenti precedenti', () async {
      final acc = await addAccount(db);
      final api = RecordingApi()
        ..txs = [
          tx('10', ref: 'vecchio', day: '2026-06-15'), // banche che ignorano date_from
          tx('20', ref: 'nuovo', day: '2026-09-15'),
        ];
      final account = (await db.query('accounts', where: 'id = ?', whereArgs: [acc])).single;
      await syncAccount(db, api, account, backfill: true, now: DateTime(2026, 10, 26));
      expect(api.askedFrom, AppConfig.dataStart); // lo storico completo partirebbe dal 2024
      expect([for (final r in await db.query('transactions')) r['id']], ['$acc|e|nuovo']);
    });

    test('grafici e confronti non vanno prima della data di partenza', () {
      expect(monthsFromStart(DateTime.utc(2026, 10)), 3); // agosto, settembre, ottobre
      expect(monthsFromStart(DateTime.utc(2026, 8)), 1);
      expect(monthsFromStart(DateTime.utc(2028, 1)), 12);
      expect(comparisonAvailable(periodFor(PeriodKind.month, DateTime.utc(2026, 8, 10))), isFalse);
      expect(comparisonAvailable(periodFor(PeriodKind.month, DateTime.utc(2026, 9, 10))), isTrue);
    });
  });

  test('Flussi: uscite ed entrate per categoria; giroconti a parte, fuori dai totali', () async {
    final acc = await addAccount(db, uid: 'u1', iban: 'IT00A');
    await addAccount(db, bankKey: 'theta', uid: 'u2', iban: 'IT00B');
    await storeTransactions(db, acc, [
      tx('30', ref: 'a', name: 'Esselunga', day: '2026-10-02'),
      tx('10', ref: 'b', name: 'Esselunga', day: '2026-10-03'),
      tx('60', ref: 'g', name: 'Io', iban: 'IT00B', day: '2026-10-04'), // giroconto
      tx('100', indicator: 'CRDT', ref: 'c', name: 'Sconosciuto Srl', day: '2026-10-05'),
    ], '2026-08-01');
    await setCategory(db, '$acc|e|a', await categoryId('Spesa alimentare'));
    await setCategory(db, '$acc|e|b', await categoryId('Spesa alimentare'));
    await setCategory(db, '$acc|e|g', await categoryId('Giroconti'));

    final flows = await byCategory(db, DateTime.utc(2026, 10), DateTime.utc(2026, 11));
    expect([for (final c in flows.expense) (c.name, c.total, c.n, c.pct.round())],
        [('Spesa alimentare', 4000, 2, 100)]);
    expect([for (final c in flows.income) (c.name, c.total)], [('Senza categoria', 10000)]);
    expect((await totals(db, DateTime.utc(2026, 10), DateTime.utc(2026, 11))).expense, 4000);
    // Visibili a parte: «Spostato tra i tuoi conti».
    final moved = await movedBetweenAccounts(db, DateTime.utc(2026, 10), DateTime.utc(2026, 11));
    expect((moved.cents, moved.n), (6000, 1));
  });

  test('Movimenti: dal giorno più recente; nello stesso giorno prima gli ultimi scaricati', () async {
    final acc = await addAccount(db);
    await storeTransactions(db, acc, [
      tx('1', ref: 'mattina', day: '2026-10-05'),
      tx('2', ref: 'ieri', day: '2026-10-04'),
    ], '2026-08-01');
    await storeTransactions(db, acc, [tx('3', ref: 'sera', day: '2026-10-05')], '2026-10-05');
    final page = await loadTransactions(db, const TxFilter());
    expect([for (final (_, items, _) in page.days) for (final t in items) t['id']],
        ['$acc|e|sera', '$acc|e|mattina', '$acc|e|ieri']);
  });
}

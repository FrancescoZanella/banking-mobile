import 'package:flutter/widgets.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../bank/bank_service.dart';
import '../bank/enable_banking.dart';
import '../data/database.dart';
import '../data/secure_store.dart';

/// File .pem scelto dall'utente: nome del file e contenuto.
typedef PickedFile = ({String name, String content});

/// Dipendenze dell'app, iniettabili nei test.
class AppServices {
  AppServices({
    required this.db,
    required this.secrets,
    required this.api,
    required this.pickPem,
    required this.openBankPage,
    this.isDeviceRooted = _notRooted,
    Future<void> Function(Database db)? afterSync,
    this.dismissNotification = _noDismiss,
  })  : sync = SyncRunner(db, api, afterSync: afterSync) {
    bank = BankService(db, api, sync);
  }

  final Database db;
  final SecretStore secrets;
  final EnableBankingApi api;
  final SyncRunner sync;
  late final BankService bank;

  /// Selettore del file .pem (selettore di sistema sul telefono).
  final Future<PickedFile?> Function() pickPem;

  /// Apre la pagina di login della banca (scheda sicura del browser).
  final Future<bool> Function(Uri url) openBankPage;

  /// Telefono con root: solo un avviso dopo lo sblocco.
  final Future<bool> Function() isDeviceRooted;

  /// Toglie la notifica di un movimento appena categorizzato.
  final Future<void> Function(String txId) dismissNotification;

  /// «Nascondi importi»: sfoca gli importi in tutta l'app. Resta attivo tra
  /// un'apertura e l'altra (impostazione nel database cifrato).
  final hideAmounts = ValueNotifier<bool>(false);

  static const _hideAmountsKey = 'hide_amounts';

  Future<void> loadPreferences() async =>
      hideAmounts.value = await getSetting(db, _hideAmountsKey) == '1';

  Future<void> setHideAmounts(bool hidden) async {
    hideAmounts.value = hidden;
    await setSetting(db, _hideAmountsKey, hidden ? '1' : '0');
  }
}

Future<void> _noDismiss(String _) async {}

Future<bool> _notRooted() async => false;

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}

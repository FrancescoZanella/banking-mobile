import 'package:flutter/widgets.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../bank/enable_banking.dart';
import '../data/secure_store.dart';

/// Pagina .pem scelta dall'utente: nome del file e contenuto.
typedef PickedFile = ({String name, String content});

/// Dipendenze dell'app, iniettabili nei test.
class AppServices {
  AppServices({required this.db, required this.secrets, required this.api, required this.pickPem});

  final Database db;
  final SecretStore secrets;
  final EnableBankingClient api;

  /// Selettore del file .pem (selettore di sistema sul telefono).
  final Future<PickedFile?> Function() pickPem;
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}

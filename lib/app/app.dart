import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../bank/bank_service.dart';
import '../security/app_lock.dart';
import '../ui/lock_screen.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import 'services.dart';

class BankingApp extends StatefulWidget {
  const BankingApp({super.key, required this.services, required this.lock, this.links});

  final AppServices services;
  final AppLock lock;

  /// Deep link in arrivo (ritorno dalla banca). Nei test uno stream finto.
  final Stream<Uri>? links;

  @override
  State<BankingApp> createState() => _BankingAppState();
}

class _BankingAppState extends State<BankingApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Timer? _idleTimer;
  StreamSubscription<Uri>? _links;
  bool _wasLocked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Controllo periodico dell'inattività mentre l'app è in primo piano.
    _idleTimer = Timer.periodic(const Duration(seconds: 30), (_) => widget.lock.checkIdle());
    _links = widget.links?.listen(_onLink);
    widget.lock.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _links?.cancel();
    widget.lock.removeListener(_onLockChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al ritorno nell'app: se è passata mezz'ora dall'ultima attività, si blocca.
    if (state == AppLifecycleState.resumed) widget.lock.checkIdle();
  }

  void _onLockChanged() {
    final locked = widget.lock.locked;
    if (_wasLocked && !locked) {
      // Aggiornamento automatico all'apertura, solo per i conti "scaduti" (>12h).
      unawaited(widget.services.sync.start(onlyDue: true));
    }
    _wasLocked = locked;
  }

  /// Ritorno dalla banca: lo `state` monouso decide se è valido, a prescindere
  /// dal blocco (non mostra dati); l'esito si vede dopo lo sblocco.
  Future<void> _onLink(Uri uri) async {
    final Flash flash = await widget.services.bank.handleCallback(uri);
    _messenger.currentState?.showSnackBar(SnackBar(
      content: Text(flash.text),
      backgroundColor: flash.ok ? AppColors.surface3 : const Color(0xFF5A2020),
      duration: const Duration(seconds: 10),
    ));
    widget.services.sync.notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      services: widget.services,
      child: MaterialApp(
        title: 'Banking Dashboard',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Testi di sistema (selettore date, menu) in italiano.
        locale: const Locale('it'),
        supportedLocales: const [Locale('it')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        scaffoldMessengerKey: _messenger,
        home: ListenableBuilder(
          listenable: widget.lock,
          builder: (context, _) => widget.lock.locked
              // Bloccata: nessuna schermata con dati è nemmeno costruita.
              ? LockScreen(lock: widget.lock)
              : Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => widget.lock.touch(),
                  child: const Shell(),
                ),
        ),
      ),
    );
  }
}

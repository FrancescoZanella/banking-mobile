import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../bank/bank_service.dart';
import '../security/app_lock.dart';
import '../ui/lock_screen.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'services.dart';

class BankingApp extends StatefulWidget {
  const BankingApp({super.key, required this.services, required this.lock, this.links, this.openTransactions});

  final AppServices services;
  final AppLock lock;

  /// Deep link in arrivo (ritorno dalla banca). Nei test uno stream finto.
  final Stream<Uri>? links;

  /// Movimenti da aprire (tocco su una notifica «da categorizzare»).
  final Stream<String>? openTransactions;

  @override
  State<BankingApp> createState() => _BankingAppState();
}

class _BankingAppState extends State<BankingApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _opens;
  String? _pendingTx;
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
    _opens = widget.openTransactions?.listen((txId) {
      _pendingTx = txId;
      _openPendingTransaction();
    });
    widget.lock.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _links?.cancel();
    _opens?.cancel();
    widget.lock.removeListener(_onLockChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al ritorno nell'app: se è passata mezz'ora dall'ultima attività, si blocca.
    // Le pagine si ricaricano: la sync delle 7/14/23 o un pulsante della
    // notifica possono aver cambiato i dati da un'altra connessione.
    if (state == AppLifecycleState.resumed) {
      widget.lock.checkIdle();
      widget.services.sync.notifyChanged();
    }
  }

  void _onLockChanged() {
    final locked = widget.lock.locked;
    if (_wasLocked && !locked) {
      // Niente sync all'apertura: solo alle 7, 14 e 23 (sync/schedule.dart).
      unawaited(_warnIfRooted());
      if (_pendingFlash case final flash?) {
        _pendingFlash = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showFlash(flash));
      }
      // Dopo lo sblocco, il movimento della notifica toccata.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingTransaction());
    }
    _wasLocked = locked;
  }

  /// Apre il dettaglio del movimento atteso, ma solo ad app sbloccata.
  void _openPendingTransaction() {
    final txId = _pendingTx, context = _navigator.currentContext;
    if (txId == null || context == null || widget.lock.locked) return;
    _pendingTx = null;
    unawaited(showTransactionDetail(context, txId).then((changed) {
      if (changed) widget.services.sync.notifyChanged();
    }));
  }

  bool _rootWarned = false;

  /// Una volta per avvio: con il root altre app possono leggere i dati di questa.
  Future<void> _warnIfRooted() async {
    if (_rootWarned || !await widget.services.isDeviceRooted()) return;
    _rootWarned = true;
    _messenger.currentState?.showSnackBar(const SnackBar(
      content: Text('Questo telefono sembra avere i permessi di root: altre app potrebbero '
          'leggere i dati di Banking Dashboard.'),
      backgroundColor: Color(0xFF5A2020),
      duration: Duration(seconds: 10),
    ));
  }

  /// Ritorno dalla banca: lo `state` monouso decide se è valido, a prescindere
  /// dal blocco (non mostra dati); l'esito si vede dopo lo sblocco.
  Future<void> _onLink(Uri uri) async {
    Flash flash;
    try {
      flash = await widget.services.bank.handleCallback(uri);
    } catch (e) {
      // Mai un errore silenzioso: la banca non è stata salvata e va detto.
      flash = Flash('Collegamento non completato: ${describeError(e)}. Riprova.', ok: false);
    }
    widget.services.sync.notifyChanged();
    if (widget.lock.locked) {
      // Ad app appena riavviata: il messaggio si vede dopo lo sblocco.
      _pendingFlash = flash;
    } else {
      _showFlash(flash);
    }
  }

  Flash? _pendingFlash;

  void _showFlash(Flash flash) => _messenger.currentState?.showSnackBar(SnackBar(
        content: Text(flash.text),
        backgroundColor: flash.ok ? AppColors.surface3 : const Color(0xFF5A2020),
        duration: const Duration(seconds: 10),
      ));

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
        navigatorKey: _navigator,
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

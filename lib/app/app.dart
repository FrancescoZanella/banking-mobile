import 'dart:async';

import 'package:flutter/material.dart';

import '../security/app_lock.dart';
import '../ui/lock_screen.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import 'services.dart';

class BankingApp extends StatefulWidget {
  const BankingApp({super.key, required this.services, required this.lock});

  final AppServices services;
  final AppLock lock;

  @override
  State<BankingApp> createState() => _BankingAppState();
}

class _BankingAppState extends State<BankingApp> with WidgetsBindingObserver {
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Controllo periodico dell'inattività mentre l'app è in primo piano.
    _idleTimer = Timer.periodic(const Duration(seconds: 30), (_) => widget.lock.checkIdle());
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al ritorno nell'app: se è passata mezz'ora dall'ultima attività, si blocca.
    if (state == AppLifecycleState.resumed) widget.lock.checkIdle();
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      services: widget.services,
      child: MaterialApp(
        title: 'Banking Dashboard',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
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

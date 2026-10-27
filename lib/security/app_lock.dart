import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../core/config.dart';

enum AuthOutcome { success, failed, notConfigured }

/// Verifica l'identità con impronta/volto o con PIN/sequenza del telefono.
abstract class Authenticator {
  Future<AuthOutcome> authenticate();
}

class DeviceAuthenticator implements Authenticator {
  final _auth = LocalAuthentication();

  @override
  Future<AuthOutcome> authenticate() async {
    // Senza un blocco schermo sul telefono non c'è nulla che protegga l'app.
    if (!await _auth.isDeviceSupported()) return AuthOutcome.notConfigured;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Sblocca Banking Dashboard',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } catch (_) {
      return AuthOutcome.failed;
    }
  }
}

/// Stato di blocco dell'app: bloccata all'avvio, si sblocca con [unlock],
/// si riblocca dopo 30 minuti senza interazioni (come il logout del web).
class AppLock extends ChangeNotifier {
  AppLock(this._authenticator, {DateTime Function()? clock, Duration idle = AppConfig.idleLock})
      : _clock = clock ?? DateTime.now,
        _idle = idle;

  final Authenticator _authenticator;
  final DateTime Function() _clock;
  final Duration _idle;

  bool _locked = true;
  bool _busy = false;
  AuthOutcome? lastOutcome;
  DateTime? _lastActivity;

  bool get locked => _locked;
  bool get busy => _busy;

  Future<void> unlock() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    lastOutcome = await _authenticator.authenticate();
    _busy = false;
    if (lastOutcome == AuthOutcome.success) {
      _locked = false;
      _lastActivity = _clock();
    }
    notifyListeners();
  }

  /// Ogni tocco sullo schermo conta come attività.
  void touch() {
    if (!_locked) _lastActivity = _clock();
  }

  /// Da chiamare al ritorno nell'app e periodicamente: blocca se inattiva da troppo.
  void checkIdle() {
    final last = _lastActivity;
    if (_locked || last == null) return;
    if (_clock().difference(last) >= _idle) lock();
  }

  void lock() {
    if (_locked) return;
    _locked = true;
    _lastActivity = null;
    lastOutcome = null;
    notifyListeners();
  }
}

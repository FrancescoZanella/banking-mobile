import 'package:flutter/material.dart';

import '../security/app_lock.dart';
import 'theme.dart';

/// Schermata di sblocco: stesso schema della pagina di accesso del web,
/// con impronta/volto o PIN del telefono al posto della password.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});

  final AppLock lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Chiede subito l'impronta all'apertura.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.lock.unlock());
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.lock.lastOutcome;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/icon.png', width: 28, height: 28),
                ),
                const SizedBox(width: 10),
                const Text('Banking Dashboard', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ]),
              const Spacer(),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/icon.png'),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Sblocca la dashboard',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text('Usa impronta, volto o il PIN del telefono.',
                  style: TextStyle(color: AppColors.muted)),
              if (outcome == AuthOutcome.failed) ...[
                const SizedBox(height: 16),
                _Notice('Sblocco non riuscito. Riprova.', AppColors.neg),
              ],
              if (outcome == AuthOutcome.notConfigured) ...[
                const SizedBox(height: 16),
                _Notice(
                    'Il telefono non ha un blocco schermo. Imposta PIN, sequenza o impronta '
                    'nelle impostazioni di Android: senza, la dashboard non si apre.',
                    AppColors.warn),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('unlock'),
                onPressed: widget.lock.busy ? null : widget.lock.unlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Sblocca'),
              ),
              const Spacer(),
              const Row(children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
                SizedBox(width: 6),
                Text('Database cifrato AES-256 · solo su questo telefono',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
        child: Text(text),
      );
}

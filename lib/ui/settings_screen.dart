import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/secure_store.dart';
import 'theme.dart';

/// Impostazioni: credenziali dell'applicazione Enable Banking del telefono.
/// APP_ID e chiave privata finiscono solo nel Keystore di Android.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _appId = TextEditingController();
  String? _pem;
  String? _pemName;
  bool? _configured;
  String? _savedAppId;
  bool _showAppId = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final creds = await readCredentials(Services.of(context).secrets);
    if (!mounted) return;
    setState(() {
      _configured = creds != null;
      // L'APP_ID salvato non torna nel campo: se ne mostrano solo le ultime cifre.
      _savedAppId = creds?.appId;
    });
  }

  Future<void> _pick() async {
    final file = await Services.of(context).pickPem();
    if (file == null) return;
    setState(() {
      _pem = file.content;
      _pemName = file.name;
      _error = null;
    });
  }

  Future<void> _save() async {
    final services = Services.of(context);
    final pem = _pem;
    final error = pem == null ? 'Scegli il file .pem della chiave privata.' : validateCredentials(_appId.text, pem);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await saveCredentials(services.secrets, _appId.text, pem!);
    if (!mounted) return;
    setState(() {
      _savedAppId = _appId.text.trim();
      _appId.clear();
      _showAppId = false;
      _pem = null;
      _pemName = null;
      _configured = true;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Credenziali salvate nel Keystore. Ora cancella il file .pem dalla cartella '
          'Download: non serve più.'),
      duration: Duration(seconds: 8),
    ));
  }

  Future<void> _remove() async {
    final services = Services.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovere le credenziali?'),
        content: const Text('Senza APP_ID e chiave privata non potrai sincronizzare né collegare banche, '
            'finché non le reimporti. I dati già scaricati restano.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok != true) return;
    await deleteCredentials(services.secrets);
    if (mounted) {
      setState(() {
        _configured = false;
        _savedAppId = null;
      });
    }
  }

  @override
  void dispose() {
    _appId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Applicazione Enable Banking', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  _configured == true
                      ? 'Configurata. Puoi sostituire APP_ID e chiave privata, oppure rimuoverli.'
                      : "Inserisci l'APP_ID dell'applicazione creata per il telefono e importa la sua chiave privata (.pem).",
                  style: const TextStyle(color: AppColors.muted),
                ),
                if (_savedAppId case final saved?) ...[
                  const SizedBox(height: 12),
                  Text('APP_ID salvato: ${maskAppId(saved)}',
                      key: const Key('saved-app-id'), style: const TextStyle(color: AppColors.muted)),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const Key('app-id'),
                  controller: _appId,
                  obscureText: !_showAppId,
                  decoration: InputDecoration(
                    hintText: _configured == true ? 'Nuovo APP_ID' : 'APP_ID',
                    suffixIcon: IconButton(
                      tooltip: _showAppId ? 'Nascondi' : 'Mostra',
                      icon: Icon(_showAppId ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showAppId = !_showAppId),
                    ),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('pick-pem'),
                  onPressed: _pick,
                  icon: const Icon(Icons.key_outlined),
                  label: Text(_pemName ?? 'Scegli il file .pem'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.neg)),
                ],
                const SizedBox(height: 16),
                FilledButton(key: const Key('save-credentials'), onPressed: _save, child: const Text('Salva')),
                if (_configured == true)
                  TextButton(onPressed: _remove, child: const Text('Rimuovi credenziali')),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// "12345678-…-456789abcdef" → "•••• cdef": basta a riconoscerlo, non a copiarlo.
String maskAppId(String appId) => '•••• ${appId.length > 4 ? appId.substring(appId.length - 4) : appId}';

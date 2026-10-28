# Sviluppo

## Test

```
flutter analyze
flutter test
flutter test integration_test -d <id-telefono>
```

- `test/`: logica (SQLite in memoria con `sqflite_common_ffi`) e schermate (widget test).
- Nei widget test usa `settle(tester)` di `test/support.dart` invece di `pumpAndSettle`: le pagine
  leggono il DB con I/O reale (fuori dal tempo simulato) e intanto mostrano un indicatore che non si
  ferma mai.
- `integration_test/`: cifratura del DB sul telefono. **Alla fine il test disinstalla l'app**: dopo,
  va reinstallata e ricollegata.
- Ogni test del web ha il suo corrispondente: aggiorna [parita-test.md](parita-test.md) quando ne aggiungi.

## Versioni fissate

Flutter è fermo alla 3.32.4; alcuni pacchetti più recenti richiedono Flutter ≥3.35/3.38:

| Pacchetto | Versione | Perché |
|---|---|---|
| `fl_chart` | 1.0.0 | la 1.1 usa `Matrix4.translateByDouble` |
| `workmanager_platform_interface` / `workmanager_android` | 0.9.3 / 0.9.2 (override) | combinazione coerente con Flutter 3.32 |

Prima di aggiornare Flutter, togli questi vincoli e rilancia tutti i test.

## Build

- Debug: `flutter build apk --debug` (APK grande, ~240 MB, con tutte le architetture).
- Release: vedi [Installazione](installazione.md). R8 usa `android/app/proguard-rules.pro`
  (classi di SQLCipher e delle notifiche da non rimuovere).

## Telefono di prova

- Xiaomi con HyperOS 2: confermare "Installa" sul telefono a ogni installazione via adb.
  "Spazio insufficiente" compare come `INSTALL_FAILED_USER_RESTRICTED`.

## Convenzioni

- Importi sempre in **centesimi interi**, mai `double`.
- Date di calendario come `DateTime` UTC a mezzanotte (`core/dates.dart`).
- Testi dell'interfaccia in italiano.
- Nessun log con dati bancari o segreti, né in debug né in release.
- Commit e push solo su richiesta.

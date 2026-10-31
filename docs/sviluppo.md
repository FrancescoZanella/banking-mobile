# Sviluppo

## Struttura della repo

| Percorso | Contenuto |
|---|---|
| `lib/` | codice dell'app, vedi [Architettura](architettura.md) |
| `test/` | test di logica e delle schermate, uno per area (`bank`, `transactions`, `analysis_flows`, `cashflow`, `budget_categories`, `security`, `to_categorize`, `return_links`, `preferences`, `investments`, `polish`, `interaction`, …): 112 test |
| `integration_test/` | test da eseguire sul telefono |
| `android/` | progetto Android: manifest, risorse, `MainActivity.kt`, firma e R8 (`app/build.gradle.kts`, `app/proguard-rules.pro`) |
| `assets/icon.png` | logo mostrato nella schermata di sblocco |
| `docs/` | documentazione |
| `.github/` | controlli automatici (`workflows/ci.yml`), modelli di issue e pull request |

Non sono nella repo (sono in `.gitignore` o generati): `build/`, `.dart_tool/`, file dell'IDE,
`local.properties`.

## Cosa non va mai su GitHub

- Chiavi e segreti: `*.pem`, `*.jks`, `*.keystore`, `key.properties`, `.env` (già in `.gitignore`).
  La chiave di firma sta in `%LOCALAPPDATA%\BankingMobile\signing`, la chiave di Enable Banking solo
  nel Keystore del telefono.
- Database e dati veri: `*.db`, CSV esportati, screenshot con importi.
- Nei test solo dati inventati (IBAN come `IT11`, `IT02`; chiave `.pem` finta con il solo testo
  `CHIAVE-DI-PROVA-NON-VALIDA`).

Controllo prima di un push (nessuna riga deve uscire; su GitHub gli stessi controlli bloccano la PR):

```
git log --all --name-only --pretty=format: | sort -u | grep -iE "\.pem$|\.jks$|\.keystore$|key\.properties|\.env$|\.db$"
git grep -nE "BEGIN [A-Z ]*PRIVATE KEY" -- ':!test' ':!docs'
```

## Test

```
flutter analyze
flutter test --timeout 60s
flutter test integration_test -d <id-telefono>
```

I primi due girano anche su GitHub a ogni push e a ogni pull request (`.github/workflows/ci.yml`),
insieme alla build `flutter build apk --debug` e ai controlli di «Cosa non va mai su GitHub». Il test
sul telefono no: va lanciato a mano.

`--timeout 60s` fa fallire subito un test bloccato invece di aspettare 10 minuti. Nei widget test non
aspettare con `tester.runAsync` una sincronizzazione avviata dall'app: resterebbe bloccata (usa
`settle`, oppure scegli un caso che non sincronizza).

- `test/`: logica (SQLite in memoria con `sqflite_common_ffi`) e schermate (widget test).
- Nei widget test usa `settle(tester)` di `test/support.dart` invece di `pumpAndSettle`: le pagine
  leggono il DB con I/O reale (fuori dal tempo simulato) e intanto mostrano un indicatore che non si
  ferma mai.
- `integration_test/`: cifratura del DB sul telefono. **Alla fine il test disinstalla l'app**: dopo,
  va reinstallata e ricollegata.

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
  "Spazio insufficiente" compare come `INSTALL_FAILED_USER_RESTRICTED`; se la conferma scade, installa
  copiando l'APK in *Download* (vedi [Installazione](installazione.md#4-installazione-sul-telefono)).

## Convenzioni

- Importi sempre in **centesimi interi**, mai `double`.
- Date di calendario come `DateTime` UTC a mezzanotte (`core/dates.dart`).
- Testi dell'interfaccia in italiano.
- Il codice è formattato a mano (righe fino a 120 caratteri): **non lanciare `dart format`** sui file
  esistenti, con Dart 3.8 riscriverebbe interi file nello stile nuovo.
- Ogni cambio di categoria dall'interfaccia passa da `applyCategory` (`ui/categorize_ui.dart`), così
  vibrazione, notifiche e «Annulla» restano coerenti.
- I testi con importi usano `Amount` e i grafici `Sensitive` (`ui/polish.dart`), altrimenti «Nascondi
  importi» non li sfoca.
- Nessun log con dati bancari o segreti, né in debug né in release.

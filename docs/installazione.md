# Installazione

Questa guida serve per la prima installazione, per gli aggiornamenti e per rimettere in piedi la
build su un PC nuovo.

## 1. Ambiente sul PC

- **Flutter 3.32.4** in `C:\sdk\flutter` (le versioni dei pacchetti sono fissate per questa versione,
  vedi [Sviluppo](sviluppo.md)).
- **Android Studio** (per il JDK in `jbr\` e l'Android SDK), con SDK 36 e NDK 27.0.12077973.
- Un'esclusione di Windows Defender per `banking-mobile\build`: senza, Gradle si blocca sui file.

Controllo: `flutter doctor` senza errori per Android.

## 2. Chiave di firma (una volta sola)

L'APK di release è firmato con una chiave **tua**, che sta fuori dalla repo:

```
%LOCALAPPDATA%\BankingMobile\signing\release.jks
%LOCALAPPDATA%\BankingMobile\signing\key.properties   (password e alias)
```

> **Fai subito un backup di entrambi i file nel password manager.** Android accetta un aggiornamento
> solo se è firmato con la stessa chiave: senza, l'unica strada è disinstallare l'app (perdendo i dati
> sul telefono) e ricollegare le banche.

Per usare una chiave in un altro percorso, imposta `BANKING_MOBILE_KEY_PROPERTIES` con il percorso del
suo `key.properties`. Senza chiave la build di release si ferma con un errore: non viene mai firmata con
la chiave di debug.

Se la chiave cambia, l'impronta SHA-256 del nuovo certificato va aggiunta in
`relay/user-site/.well-known/assetlinks.json` e pubblicata nella repo `francescozanella.github.io`
(vedi sotto), altrimenti il ritorno dalla banca passa dalla pagina relay invece di aprire l'app.
L'impronta si legge con:

```
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

## 3. Build di release

```
flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64
```

- `--obfuscate` e R8 rendono il codice illeggibile; i simboli per leggere eventuali crash restano in
  `build/symbols` (fuori dalla repo).
- `android-arm64` basta per i telefoni moderni e riduce l'APK a ~40 MB.

## 4. Installazione sul telefono

Con il debug USB attivo:

```
adb push build\app\outputs\flutter-apk\app-release.apk /data/local/tmp/bankingmobile.apk
adb shell pm install -r /data/local/tmp/bankingmobile.apk
adb shell rm /data/local/tmp/bankingmobile.apk
```

Sui telefoni Xiaomi (HyperOS) va confermato "Installa" sul telefono entro pochi secondi. Copiare prima
il file sul telefono fa comparire subito la richiesta (con `adb install` diretto, un APK grande può
farla scadere). Da Git Bash, anteporre `MSYS_NO_PATHCONV=1` ai comandi `adb` con percorsi del telefono.

**Passaggio da debug a release:** le due build hanno firme diverse, quindi la prima volta l'app di
debug va disinstallata. I dati sul telefono si perdono: al primo avvio vanno reinseriti APP_ID e `.pem`
e ricollegate le banche.

## 5. Primo avvio

1. **Sblocco:** serve un blocco schermo (impronta, volto o PIN) impostato sul telefono.
2. **Impostazioni** (Altro → Impostazioni): inserisci l'APP_ID dell'applicazione Enable Banking del
   telefono e scegli il suo file `.pem`. Vengono salvati nel Keystore; poi **cancella il `.pem` dalla
   cartella Download**.
3. **Conti → Collega banca:** prima collega il conto alla tua app nel Control Panel di Enable Banking,
   poi scegli la banca e fai il login. Il recupero dello storico parte da solo.
4. Consenti le **notifiche**, se Android le chiede: servono per l'avviso di consenso in scadenza.

## 6. Pagine pubbliche usate dall'app

| Repo (GitHub Pages) | Contenuto | Perché |
|---|---|---|
| `Bankrelay` → `app/index.html` | pagina di ritorno dalla banca | indirizzo di redirect registrato su Enable Banking; rimanda all'app |
| `francescozanella.github.io` → `.well-known/assetlinks.json` | impronte dei certificati dell'app | App Link verificato: il ritorno dalla banca apre direttamente l'app |

Nessuna delle due contiene dati personali. La sorgente di `assetlinks.json` è in `relay/user-site/`.

## 7. Aggiornare l'app

1. `git pull`, poi `flutter test` (devono essere tutti verdi).
2. Build di release (punto 3) con **la stessa chiave**.
3. Installazione (punto 4): con la stessa firma i dati restano.

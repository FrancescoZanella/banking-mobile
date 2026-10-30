# Installazione

Questa guida serve per **compilare** l'app, per usare una **tua pagina di ritorno**, per pubblicare una
**Release** e per gli **aggiornamenti**. Il primo utilizzo (Enable Banking, `.pem`, APP_ID, banche) è
nel [README](../README.md).

## 1. Ambiente sul PC

- **Flutter 3.32.4** (le versioni dei pacchetti sono fissate per questa versione, vedi
  [Sviluppo](sviluppo.md#versioni-fissate)).
- **Android Studio**, per il JDK (`jbr\`) e l'Android SDK, con **SDK 36** e **NDK 27.0.12077973**.
- Su Windows: un'esclusione di Windows Defender per la cartella `build` del progetto; senza, Gradle si
  blocca sui file.

Controllo: `flutter doctor` senza errori per Android.

## 2. Chiave di firma (una volta sola)

L'APK di release è firmato con una chiave **tua**, che sta fuori dalla repo. Di default Gradle la cerca
in:

```
%LOCALAPPDATA%\BankingMobile\signing\release.jks
%LOCALAPPDATA%\BankingMobile\signing\key.properties
```

Per crearla (dal JDK di Android Studio):

```bash
keytool -genkeypair -v -keystore release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias release
```

`key.properties` contiene:

```
storePassword=<password del keystore>
keyPassword=<password della chiave>
keyAlias=release
storeFile=<percorso completo di release.jks>
```

Nel percorso usa le barre `/` (oppure `\\`): una `\` singola in un file `.properties` viene ignorata.

> **Fai subito un backup di entrambi i file nel password manager.** Android accetta un aggiornamento
> solo se è firmato con la stessa chiave: senza, l'unica strada è disinstallare l'app (perdendo i dati
> sul telefono) e ricollegare le banche.

Per una chiave in un altro percorso imposta `BANKING_MOBILE_KEY_PROPERTIES` con il percorso del suo
`key.properties`. Senza chiave la build di release si ferma con un errore: non viene mai firmata con la
chiave di debug.

## 3. Pagina di ritorno propria (facoltativo)

L'APK delle Release usa la pagina di ritorno già scritta nel codice. Per usarne una tua (per esempio
`https://<utente>.github.io/banking-relay/app/`), prima della build cambia questi punti:

| Dove | Cosa |
|---|---|
| [`lib/core/config.dart`](../lib/core/config.dart) | `AppConfig.redirectUri`: il tuo indirizzo, con la `/` finale. Deve essere **identico** al Redirect URL registrato su Enable Banking |
| [`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) | nell'`intent-filter` con `autoVerify`: `android:host` (`<utente>.github.io`) e `android:pathPrefix` (`/banking-relay/app`) |
| [`relay/app/index.html`](../relay/app/index.html) | solo se cambi il nome del pacchetto: `package=…` nello script, poi ricalcola l'hash della CSP (sotto) |

Il nome del pacchetto (`applicationId` e `namespace` in
[`android/app/build.gradle.kts`](../android/app/build.gradle.kts)) può restare quello della repo. Se lo
cambi, cambialo anche nella pagina relay e in `assetlinks.json`.

**Hash della CSP della pagina relay.** La pagina accetta solo lo script con l'hash scritto nella sua
`Content-Security-Policy`. Se modifichi lo script, ricalcolalo e sostituiscilo in `script-src
'sha256-…'`:

```bash
python -c "import re,hashlib,base64;s=open('relay/app/index.html',encoding='utf-8').read();print(base64.b64encode(hashlib.sha256(re.search(r'<script>(.*?)</script>',s,re.S).group(1).encode()).digest()).decode())"
```

Poi pubblica le pagine come spiegato nel [README](../README.md#passo-2--pubblica-le-pagine-pubbliche)
e registra il nuovo indirizzo tra i Redirect URL della tua applicazione Enable Banking.

## App Link verificato

Senza App Link il ritorno dalla banca funziona lo stesso: la banca apre la pagina relay, che rimanda
all'app con `bankingmobile://callback`. Con l'App Link verificato Android apre **direttamente** l'app,
senza passare dal browser.

1. Leggi l'impronta SHA-256 del certificato con cui firmi:
   ```bash
   apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
   ```
2. Crea `.well-known/assetlinks.json` con il nome del pacchetto e l'impronta (il modello è in
   [`relay/user-site/.well-known/assetlinks.json`](../relay/user-site/.well-known/assetlinks.json):
   sostituisci `package_name` e `sha256_cert_fingerprints`).
3. Pubblicalo nella **repository del sito utente** di GitHub Pages, quella chiamata
   `<utente>.github.io`, insieme a un file vuoto `.nojekyll` (altrimenti GitHub non pubblica le
   cartelle che iniziano con il punto). Deve rispondere a
   `https://<utente>.github.io/.well-known/assetlinks.json`.
4. Installa l'app e controlla sul telefono:
   ```bash
   adb shell pm get-app-links <nome del pacchetto>
   ```
   Il dominio deve risultare `verified`.

Se cambi la chiave di firma, aggiungi la nuova impronta in `assetlinks.json`.

## 4. Build di release

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64
```

- `--obfuscate` e R8 rendono il codice illeggibile; i simboli per leggere eventuali crash restano in
  `build/symbols` (fuori dalla repo).
- `android-arm64` basta per i telefoni moderni e riduce l'APK a ~40 MB.

Il file è `build/app/outputs/flutter-apk/app-release.apk`.

## 5. Installazione sul telefono

**Senza cavo dati:** copia l'APK nella cartella *Download* del telefono, aprilo dall'app *File* e
tocca **Installa** (o **Aggiorna**). Poi cancella l'APK.

**Con adb** (debug USB attivo):

```bash
adb push build/app/outputs/flutter-apk/app-release.apk /data/local/tmp/bankingmobile.apk
adb shell pm install -r /data/local/tmp/bankingmobile.apk
adb shell rm /data/local/tmp/bankingmobile.apk
```

- Sui telefoni Xiaomi (HyperOS) va confermato **Installa** sul telefono entro pochi secondi; se scade
  compare `INSTALL_FAILED_USER_RESTRICTED` (lo stesso errore compare anche con poco spazio libero). In
  quel caso usa la strada senza cavo dati.
- Da Git Bash su Windows anteponi `MSYS_NO_PATHCONV=1` ai comandi `adb` con percorsi del telefono.
- Conferma che l'aggiornamento è arrivato:
  ```bash
  adb shell dumpsys package <nome del pacchetto> | grep lastUpdateTime
  ```

**Da debug a release:** le due build hanno firme diverse, quindi la prima volta l'app di debug va
disinstallata; i dati sul telefono si perdono.

## 6. Pubblicare una Release

Per chi installa senza compilare. Con la [GitHub CLI](https://cli.github.com):

```bash
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 build/app/outputs/flutter-apk/app-release.apk --title "v1.0.0" --notes "Novità: …"
```

- Pubblica solo APK firmati con la chiave di release e con tutti i test verdi.
- Se la repository è privata, la Release è visibile solo a chi ha accesso alla repository.
- L'APK non contiene segreti: APP_ID e `.pem` si inseriscono nell'app dopo l'installazione.

## 7. Aggiornare l'app

1. `git pull`, poi `flutter test --timeout 60s` (devono essere tutti verdi).
2. Build di release (punto 4) con **la stessa chiave**.
3. Installazione (punto 5): con la stessa firma i dati restano.

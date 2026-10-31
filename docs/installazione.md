# Installazione

Questa guida serve per **compilare** l'app, per pubblicare una **Release** e per gli
**aggiornamenti**. Il primo utilizzo (Enable Banking, `.pem`, APP_ID, banche) è
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

> **Non cambiare il nome del pacchetto** (`applicationId` in `android/app/build.gradle.kts`): la
> pagina di ritorno condivisa riapre l'app proprio con quel nome. Con una chiave diversa da quella della
> Release l'App Link non risulta verificato: il ritorno dalla banca funziona lo stesso, ma passa dalla
> pagina, che riapre l'app (a volte con un tocco su «Torna all'app»).

Per una chiave in un altro percorso imposta `BANKING_MOBILE_KEY_PROPERTIES` con il percorso del suo
`key.properties`. Senza chiave la build di release si ferma con un errore: non viene mai firmata con la
chiave di debug.

## 3. Build di release

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64
```

- `--obfuscate` e R8 rendono il codice illeggibile; i simboli per leggere eventuali crash restano in
  `build/symbols` (fuori dalla repo).
- `android-arm64` basta per i telefoni moderni e riduce l'APK a ~40 MB.

Il file è `build/app/outputs/flutter-apk/app-release.apk`.

## 4. Installazione sul telefono

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

## 5. Pubblicare una Release

Per chi installa senza compilare.

1. **Alza la versione** in `pubspec.yaml`, riga `version: <nome>+<numero>` (per esempio da
   `1.1.0+2` a `1.2.0+3`): il numero dopo il `+` deve crescere a ogni Release, altrimenti Android può
   non riconoscere l'APK come aggiornamento.
2. Lancia i test e fai la build di release (punto 3).
3. Committa, poi pubblica con la [GitHub CLI](https://cli.github.com), usando lo stesso nome di versione:

```bash
git tag v1.2.0
git push origin v1.2.0
gh release create v1.2.0 build/app/outputs/flutter-apk/app-release.apk --title "v1.2.0" --notes "Novità: …"
```

- Pubblica solo APK firmati con la chiave di release e con tutti i test verdi.
- Se la repository è privata, la Release è visibile solo a chi ha accesso alla repository.
- L'APK non contiene segreti: APP_ID e `.pem` si inseriscono nell'app dopo l'installazione.

## 6. Aggiornare l'app

1. `git pull`, poi `flutter test --timeout 60s` (devono essere tutti verdi).
2. Build di release (punto 3) con **la stessa chiave**.
3. Installazione (punto 4): con la stessa firma i dati restano.

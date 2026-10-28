# Sicurezza

Rapporto dell'audit finale (fase 8, 28/10/2026) secondo la checklist **OWASP MASVS v2**, sulla build di
release firmata installata sul telefono (Android 14).

## Modello di minaccia

| Minaccia | Protezione |
|---|---|
| Telefono perso o rubato, bloccato | Dati nel DB cifrato; la chiave è nel Keystore, utilizzabile solo dall'app su quel telefono |
| Telefono sbloccato in mano ad altri | L'app chiede impronta, volto o PIN all'apertura e dopo 30 minuti di inattività |
| Altre app sul telefono | Sandbox di Android; nessun componente o file condiviso; niente screenshot né anteprima |
| Backup e trasferimenti | Backup cloud e trasferimento tra dispositivi disattivati |
| Rete (Wi-Fi pubblico, proxy) | Solo HTTPS verso `api.enablebanking.com`, solo certificati di sistema |
| Ritorno dalla banca contraffatto | `state` casuale monouso con scadenza, confrontato a tempo costante |
| Furto della chiave Enable Banking | Chiave solo nel Keystore; in caso di furto si revoca l'app nel Control Panel |

## Esito per area MASVS

### STORAGE: archiviazione dei dati

- ✅ **DB cifrato** con SQLCipher 4.10 (AES-256). La chiave è di 256 bit casuali (`Random.secure`), ed è
  salvata cifrata con una chiave del Keystore hardware. Test sul telefono: `integration_test/db_encryption_test.dart`
  verifica che senza chiave, o con una chiave errata, il file sia illeggibile e il testo non compaia.
- ✅ **APP_ID e chiave privata `.pem`** stanno solo nel Keystore, mai nel DB (lo verifica un test).
  Nelle Impostazioni l'APP_ID salvato si vede solo come «•••• ultime 4 cifre».
- 🔧 **Corretto:** il selettore di file (`file_picker`) lasciava una **copia in chiaro del `.pem`**
  nella cache privata dell'app. Ora la copia viene cancellata subito dopo la lettura, e all'avvio
  l'app svuota le cartelle temporanee dei plugin.
- 🔧 **Corretto:** il CSV condiviso restava nella cache di `share_plus` fino alla condivisione
  successiva. Ora viene cancellato al successivo avvio dell'app.
- ✅ **Backup:** `allowBackup=false` e regole di esclusione per cloud e trasferimento. Sul telefono
  il flag `ALLOW_BACKUP` è assente.
- ✅ **Nessun log** con dati bancari o segreti: nel codice non ci sono `print` né `debugPrint`.
- ✅ **Notifiche:** contengono solo il nome della banca e i giorni alla scadenza.

### CRYPTO: crittografia

- ✅ **JWT RS256** per Enable Banking con `exp` a 5 minuti e `kid` uguale all'APP_ID, come sul web.
- ✅ **`state`** di 32 byte da `Random.secure`, monouso, valido 20 minuti, confrontato a tempo costante.
- ✅ Nessun algoritmo o chiave scritti nel codice. Nell'APK compaiono solo l'intestazione testuale
  `BEGIN RSA PRIVATE KEY` del parser PEM e i parametri pubblici delle curve ellittiche.

### AUTH: autenticazione

- ✅ Sblocco con `local_auth` (biometria oppure PIN o sequenza del telefono). L'app resta bloccata se il
  telefono non ha un blocco schermo.
- ✅ Si blocca dopo 30 minuti di inattività. Da bloccata **non viene costruita nessuna schermata con dati**.
- ℹ️ La chiave del DB è usabile anche senza sblocco, per **scelta di progetto**: serve alla
  sincronizzazione in background. Lo sblocco protegge l'interfaccia; i dati restano illeggibili fuori
  dall'app e fuori dal telefono.

### NETWORK: comunicazioni

- ✅ `network_security_config`: niente traffico in chiaro, solo CA di sistema. Le CA installate
  dall'utente non sono accettate, quindi un proxy che intercetta il traffico non funziona senza root.
- ✅ Timeout di 60 secondi. L'unico host contattato è `https://api.enablebanking.com`; il login con la
  banca avviene nel browser (Custom Tab effimera).
- ✅ Nessuna porta in ascolto: sul telefono l'app (UID 10283) non ha alcun socket aperto.
- ➖ **Certificate pinning: non adottato.** Fissare la chiave di `api.enablebanking.com` bloccherebbe
  l'app a ogni cambio di certificato non previsto, costringendo a un aggiornamento. Visto che le CA
  dell'utente sono già escluse, il beneficio residuo è basso. Lo si può rivalutare se Enable Banking
  pubblicherà le chiavi di riserva.

### PLATFORM: interazione con il sistema

- ✅ **Componenti esportati:** solo `MainActivity` (avvio, deep link, App Link). Gli altri componenti
  esportati (WorkManager, profileinstaller) richiedono permessi di sistema (`BIND_JOB_SERVICE`, `DUMP`).
- ✅ **Deep link:** accettati solo `bankingmobile://callback` e l'App Link verificato
  `https://francescozanella.github.io/Bankrelay/app`, e solo con uno `state` in attesa. Prova sul
  telefono: un link con `state` falso apre l'app ma viene rifiutato.
- ✅ **App Link verificato** con il certificato di release (`assetlinks.json`).
- ✅ **FLAG_SECURE:** su uno screenshot preso con l'app in primo piano risulta tutto nero, salvo la barra
  di stato.
- 🔧 **Permessi ridotti:** tolti `USE_FINGERPRINT`, la vecchia API superata da BiometricPrompt con
  minSdk 28, e `FOREGROUND_SERVICE`, che l'app non usa. Restano:

  | Permesso | Perché |
  |---|---|
  | `INTERNET` | Enable Banking |
  | `USE_BIOMETRIC` | sblocco |
  | `POST_NOTIFICATIONS` | avviso di consenso in scadenza (concesso dall'utente) |
  | `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE` | WorkManager: ripianificazione dopo il riavvio, esecuzione e attesa della rete |
  | `VIBRATE` | notifiche |

  Sono tutti permessi "normali", cioè concessi senza richiesta, tranne le notifiche.

### CODE: qualità del codice e dipendenze

- ✅ **Release** non `debuggable`, firmata con una chiave propria (RSA 4096, fuori dalla repo).
  R8 rimuove il codice inutile e `--obfuscate` offusca il codice Dart; i simboli restano fuori dall'APK.
- ✅ **Dipendenze:** nessuna vulnerabilità nota nel database OSV per i 100 pacchetti Dart di
  `pubspec.lock`, per SQLCipher Android 4.10.0 e per androidx.browser 1.9.0 (verifica del 28/10/2026).
- ✅ **Input:** categorie, regole e budget sono validati come sul web (icone solo dall'elenco, colore
  `#rrggbb`, importi con limite) e tutte le query sono parametrizzate. Il CSV è protetto dalle formule
  di Excel (CSV injection).

### RESILIENCE: resistenza a manomissioni

- 🔧 **Telefono con root:** aggiunto un avviso dopo lo sblocco, senza blocco, come previsto dal piano.
  L'avviso si basa su indizi semplici (binari `su`, Magisk, build `test-keys`), quindi va considerato
  un avviso e non una protezione.
- ➖ Niente anti-debug e niente controllo d'integrità: l'app è personale e non distribuita.

## Prove pratiche sul telefono (28/10/2026)

| Prova | Esito |
|---|---|
| Copiare il DB con `adb shell run-as` | rifiutato: "package not debuggable" |
| Leggere `/data/data/…/databases` da `adb shell` | "Permission denied" |
| DB copiato senza chiave | illeggibile (test di integrazione) |
| App Link con `state` falso da un'altra app | apre l'app, collegamento rifiutato |
| Screenshot con l'app in primo piano | nero |
| Porte in ascolto | nessuna |

## Repository

- Repo dell'app **privata**; le due repo pubbliche (`Bankrelay`, `francescozanella.github.io`) contengono
  solo la pagina di ritorno, `assetlinks.json` e un README.
- Controllo della cronologia completa (28/10/2026): nessun `.pem`, keystore, `key.properties`, `.env` o
  database mai committato; nessun APP_ID, password, token, IBAN reale o indirizzo email nei contenuti.

## Rischi residui

- **Telefono con root o malware con privilegi di sistema:** potrebbe usare la chiave del Keystore
  tramite l'app, perché la chiave non è legata allo sblocco (scelta per la sincronizzazione in background).
- **Telefono sbloccato e app aperta da meno di 30 minuti:** chi ha il telefono in mano vede i dati.
- **Chiave di firma:** se viene persa, gli aggiornamenti richiedono di reinstallare l'app; se viene
  rubata, qualcuno potrebbe firmare un aggiornamento valido, ma dovrebbe comunque installarlo sul
  telefono via USB. Il backup va tenuto nel password manager.
- **Chiave `.pem` di Enable Banking:** chi la ottiene può leggere i conti finché il consenso è valido.
  In quel caso si revoca l'applicazione nel Control Panel di Enable Banking.
- **Pagine pubbliche su GitHub (relay e `assetlinks.json`):** non contengono dati. Se un attaccante
  potesse modificarle, al massimo romperebbe il ritorno dalla banca, perché lo `state` resta comunque
  necessario.

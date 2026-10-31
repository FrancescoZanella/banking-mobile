# Sicurezza

Come l'app protegge i dati, secondo le aree della checklist **OWASP MASVS v2**, e quali rischi restano.

## Modello di minaccia

| Minaccia | Protezione |
|---|---|
| Telefono perso o rubato, bloccato | Dati nel DB cifrato; la chiave è nel Keystore, utilizzabile solo dall'app su quel telefono |
| Telefono sbloccato in mano ad altri | L'app chiede impronta, volto o PIN all'apertura e dopo 30 minuti di inattività |
| Altre app sul telefono | Sandbox di Android; nessun componente o file condiviso; niente screenshot né anteprima |
| Backup e trasferimenti | Backup cloud e trasferimento tra dispositivi disattivati |
| Rete (Wi-Fi pubblico, proxy) | Solo HTTPS verso `api.enablebanking.com`, solo certificati di sistema |
| Ritorno dalla banca contraffatto | `state` casuale monouso con scadenza, confrontato a tempo costante |
| Furto della chiave Enable Banking | Chiave solo nel Keystore; in caso di furto si revoca l'applicazione nel Control Panel |

## Archiviazione dei dati

- **DB cifrato** con SQLCipher (AES-256). La chiave è di 256 bit casuali ed è salvata cifrata con una
  chiave del Keystore hardware. Senza chiave, o con una chiave errata, il file è illeggibile
  (`integration_test/db_encryption_test.dart`).
- **APP_ID e chiave privata `.pem`** stanno solo nel Keystore, mai nel DB. Nelle Impostazioni l'APP_ID
  salvato si vede solo come «•••• ultime 4 cifre».
- Il `.pem` scelto con il selettore di file viene letto una volta; la copia temporanea del selettore
  viene cancellata subito, e all'avvio l'app svuota le cartelle temporanee dei plugin (anche il CSV
  condiviso).
- **Backup** disattivato (`allowBackup=false` e regole di esclusione per cloud e trasferimento).
- **Nessun log** con dati bancari o segreti; in release R8 toglie anche i log di debug dei plugin.
- **Notifiche:** quelle dei consensi contengono solo il nome della banca e i giorni alla scadenza.
  Quelle dei movimenti hanno visibilità *privata*: sulla schermata di blocco esercente, importo e
  pulsanti restano nascosti finché il telefono non viene sbloccato. I pulsanti assegnano solo la
  categoria a quel movimento, tramite un receiver non esportato.

## Crittografia

- **JWT RS256** per Enable Banking con `exp` a 5 minuti e `kid` uguale all'APP_ID.
- **`state`** di 32 byte casuali, monouso, valido 20 minuti, confrontato a tempo costante.
- Nessuna chiave scritta nel codice né nell'APK.

## Autenticazione

- Sblocco con biometria oppure PIN o sequenza del telefono; senza blocco schermo l'app resta bloccata.
- Blocco dopo 30 minuti di inattività. Da bloccata non viene costruita nessuna schermata con dati.
- La chiave del DB è usabile anche senza sblocco, **per scelta**: serve alla sincronizzazione in
  background. Lo sblocco protegge l'interfaccia; i dati restano illeggibili fuori dall'app e fuori dal
  telefono.

## Rete

- Niente traffico in chiaro, solo CA di sistema: le CA installate dall'utente non sono accettate, quindi
  un proxy che intercetta il traffico non funziona senza root.
- L'unico host contattato è `https://api.enablebanking.com`; il login con la banca avviene nel browser,
  in una scheda in incognito, e l'app non vede le credenziali della banca.
- Nessuna porta in ascolto.
- **Certificate pinning non adottato:** bloccherebbe l'app a ogni cambio di certificato non previsto;
  con le CA dell'utente già escluse il beneficio residuo è basso.

## Piattaforma

- Unico componente esportato utilizzabile da altre app: l'activity principale (avvio e ritorno dalla
  banca). Gli altri richiedono permessi di sistema.
- Ritorno dalla banca accettato solo da `bankingmobile://callback` o dall'App Link verificato, e solo con
  uno `state` in attesa. Un ritorno con `state` falso apre l'app ma viene rifiutato.
- **FLAG_SECURE:** screenshot e anteprima nelle app recenti risultano neri.
- Permessi:

  | Permesso | Perché |
  |---|---|
  | `INTERNET` | Enable Banking |
  | `USE_BIOMETRIC` | sblocco |
  | `POST_NOTIFICATIONS` | notifiche (concesso da te al primo avvio) |
  | `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE` | WorkManager: ripianificazione dopo il riavvio, esecuzione e attesa della rete |
  | `VIBRATE` | notifiche e conferme |

## Codice e dipendenze

- Release non `debuggable`, firmata con una chiave propria, ridotta con R8 e offuscata; i simboli
  restano fuori dall'APK.
- Input validati (icone solo dall'elenco, colori `#rrggbb`, importi con limite) e tutte le query SQL
  parametrizzate. Il CSV esportato è protetto dalle formule di Excel (CSV injection).
- Prima di ogni Release: test verdi e controllo delle dipendenze nel database [OSV](https://osv.dev).

## Resistenza a manomissioni

- **Telefono con root:** dopo lo sblocco compare un avviso, senza bloccare l'app. Si basa su indizi
  semplici, quindi è un avviso e non una protezione.
- Niente anti-debug né controllo d'integrità: l'app è per uso personale.

## Cosa devi fare tu

- Tieni il **`.pem`** solo il tempo di importarlo, poi cancellalo dal telefono; conservane una copia
  cifrata nel password manager. Mai in mail, chat o cloud.
- Se compili l'app, tieni **chiave di firma e `key.properties`** fuori dalla repo, con un backup nel
  password manager.
- Se perdi il telefono o temi che il `.pem` sia stato copiato, **revoca l'applicazione** (o le sessioni)
  nel Control Panel di Enable Banking e creane una nuova.

## Rischi residui

- **Telefono con root o malware con privilegi di sistema:** potrebbe usare la chiave del Keystore
  tramite l'app, perché la chiave non è legata allo sblocco (scelta per la sincronizzazione in background).
- **Telefono sbloccato e app aperta da meno di 30 minuti:** chi ha il telefono in mano vede i dati.
- **Chiave di firma:** se viene persa, gli aggiornamenti richiedono di reinstallare l'app; se viene
  rubata, qualcuno potrebbe firmare un aggiornamento valido, ma dovrebbe comunque installarlo sul
  telefono.
- **Chiave `.pem`:** chi la ottiene può leggere i conti finché il consenso è valido. In quel caso si
  revoca l'applicazione nel Control Panel di Enable Banking.
- **Pagine pubbliche su GitHub Pages** (condivise da tutti gli utenti dell'APK della Release): non
  contengono dati. Se qualcuno potesse modificarle, al massimo romperebbe il ritorno dalla banca: lo
  `state` resta necessario e il `code` è monouso e inutile senza il `.pem` di chi lo usa. Se venissero
  tolte, collegare o rinnovare una banca non funzionerebbe più; la sincronizzazione sì.

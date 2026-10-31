# Architettura

L'app è autonoma: **nessun server e nessuna porta aperta**. Tutto sta sul telefono e l'unica
connessione è in uscita verso `https://api.enablebanking.com`.

## Moduli

```
lib/
  main.dart            avvio: DB cifrato, Keystore, sblocco, deep link, sync in background
  app/                 app.dart (blocco, deep link, MaterialApp), services.dart (dipendenze iniettabili),
                       return_links.dart (ritorno dalla banca anche dopo che HyperOS ha chiuso l'app)
  core/                money (centesimi, formato €), dates (date di calendario UTC), periods, config
  data/                database (schema, migrazioni), defaults (categorie, icone, regole),
                       secure_database (SQLCipher), secure_store (Keystore, credenziali)
  bank/                enable_banking (JWT RS256, API), consent (stato monouso), bank_service
                       (collega, rinnova, scollega, elimina, ritorno dalla banca, SyncRunner)
  sync/                sync (normalizza, deduplica, PDNG, storico/incrementale, is_due),
                       schedule (orari 7/14/23 ora italiana), background (WorkManager,
                       notifiche di scadenza e dei movimenti con i pulsanti delle categorie)
  domain/              categorize, reports, analysis, cashflow, transactions, categories,
                       to_categorize (movimenti da notificare), budget (non usato dall'interfaccia)
  security/            app_lock (sblocco biometrico, 30 minuti di inattività)
  ui/                  una schermata per pagina (home, analysis, transactions, flows, categories,
                       accounts, settings, lock, shell) e inoltre:
                       widgets (riga del feed con scorrimento e selezione, dettaglio, avvisi, periodo),
                       charts (grafici fl_chart e barre divergenti), polish (avatar degli esercenti,
                       «Nascondi importi», sagome di caricamento, numeri animati, schermate vuote),
                       categorize_ui (selettore delle categorie, cambio con vibrazione e «Annulla»),
                       sort_screen («Smista»)
```

**Codice nativo** (`android/app/src/main/kotlin/…/MainActivity.kt`), raggiunto con due MethodChannel:

| Canale | Metodo | A cosa serve |
|---|---|---|
| `bankingmobile/custom_tabs` | `open` | login con la banca in una Custom Tab effimera (incognito) |
| `bankingmobile/device` | `isRooted` | indizi di root, solo per un avviso |

All'avvio `MainActivity` imposta `FLAG_SECURE` e svuota le cartelle temporanee dei plugin
(`cache/file_picker`, `cache/share_plus`).

**Risorse Android:** icona adattiva vettoriale (`mipmap-anydpi-v26/ic_launcher.xml`, banca su
`#7C83FF` con variante monocromatica), icona delle notifiche `drawable/ic_notification.xml` (tenuta da
`raw/keep.xml` perché è usata per nome dal codice Dart), `xml/network_security_config.xml` e
`xml/data_extraction_rules.xml`.

**Pagine pubbliche**, condivise da tutti gli utenti e pubblicate con GitHub Pages dalla repository
pubblica [`francescozanella.github.io`](https://github.com/FrancescoZanella/francescozanella.github.io):
in `banking/` la pagina di ritorno dalla banca, l'informativa privacy e i termini; in
`.well-known/assetlinks.json` l'App Link. Gli indirizzi sono nel
[README](../README.md#passo-2--copia-gli-indirizzi-pronti).

Le schermate leggono il DB direttamente tramite le funzioni di `domain/` e si ricaricano quando
`SyncRunner` notifica un cambiamento (sincronizzazione, banca collegata, categoria cambiata).

## Flussi principali

**Collegamento di una banca**
1. Conti → Collega banca: il nome scelto viene validato contro il catalogo di Enable Banking.
2. `bank_service` crea uno `state` casuale (32 byte, monouso, scade in 20 minuti) e ottiene
   l'indirizzo di login; la pagina si apre in una Custom Tab effimera (incognito).
3. La banca rimanda alla pagina di ritorno (`AppConfig.redirectUri`), che grazie all'App Link verificato
   riapre direttamente l'app (in alternativa la pagina rimanda a `bankingmobile://callback`).
4. L'app accetta il ritorno solo con uno `state` valido, crea la sessione, salva banca e conti e
   avvia il recupero dello storico.

**Movimenti da categorizzare**
- Ogni movimento ha `notified_at`: vuoto = da segnalare. Lo storico scaricato collegando o rinnovando
  una banca nasce già segnato (`storico`); quelli presenti prima di questa funzione sono segnati `prima`.
- Dopo ogni sincronizzazione (`SyncRunner.afterSync` in primo piano, `callbackDispatcher` in
  background) `notifyToCategorize` cerca i movimenti dubbi (`domain/to_categorize.dart`: visibili, non
  giroconti, non scelti a mano, in *Altre spese*/*Altre entrate* o senza categoria, degli ultimi 7
  giorni), mostra una notifica privata per ciascuno (canale «movimenti», raggruppate) e li segna.
- Il tocco porta l'id del movimento nel payload; `BankingApp` lo tiene da parte finché l'app è
  bloccata e dopo lo sblocco apre il dettaglio. Salvando la categoria la notifica viene tolta.
- I **pulsanti delle categorie** (al massimo 3, limite di Android) sono le categorie più scelte dello
  stesso tipo del movimento (`quickCategories`: prima quelle scelte a mano, poi le più usate; mai
  giroconti né categorie di ripiego). Il tocco arriva all'`ActionBroadcastReceiver` del plugin (non
  esportato, dichiarato nel manifest), che avvia un motore Flutter a parte ed esegue
  `onNotificationAction`: apre il DB con una connessione propria e chiama `setCategory` senza regola.

**Cambio di categoria dall'interfaccia** (`ui/categorize_ui.dart`)
- Dettaglio, scorrimento verso sinistra, selezione multipla in Movimenti e «Smista» passano tutti da
  `applyCategory`: prima `categorySnapshot` fotografa movimenti (categoria, origine, `is_internal`) ed
  eventuale regola con lo stesso testo; poi salva, toglie le notifiche, notifica le pagine e vibra.
- «Annulla» chiama `undoCategory`: rimette i movimenti, toglie la regola creata (o ripristina quella che
  c'era) e, se ha toccato una regola, ricalcola le categorie automatiche.
- «Smista» (`ui/sort_screen.dart`) usa le stesse funzioni e tiene una pila di fotografie per «Indietro».

**Nascondi importi**
- `AppServices.hideAmounts` (`ValueNotifier`) salvato nella tabella `settings` (`hide_amounts`) e letto
  all'avvio. I testi con importi usano `Amount`, i grafici `Sensitive`: con il valore attivo vengono
  sfocati (`ImageFiltered`) ed esclusi dai lettori di schermo.
- **Movimenti in attesa:** a ogni sincronizzazione vengono cancellati e riscaricati. Prima di
  cancellarli `storeTransactions` ne ricorda categoria manuale e `notified_at` e li passa al movimento
  che li sostituisce: stesso id, oppure stesso importo e stessa controparte entro 7 giorni.

**Sincronizzazione**
- Solo da WorkManager alle 7, 14 e 23 ora italiana: un lavoro singolo che a fine esecuzione mette in
  coda il successivo (`ExistingWorkPolicy.update`). Niente sync all'apertura né a mano; restano solo
  quelle dello storico dopo un collegamento o un rinnovo. Minimo 4 ore tra due sync dello stesso conto.
- I lavori in background (sync e pulsanti delle notifiche) aprono il database con una connessione
  propria: il plugin altrimenti riuserebbe quella dell'app aperta, e chiuderla la chiuderebbe anche
  all'app. `busy_timeout` di 10 s su tutte le connessioni.
- Saldi e movimenti vengono normalizzati in centesimi interi, deduplicati con una chiave stabile; i
  movimenti in attesa (PDNG) vengono sostituiti da quelli contabilizzati.
- Dopo ogni sincronizzazione: riconoscimento dei giroconti (solo IBAN dei tuoi conti o tuo nome) e
  categorizzazione con le regole.

## Dati

Database SQLCipher nella memoria privata dell'app; la chiave (256 bit casuali) è nel Keystore,
utilizzabile anche senza sblocco per permettere la sincronizzazione in background. Tabelle: `banks`,
`consents`, `accounts`, `balances`, `transactions`, `categories`, `category_rules`, `budgets`,
`subscription_ignores`, `pending_auth`, `sync_runs`, `settings`. Da notare `transactions.notified_at`
(notifiche «da categorizzare»), `categories.investment` (categoria di investimento) e l'impostazione
`hide_amounts` («Nascondi importi»).

**Regole dei conteggi** (`domain/reports.dart`):

| Movimento | Totali di tutti i conti (Home, Analisi, Flussi, Movimenti senza filtro) | Movimenti filtrati su un conto |
|---|---|---|
| Spese ed entrate normali | contano | contano |
| Giroconti (`is_internal = 1`) | non contano; in Flussi «Spostato tra i tuoi conti» | contano |
| Investimenti (`categories.investment = 1`) | mai uscite o spese; sommati ai risparmiati; riquadro «Investiti» | mai uscite o spese |

Risparmiati = entrate − uscite senza investimenti (cioè quello che resta sul conto più l'investito).

**Dati dal 1 agosto 2026** (`AppConfig.dataStart`): la sincronizzazione non chiede né salva movimenti
precedenti, `initDb` cancella quelli già presenti, grafici e confronti non vanno prima.

**Ordine dei movimenti** (`txOrder`): data contabile dal più recente; nello stesso giorno (le banche non
danno l'ora) prima quelli scaricati per ultimi.

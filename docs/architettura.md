# Architettura

L'app è autonoma: **nessun server e nessuna porta aperta**. Tutto sta sul telefono e l'unica
connessione è in uscita verso `https://api.enablebanking.com`. La logica è la stessa della versione
web (`banking-dashboard/app/`), riscritta in Dart; i test di [parità](parita-test.md) garantiscono che
il risultato coincida.

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
                       background (WorkManager ogni ~12 h, notifiche di scadenza)
  domain/              categorize, reports, analysis, cashflow, transactions, categories,
                       to_categorize (movimenti da notificare), budget (solo logica: pagina tolta)
  security/            app_lock (sblocco biometrico, 30 minuti di inattività)
  ui/                  una schermata per pagina + widgets (feed, dettaglio, avvisi, periodo) e charts
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

**Pagine pubbliche** (sorgenti in `relay/`, pubblicate con GitHub Pages): `relay/app/index.html` è la
pagina di ritorno dalla banca (repo `Bankrelay`), `relay/user-site/` contiene `assetlinks.json` (repo
`francescozanella.github.io`).

Le schermate leggono il DB direttamente tramite le funzioni di `domain/` e si ricaricano quando
`SyncRunner` notifica un cambiamento (sincronizzazione, banca collegata, categoria cambiata).

## Flussi principali

**Collegamento di una banca**
1. Conti → Collega banca: il nome scelto viene validato contro il catalogo di Enable Banking.
2. `bank_service` crea uno `state` casuale (32 byte, monouso, scade in 20 minuti) e ottiene
   l'indirizzo di login; la pagina si apre in una Custom Tab effimera (incognito).
3. La banca rimanda alla relay `https://francescozanella.github.io/Bankrelay/app`, che grazie all'App
   Link verificato riapre direttamente l'app (in alternativa rimanda a `bankingmobile://callback`).
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
- **Movimenti in attesa:** a ogni sincronizzazione vengono cancellati e riscaricati. Prima di
  cancellarli `storeTransactions` ne ricorda categoria manuale e `notified_at` e li passa al movimento
  che li sostituisce: stesso id, oppure stesso importo e stessa controparte entro 7 giorni.

**Sincronizzazione**
- All'apertura (dopo lo sblocco) e da WorkManager ogni ~12 ore, solo per i conti "scaduti".
- Saldi e movimenti vengono normalizzati in centesimi interi, deduplicati con una chiave stabile; i
  movimenti in attesa (PDNG) vengono sostituiti da quelli contabilizzati.
- Dopo ogni sincronizzazione: riconoscimento dei giroconti (solo IBAN dei tuoi conti o tuo nome) e
  categorizzazione con le regole.

## Dati

Database SQLCipher nella memoria privata dell'app; la chiave (256 bit casuali) è nel Keystore,
utilizzabile anche senza sblocco per permettere la sincronizzazione in background. Le tabelle sono le
stesse del web: `banks`, `consents`, `accounts`, `balances`, `transactions`, `categories`,
`category_rules`, `budgets`, `subscription_ignores`, `pending_auth`, `sync_runs`, `settings`.
In più: `transactions.notified_at` (notifiche «da categorizzare») e `categories.investment`
(categoria di investimento).

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

## Differenze volute rispetto al web

- Sblocco biometrico al posto di password, setup e "Cambia password".
- Sincronizzazione anche in background, con notifica dei consensi in scadenza.
- Barra di navigazione Home, Analisi, Movimenti, Flussi, Altro; dettaglio del movimento e filtri come
  pannelli dal basso.
- Niente pagina Budget e abbonamenti (tolta su richiesta).
- Dati dal 1 agosto 2026; giroconti neutri sul totale e reali sul singolo conto; categoria
  Investimenti; Flussi anche per settimana e divisi per categoria; menu delle categorie dalla più usata.
- Notifiche dei movimenti da categorizzare.
- Export CSV con la condivisione di Android.
- Colore delle categorie scelto da una tavolozza invece del selettore libero.

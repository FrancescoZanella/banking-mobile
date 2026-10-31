# Banking Dashboard · Android

**I conti di tutte le tue banche in un'unica app, sul telefono, senza server.**

App Android per uso personale, scritta in Flutter. Legge saldi e movimenti con le API PSD2 di
informazione sui conti (AIS) di [Enable Banking](https://enablebanking.com) e li analizza: patrimonio,
movimenti, spese ed entrate per categoria, flussi di cassa. I dati restano solo sul telefono, cifrati.

| | |
|---|---|
| **Piattaforma** | Android 9 o successivo (provata su Android 14, HyperOS 2) |
| **Tecnologia** | Flutter 3.32 · Dart 3.8 · SQLCipher · Android Keystore · WorkManager |
| **Banche** | quelle italiane del catalogo Enable Banking |
| **Dati** | solo sul telefono, cifrati; l'unico servizio contattato è `api.enablebanking.com` |
| **Qualità** | 112 test automatici, controlli OWASP MASVS ([sicurezza](docs/sicurezza.md)) |

---

## Indice

1. [Cosa fa](#cosa-fa)
2. [Cosa serve](#cosa-serve)
3. [Passo 1 · Scarica o compila l'app](#passo-1--scarica-o-compila-lapp)
4. [Passo 2 · Copia gli indirizzi pronti](#passo-2--copia-gli-indirizzi-pronti)
5. [Passo 3 · Crea l'applicazione su Enable Banking](#passo-3--crea-lapplicazione-su-enable-banking)
6. [Passo 4 · Primo avvio: APP_ID, chiave e banche](#passo-4--primo-avvio-app_id-chiave-e-banche)
7. [Limiti](#limiti)
8. [Sicurezza in breve](#sicurezza-in-breve)
9. [Documentazione](#documentazione)
10. [Per chi sviluppa](#per-chi-sviluppa)

---

## Cosa fa

| Pagina | In breve |
|---|---|
| **Home** | patrimonio totale, schede dei conti, avvisi sui consensi, spese del mese, ultimi movimenti; riquadro *Da categorizzare* con la modalità **Smista** |
| **Analisi** | settimana, mese o anno: speso e confronto con il periodo precedente allo stesso giorno, curva cumulata, ultimi 12 mesi, categorie ed esercenti |
| **Movimenti** | ricerca, pannello **Filtri** (periodo, tipo, conti e categorie anche in più insieme, importo), totali, export CSV, selezione multipla |
| **Flussi** | entrate, uscite, risparmio e tasso di risparmio; **saldo per categoria** (entrate meno uscite); uscite ed entrate per categoria; andamento del patrimonio; entrate ricorrenti |
| **Altro** | Categorie e regole, Conti (collega, rinnova, scollega, elimina), Impostazioni |

E inoltre:

- **Categorie automatiche** con regole per testo o codice esercente (MCC); le scelte a mano non vengono
  mai sovrascritte.
- **Cambio di categoria rapido:** dal dettaglio, **scorrendo un movimento verso sinistra**, con la
  **selezione multipla** (pressione lunga) o con **Smista** (un movimento alla volta). Ogni cambio si può
  **annullare**.
- **Notifiche dei movimenti da categorizzare**, con i pulsanti delle 3 categorie che scegli più spesso:
  un tocco salva la categoria senza aprire l'app.
- **Giroconti** tra i tuoi conti riconosciuti dall'IBAN o dal tuo nome: fuori dai totali di tutti i
  conti, contati quando guardi un conto solo.
- **Investimenti** (scelti a mano): non sono spese, si sommano ai risparmiati.
- **Nascondi importi:** un tocco sull'occhio in Home sfoca importi e grafici in tutta l'app.
- **Sincronizzazione automatica** alle 7, alle 14 e alle 23 (ora italiana) e avviso prima della
  scadenza del consenso bancario.

Il funzionamento pagina per pagina è nella [Guida all'uso](docs/guida-utente.md).

---

## Cosa serve

- Un **telefono Android 9+** con un blocco schermo (impronta, volto o PIN): l'app si apre solo così.
- Un **account [Enable Banking](https://enablebanking.com)** (gratuito per uso personale, in modalità
  limitata).
- Un **PC** con il cavo USB, per copiare sul telefono la chiave `.pem` (ed eventualmente l'APK). Serve
  solo all'inizio e per gli aggiornamenti.

Tempo indicativo: 20-30 minuti la prima volta.

---

## Passo 1 · Scarica o compila l'app

L'app non è su Google Play. Due strade:

### A · Scarica l'APK pronto (consigliata)

1. Nella pagina **Releases** di questa repository apri l'ultima versione e scarica `app-release.apk`.
2. Copia il file sul telefono (cavo USB, cartella *Download*).
3. Sul telefono apri l'app **File** → *Download* → tocca l'APK → **Installa**. Android chiede di
   consentire l'installazione da questa sorgente: consentila solo per questa volta.
4. Cancella l'APK da *Download*.

> L'APK delle Release è firmato e usa le **pagine pubbliche già pronte** del passo 2: non devi
> pubblicare niente.

### B · Compila dal codice

Serve solo per modificare l'app. In breve:

```bash
flutter pub get
flutter test --timeout 60s
flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64
```

Prima della build servono l'ambiente (Flutter 3.32.4, Android SDK 36, NDK 27) e **una tua chiave di
firma**. Tutto passo per passo in [Installazione](docs/installazione.md).

---

## Passo 2 · Copia gli indirizzi pronti

Enable Banking chiede alcuni indirizzi `https://` pubblici. Sono già online, uguali per tutti:

| Pagina | Indirizzo |
|---|---|
| **Ritorno dalla banca** (Redirect URL) | `https://francescozanella.github.io/banking/` |
| **Informativa privacy** | `https://francescozanella.github.io/banking/privacy.html` |
| **Termini di utilizzo** | `https://francescozanella.github.io/banking/termini.html` |

- Sono pagine **statiche**: non contengono segreti e non raccolgono dati. La pagina di ritorno riapre
  soltanto l'app sul tuo telefono, passandole `code` e `state`.
- Il `code` è monouso e senza il **tuo** `.pem` non serve a niente: chi pubblica le pagine non può
  leggere i tuoi conti.
- Privacy e termini valgono per chiunque usi l'app: ognuno è l'unico titolare dei propri dati, che
  restano sul suo telefono.
- Con l'APK delle Release il ritorno dalla banca apre l'app direttamente (App Link verificato).
- Servono solo quando colleghi una banca o rinnovi il consenso (circa ogni 180 giorni), non per la
  sincronizzazione.

Stanno tutte nella repository pubblica
[`francescozanella.github.io`](https://github.com/FrancescoZanella/francescozanella.github.io).

---

## Passo 3 · Crea l'applicazione su Enable Banking

1. Registrati su [enablebanking.com](https://enablebanking.com) e apri il **Control Panel**.
2. Crea una **nuova applicazione** nell'ambiente **production** (non sandbox: la sandbox ha solo banche
   finte). Per uso personale va bene la **modalità limitata** (*restricted*).
3. Compila il modulo:
   - **nome** dell'applicazione (es. «Banking Dashboard telefono»);
   - **Redirect URL:** `https://francescozanella.github.io/banking/`, **identico** carattere per
     carattere (maiuscole e `/` finale comprese);
   - **privacy** e **termini**, se richiesti: gli altri due indirizzi del passo 2;
   - un'email di contatto, se richiesta: la **tua**.
4. Alla creazione il sito genera la coppia di chiavi e **scarica il file `<APP_ID>.pem`**: è la **chiave
   privata** e viene data **una volta sola**.
   - L'**APP_ID** è l'identificativo dell'applicazione: è anche il nome del file senza `.pem`.
   - Tieni il `.pem` solo sul PC finché non l'hai importato nel telefono (passo 4). Mai in mail, chat,
     cloud o nella cartella del progetto. Conservane una copia cifrata nel password manager.
5. **Collega i tuoi conti all'applicazione:** nella pagina dell'applicazione, nella sezione dei conti,
   collega le banche e i conti che vuoi vedere.

> ⚠️ **Modalità limitata:** l'applicazione legge **solo** i conti collegati qui. Se salti il punto 5 il
> login con la banca riesce, ma l'app non riceve nessun conto. Per aggiungere una banca in futuro:
> prima la colleghi qui, poi nell'app.

✅ **Fatto quando:** hai il file `.pem`, conosci l'APP_ID e nel Control Panel vedi i conti collegati.

---

## Passo 4 · Primo avvio: APP_ID, chiave e banche

### 4.1 Sblocca l'app

Apri **Banking Dashboard** e sbloccala con impronta, volto o PIN. Se Android chiede di mostrare le
**notifiche**, consentile: servono per i movimenti da categorizzare e per il consenso in scadenza.

### 4.2 Importa APP_ID e chiave privata

1. Con il cavo USB copia il `.pem` dal PC nella cartella **Download** del telefono.
2. Nell'app: **Altro → Impostazioni**.
3. Scrivi l'**APP_ID** (il campo nasconde il testo; l'occhio lo mostra).
4. Tocca **Scegli il file .pem** e seleziona il file.
5. Tocca **Salva**. APP_ID e chiave finiscono nel **Keystore** del telefono; l'app non ne tiene altre
   copie.
6. **Cancella subito il `.pem` dalla cartella Download** (e dal cestino dell'app File, se c'è).

✅ **Fatto quando:** in Impostazioni compare «APP_ID salvato: •••• ultime 4 cifre».

### 4.3 Collega la prima banca

1. **Altro → Conti → Collega banca** e scegli la banca dall'elenco (c'è la ricerca).
2. Si apre la pagina della banca in una scheda del browser **in incognito**: fai il login con le tue
   credenziali e l'autenticazione forte (SCA). L'app non vede mai le credenziali della banca.
3. Al termine la banca torna alla pagina di ritorno, che riapre l'app. Compare l'esito e parte da solo il
   **recupero dello storico** (quanto la banca concede, spesso ~90 giorni).
4. Ripeti per le altre banche.

> Il consenso dura il massimo concesso dalla banca (circa **180 giorni**). Due settimane prima della
> scadenza compaiono un avviso e una notifica: tocca **Rinnova** e rifai il login con la banca.

### 4.4 Impostazioni consigliate del telefono

- **Batteria senza restrizioni** per l'app (su Xiaomi/HyperOS: *Impostazioni → App → Gestisci app →
  Banking Dashboard → Risparmio batteria → Nessuna restrizione*). Senza, Android può rimandare la
  sincronizzazione delle 7, 14 e 23 e le notifiche.
- Nascondi i conti che non vuoi nei totali (per esempio quelli in valuta estera): **Conti → tocca il
  conto → Nascondi**.

Fatto: da qui in poi l'app si aggiorna da sola. Come si usa è nella [Guida all'uso](docs/guida-utente.md).

---

## Limiti

**Dovuti a PSD2 e alle banche**

- **Non è in tempo reale:** senza di te presente le banche concedono circa **4 accessi al giorno** per
  conto, quindi l'app sincronizza solo alle **7, 14 e 23** (ora italiana) e non a mano. In più le banche
  pubblicano i movimenti con ore o giorni di ritardo.
- **Consenso di circa 180 giorni:** poi va rinnovato con il login della banca (SCA).
- **Storico limitato:** al primo collegamento ogni banca dà quanto vuole, spesso ~90 giorni.
- **Solo i conti collegati** all'applicazione nel Control Panel di Enable Banking (modalità limitata).
- **Conti titoli e carte non leggibili** da alcune banche: gli investimenti si vedono solo come
  bonifici in uscita, da segnare a mano come *Investimenti*.
- **Niente codice esercente (MCC)** da molte banche: per questo alcune spese finiscono in *Altre spese*
  finché non le categorizzi (una volta, con una regola, valgono anche per le successive).

**Dovuti al telefono**

- WorkManager **non garantisce il minuto**: la sincronizzazione può partire qualche minuto dopo, di più
  con il risparmio energetico; senza rete parte quando torna.
- Le notifiche mostrano al massimo **3 pulsanti** (limite di Android); per le altre categorie si tocca la
  notifica.
- **Niente backup:** disinstallando l'app o cambiando telefono i dati si perdono; si reimportano APP_ID e
  `.pem` e si ricollegano le banche.
- **Niente screenshot** dell'app (bloccati apposta).
- Serve un **blocco schermo** sul telefono.

**Scelte dell'app**

- **Nessuna conversione di valuta:** i conti non in euro si vedono a parte; nascondili se non li vuoi
  nei totali.
- **Dati da una data di partenza fissa** (`AppConfig.dataStart` in [`config.dart`](lib/core/config.dart)):
  i movimenti precedenti non vengono scaricati né conservati.
- **Giroconti** riconosciuti solo dall'IBAN dei tuoi conti o dal tuo nome; gli altri si segnano a mano.
- App **per uso personale**, non pubblicata su Google Play.

---

## Sicurezza in breve

- Sblocco con **impronta, volto o PIN** del telefono; blocco dopo 30 minuti di inattività.
- **Database cifrato** (SQLCipher, AES-256) con la chiave nel **Keystore**; APP_ID e chiave privata di
  Enable Banking solo nel Keystore.
- **Niente backup** su Google, **niente screenshot**, **solo HTTPS**, nessun server e nessuna porta aperta.
- Login con la banca in una scheda **in incognito**; ritorno nell'app solo con uno `state` monouso valido.
- Le notifiche sulla schermata di blocco non mostrano esercente, importo né pulsanti.
- **Nascondi importi** per usarla in pubblico.

Dettagli, prove e rischi residui in [Sicurezza](docs/sicurezza.md).

---

## Documentazione

| Documento | Per chi | Contenuto |
|---|---|---|
| [Guida all'uso](docs/guida-utente.md) | chi la usa | ogni pagina, categorie, notifiche, Smista, banche e consensi, domande frequenti |
| [Installazione](docs/installazione.md) | chi la compila o la aggiorna | ambiente, chiave di firma, pagina di ritorno e App Link propri, build, Release, aggiornamenti |
| [Architettura](docs/architettura.md) | chi modifica il codice | moduli, flussi (collegamento, sync, notifiche), dati, codice nativo |
| [Sviluppo](docs/sviluppo.md) | chi modifica il codice | struttura della repo, test, versioni fissate, convenzioni, cosa non va mai su GitHub |
| [Sicurezza](docs/sicurezza.md) | tutti | protezioni (OWASP MASVS), permessi, cosa fare con le chiavi, rischi residui |

---

## Per chi sviluppa

```bash
flutter pub get
flutter analyze
flutter test --timeout 60s
```

```
lib/               codice dell'app (core, data, bank, sync, domain, security, ui)
test/              test di logica e delle schermate
integration_test/  test sul telefono (cifratura del database)
android/           progetto Android: manifest, icone, codice nativo (MainActivity.kt), firma
docs/              documentazione
```

Mai su GitHub: `.pem`, chiavi di firma, `key.properties`, database, CSV esportati. Vedi
[Sviluppo](docs/sviluppo.md#cosa-non-va-mai-su-github).

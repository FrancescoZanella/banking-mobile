# Immagini della documentazione

Il README e la [Guida all'uso](../guida-utente.md) mostrano già queste immagini: basta salvarle qui con
**esattamente questi nomi** (PNG). Finché un file manca, al suo posto si vede solo il testo alternativo.

## Prima di catturare

- **Niente dati veri:** copri (o sfoca) nomi di esercenti, importi, IBAN, nomi dei conti, APP_ID,
  email e indirizzi personali. L'APP_ID non è segreto come il `.pem`, ma non serve mostrarlo.
- **Mai** catturare il contenuto del file `.pem`.
- Telefono: catture verticali, ritagliate senza barra di stato se possibile. Larghezza consigliata
  ~1080 px (nella pagina vengono mostrate a 260 px).
- PC: solo la parte utile della pagina, larghezza massima ~1400 px.

> **Schermate dell'app:** l'app blocca gli screenshot (FLAG_SECURE), quindi dal telefono escono nere.
> Le notifiche invece si possono catturare (stanno nella tendina di Android, fuori dall'app).

## App (telefono)

| File | Cosa mostrare |
|---|---|
| `home.png` | Home: patrimonio, schede dei conti, riquadro «Da categorizzare» con il pulsante *Smista* |
| `nascondi-importi.png` | Home con «Nascondi importi» attivo (importi sfocati) |
| `movimenti.png` | Movimenti con un paio di filtri attivi (pillole sotto la ricerca) e la lista per giorno |
| `filtri.png` | Pannello *Filtri* aperto, con due categorie selezionate |
| `scorrimento.png` | Una riga di Movimenti scorsa verso sinistra (sfondo viola «Categoria») |
| `selezione.png` | Selezione multipla: righe con la spunta e la barra in basso |
| `dettaglio.png` | Dettaglio di un movimento: avatar, importo, categoria, *Applica a tutti…* |
| `smista.png` | Smista: scheda del movimento con i pulsanti delle categorie |
| `analisi.png` | Analisi del mese: speso, confronto e curva cumulata |
| `flussi.png` | Flussi: riquadri in alto e «Saldo per categoria» |
| `notifica.png` | Notifica di un movimento da categorizzare con i 3 pulsanti (tendina delle notifiche) |
| `impostazioni.png` | Altro → Impostazioni, prima del salvataggio: campo APP_ID vuoto e pulsante *Scegli il file .pem* |
| `conti.png` | Altro → Conti: pulsante *Collega banca* e una banca collegata con lo stato del consenso |
| `scegli-banca.png` | L'elenco delle banche con la ricerca, dopo *Collega banca* |

## Enable Banking (PC)

| File | Cosa mostrare |
|---|---|
| `eb-nuova-applicazione.png` | Control Panel: modulo di creazione della nuova applicazione (production), con il campo dei Redirect URL compilato |
| `eb-applicazione.png` | La pagina dell'applicazione creata, con Redirect URL, privacy e termini (APP_ID coperto) |
| `eb-conti-collegati.png` | La sezione in cui si collegano i conti all'applicazione (modalità limitata), IBAN coperti |

## GitHub (PC)

| File | Cosa mostrare |
|---|---|
| `github-pages.png` | Repository della pagina di ritorno → *Settings → Pages*, con branch `main` e cartella `/ (root)` |
| `github-release.png` | La pagina della Release con `app-release.apk` tra gli allegati |

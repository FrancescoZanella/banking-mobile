# Banking Dashboard · Android

**I conti di tutte le tue banche in un'unica app, sul telefono, senza server.**

App Android personale, scritta in Flutter, che legge i conti tramite le API PSD2 (AIS) di
[Enable Banking](https://enablebanking.com) e li analizza: patrimonio, movimenti, spese per categoria,
flussi di cassa, budget e abbonamenti. È la versione per telefono della dashboard web
(`banking-dashboard`): **per l'utente funziona allo stesso modo**, ma non serve accendere il PC.

| | |
|---|---|
| **Piattaforma** | Android 9+ (testata su Android 14, HyperOS 2) |
| **Tecnologia** | Flutter 3.32 · Dart 3.8 · SQLCipher · Android Keystore · WorkManager |
| **Banche** | tutte quelle italiane del catalogo Enable Banking |
| **Dati** | solo sul telefono, cifrati; l'unico servizio contattato è `api.enablebanking.com` |
| **Stato** | completa: fasi 0-8 chiuse, 81 test, audit OWASP MASVS ([rapporto](docs/sicurezza.md)) |

## Cosa fa

- **Home:** patrimonio totale, schede dei conti, avvisi su consensi e budget, spese del mese, ultimi
  movimenti raggruppati per giorno.
- **Movimenti:** ricerca, filtri (conto, categoria, periodo, tipo, importo), totali, export CSV.
  Dal dettaglio di un movimento si cambia la categoria, anche con una regola per i movimenti futuri.
- **Analisi:** settimana, mese o anno, confronto con il periodo precedente allo stesso giorno, curva
  cumulata, ultimi 12 mesi, categorie ed esercenti.
- **Flussi:** entrate, uscite, risparmio e tasso di risparmio, andamento del patrimonio, entrate ricorrenti.
- **Budget e abbonamenti:** limiti mensili con previsione a fine mese, abbonamenti riconosciuti in automatico.
- **Categorie e regole:** icone, colori, regole per testo o codice esercente (MCC).
- **Giroconti** tra i tuoi conti riconosciuti dall'IBAN o dal tuo nome: visibili, ma esclusi dai totali.
- **Notifiche dei movimenti da categorizzare:** per ogni movimento nuovo che le regole non riconoscono;
  il tocco apre il dettaglio per scegliere la categoria.

## Sicurezza in breve

- Sblocco con **impronta, volto o PIN** del telefono; blocco dopo 30 minuti di inattività.
- **Database cifrato** (SQLCipher, AES-256) con la chiave nel **Keystore** hardware; APP_ID e chiave
  privata di Enable Banking solo nel Keystore.
- **Niente backup** su Google, **niente screenshot**, **solo HTTPS** con le CA di sistema, nessuna porta aperta.
- Login con la banca in una scheda del browser **in incognito**; ritorno nell'app tramite
  **App Link verificato** e `state` monouso.
- **Consenso bancario ~180 giorni:** sincronizzazione automatica (all'apertura e ogni ~12 ore in
  background) e notifica prima della scadenza.

Dettagli, prove e rischi residui in [docs/sicurezza.md](docs/sicurezza.md).

## Documentazione

| Documento | Per chi | Contenuto |
|---|---|---|
| [Guida all'uso](docs/guida-utente.md) | chi la usa | pagine, banche e consensi, sincronizzazione, categorie, budget, domande frequenti |
| [Installazione](docs/installazione.md) | chi la installa o la aggiorna | ambiente, chiave di firma, build di release, primo avvio, aggiornamenti |
| [Architettura](docs/architettura.md) | chi modifica il codice | moduli, flussi, dati, codice nativo, differenze dal web |
| [Sviluppo](docs/sviluppo.md) | chi modifica il codice | struttura della repo, test, versioni fissate, cosa non va mai su GitHub |
| [Sicurezza](docs/sicurezza.md) | tutti | audit OWASP MASVS, protezioni, prove sul telefono, rischi residui |
| [Parità dei test](docs/parita-test.md) | chi modifica il codice | ogni test della versione web e il suo corrispondente qui |

## Avvio rapido (sviluppo)

```
flutter pub get
flutter analyze
flutter test
```

Per la build firmata e l'installazione sul telefono vedi [Installazione](docs/installazione.md).

## Struttura

```
lib/               codice dell'app (core, data, bank, sync, domain, security, ui)
test/              test di logica e delle schermate (parità con la versione web)
integration_test/  test sul telefono (cifratura del database)
android/           progetto Android: manifest, icone, codice nativo (MainActivity.kt), firma
relay/             sorgenti delle pagine pubbliche su GitHub Pages (ritorno dalla banca, assetlinks.json)
docs/              documentazione
```

## Limiti noti

- Nessuna conversione di valuta: i conti non in euro vanno nascosti (pagina Conti).
- Lo storico dipende dalla banca: alcune forniscono solo ~90 giorni anche al primo collegamento.
- Telefono e PC hanno dati separati: ognuno ha il suo collegamento alle banche.
- Repo privata e app per uso personale: non è pubblicata su Google Play.

# Banking Dashboard per Android

App Android personale, scritta in Flutter, che raccoglie in un'unica vista i conti di più banche
letti tramite le API PSD2 (AIS) di [Enable Banking](https://enablebanking.com). È la versione per
telefono della dashboard web (`banking-dashboard`): **per l'utente funziona allo stesso modo**,
ma non serve accendere il PC.

| Documento | Per chi | Contenuto |
|---|---|---|
| [Installazione](docs/installazione.md) | chi la installa o la aggiorna | ambiente, chiave di firma, build di release, primo avvio, aggiornamenti, ripristino |
| [Guida all'uso](docs/guida-utente.md) | chi la usa | pagine, banche e consensi, sincronizzazione, categorie, budget |
| [Architettura](docs/architettura.md) | chi modifica il codice | moduli, flussi, dati, differenze dal web |
| [Sviluppo](docs/sviluppo.md) | chi modifica il codice | test, versioni fissate, telefono di prova, convenzioni |
| [Parità dei test](docs/parita-test.md) | chi modifica il codice | ogni test del web e il suo corrispondente qui |

## In breve

- **Sblocco con impronta, volto o PIN del telefono**, nessuna password dell'app. Si blocca dopo
  30 minuti di inattività; screenshot e anteprima nelle app recenti sono bloccati.
- **Login con la banca ogni ~180 giorni:** il consenso dura il massimo concesso dalla banca; nel
  frattempo la sincronizzazione è automatica, all'apertura e in background ogni ~12 ore, con una
  notifica quando un consenso sta per scadere.
- **Dati solo sul telefono:** database SQLCipher con la chiave nel Keystore di Android, niente backup
  su Google. L'unico servizio contattato è `api.enablebanking.com`, solo in HTTPS.
- **Niente doppi conteggi:** i giroconti tra i tuoi conti restano visibili ma sono esclusi da tutti i totali.

## Limiti noti

- Nessuna conversione di valuta: i conti non in euro vanno nascosti (pagina Conti).
- Lo storico dipende dalla banca: alcune forniscono solo ~90 giorni anche al primo collegamento.
- Il telefono e il PC hanno dati separati: ognuno ha il suo collegamento alle banche.

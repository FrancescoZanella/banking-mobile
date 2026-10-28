# Guida all'uso

L'app si apre con lo sblocco del telefono (impronta, volto o PIN) e si blocca da sola dopo 30 minuti
senza tocchi. La barra in basso ha cinque voci: **Home, Analisi, Movimenti, Budget, Altro**
(in Altro: Flussi, Categorie, Conti, Impostazioni).

## Home

- **Patrimonio totale** dei conti visibili e il saldo del mese (entrate meno uscite).
- **Schede dei conti** scorrevoli in orizzontale.
- **Avvisi:** consenso scaduto o in scadenza (con *Rinnova ora*) e budget all'80% o superati
  (con *Vedi budget*).
- **Questo mese:** speso finora, entrate e uscite; **Dove spendi questo mese:** le 6 categorie principali.
- **Movimenti recenti** raggruppati per giorno. Tocca un movimento per il dettaglio.

## Dettaglio di un movimento

Conto, date, descrizione, IBAN della controparte (mascherato), codice esercente. Da qui puoi:

- **cambiare la categoria** (o tornare ad *Automatica*);
- con *Applica a tutti i movimenti di «…»*, creare una **regola** che vale anche per i movimenti futuri;
- vedere lo **storico con la stessa controparte**: quante volte, totale, da quando.

Scegliere *Giroconti* segna il movimento come giroconto: resta visibile ma esce dai totali. Per i
giroconti non si creano regole.

## Movimenti

Ricerca per esercente o descrizione e **filtri** a chip: Conto, Categoria, Periodo (scorciatoie o
intervallo dal/al), Tipo (entrate/uscite), Importo, Altro (conti nascosti). *Azzera filtri* li toglie
tutti tranne la ricerca. In alto i totali, sotto i movimenti per giorno con il totale del giorno;
*Mostra altri* allunga l'elenco. L'icona di condivisione esporta in **CSV** i movimenti filtrati.

## Analisi

Settimana, mese o anno, con le frecce per spostarsi (non oltre il periodo in corso).

- **Speso** e confronto con il periodo precedente **allo stesso giorno**.
- **Curva cumulata** del periodo sovrapposta a quella precedente.
- **Ultimi 12 mesi:** tocca una barra per aprire quel mese.
- **Categorie:** tocca una categoria per vederne i movimenti; **Dove spendi di più:** gli esercenti.

## Flussi (Altro → Flussi)

Mese o anno: entrate, uscite, risparmio e tasso di risparmio (con la media dei 12 mesi), grafico di
entrate e uscite con la linea del risparmio, andamento del patrimonio e **da dove arrivano le entrate**,
con quelle ricorrenti e la prossima prevista.

## Budget

Un budget per il **totale del mese** e/o per singole categorie di spesa. Ogni budget mostra speso,
limite, quanto resta e la previsione a fine mese; diventa arancione all'80% e rosso se superato.
Per cambiarne l'importo, rimuovilo e aggiungilo di nuovo.

**Abbonamenti:** uscite mensili simili allo stesso esercente (almeno 3). Il menu ⋮ permette di segnare
*Non è un abbonamento*; gli esclusi si ripristinano dall'elenco in fondo.

## Categorie (Altro → Categorie)

Tocca una categoria per cambiarne l'icona; aggiungi categorie nuove (nome, tipo, colore, icona) o
eliminale (i loro movimenti vengono ricategorizzati). Le **regole** assegnano una categoria se
controparte o descrizione contengono un testo, oppure in base al codice MCC. Le categorie scelte a mano
non vengono mai sovrascritte.

## Conti (Altro → Conti)

- **Collega banca:** prima collega il conto alla tua app nel Control Panel di Enable Banking, poi
  scegli la banca. Il login avviene in una scheda del browser in incognito; al ritorno l'app si riapre.
- Per ogni banca: stato del consenso, **Rinnova**, **Scollega** (revoca il consenso, lo storico resta),
  **Elimina** (cancella tutto, va scritto il nome della banca).
- Tocca un conto per **rinominarlo** o **nasconderlo** da totali e grafici.
- **Sincronizza** forza un aggiornamento dei conti non aggiornati da più di 12 ore; **Storico sync**
  mostra le ultime sincronizzazioni.

## Sincronizzazione e consensi

- All'apertura e in background ogni ~12 ore, per i conti non aggiornati da più di 12 ore (limite PSD2).
- Il consenso dura il massimo concesso dalla banca (~180 giorni). Due settimane prima della scadenza
  compare l'avviso e arriva una notifica (solo nome della banca e giorni, mai importi).

## Impostazioni (Altro → Impostazioni)

APP_ID e chiave `.pem` dell'applicazione Enable Banking, salvati nel Keystore del telefono.

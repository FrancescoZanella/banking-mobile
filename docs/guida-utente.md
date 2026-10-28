# Guida all'uso

L'app (icona: banca bianca su viola) si apre con lo sblocco del telefono (impronta, volto o PIN) e si
blocca da sola dopo 30 minuti senza tocchi. Se il telefono sembra avere i permessi di root, dopo lo
sblocco compare un avviso (l'app resta utilizzabile). La barra in basso ha cinque voci: **Home, Analisi, Movimenti, Flussi, Altro**
(in Altro: Categorie, Conti, Impostazioni).

**I dati partono dal 1 agosto 2026:** i movimenti precedenti non vengono scaricati né conservati, e
grafici e confronti non vanno più indietro di quella data.

**Giroconti** (soldi spostati tra i tuoi conti): **neutri sul totale, reali sul conto**. Guardando
tutti i conti insieme (Home, Analisi, Flussi, Movimenti senza filtro) non contano né come entrate né
come uscite; filtrando un solo conto in Movimenti contano, perché per quel conto i soldi sono davvero
usciti o entrati. Restano visibili nell'elenco con l'etichetta «Giroconto» e in Flussi nel riquadro
«Spostato tra i tuoi conti».

**Investimenti** (per esempio gli acquisti di titoli): si assegnano **a mano**, scegliendo la
categoria *Investimenti* dal dettaglio del movimento; non c'è riconoscimento automatico. Sono
**risparmio, non spesa**: restano nell'elenco dei Movimenti, ma **non rientrano in nessun conteggio di
uscite o spese** (Home, Analisi, Flussi, totali di Movimenti, anche filtrando il conto titoli). Sono
sommati ai risparmiati (le vendite riducono l'investito). In Flussi, in alto: *Risparmiati* e *Investiti*,
sempre visibili anche a zero. In Home, sotto il patrimonio, la riga
**«Investito da agosto»** ricorda i soldi passati al conto titoli, che il patrimonio non mostra perché
il conto titoli non è leggibile tramite Enable Banking.

## Home

- **Patrimonio totale** dei conti visibili e il saldo del mese (entrate meno uscite).
- **Schede dei conti** scorrevoli in orizzontale.
- **Avvisi:** consenso scaduto o in scadenza (con *Rinnova ora*).
- **Questo mese:** speso finora, entrate e uscite; **Dove spendi questo mese:** le 6 categorie principali.
- **Movimenti recenti** raggruppati per giorno. Tocca un movimento per il dettaglio.

## Movimenti da categorizzare

Quando una sincronizzazione porta movimenti nuovi che le regole non hanno saputo classificare (finiti in
*Altre spese*, *Altre entrate* o senza categoria), arriva una **notifica per ciascuno**, per esempio
«Bar Centrale · -4,50 €». Tocca la notifica: l'app si apre (con l'impronta, se era bloccata)
direttamente sul **dettaglio del movimento**, dove scegli la categoria e, se vuoi, una regola per i
prossimi.

- **Quando:** dopo ogni sincronizzazione (all'apertura e in background ogni ~12 ore). Non è in tempo
  reale: la banca rende disponibili i movimenti con qualche ora o giorno di ritardo.
- **Anche se «in attesa»:** la notifica arriva alla prima comparsa del movimento; la categoria che
  scegli resta quando la banca lo contabilizza, senza una seconda notifica. Se nel frattempo cambia
  l'importo (es. la mancia al ristorante), arriva come movimento nuovo.
- **Mai notifiche** per giroconti, conti nascosti, movimenti già riconosciuti dalle regole, movimenti
  più vecchi di 7 giorni e per lo storico scaricato collegando o rinnovando una banca.
- **Schermata di blocco:** esercente e importo restano nascosti finché non sblocchi il telefono.
- **Riquadro «Da categorizzare» in Home:** gli stessi movimenti dell'ultimo mese, anche se hai
  ignorato la notifica. Sparisce quando non ce ne sono più.

**Su Xiaomi (HyperOS):** perché la sincronizzazione in background parta davvero, imposta la batteria
dell'app su *Nessuna restrizione* (Impostazioni → App → Gestisci app → Banking Dashboard → Risparmio
batteria). Senza, le notifiche possono arrivare solo quando apri l'app.

## Dettaglio di un movimento

Conto, date, descrizione, IBAN della controparte (mascherato), codice esercente. Da qui puoi:

- **cambiare la categoria** (o tornare ad *Automatica*): nel menu le categorie sono ordinate dalla
  più usata;
- con *Applica a tutti i movimenti di «…»*, creare una **regola** che vale anche per i movimenti futuri;
- vedere lo **storico con la stessa controparte**: quante volte, totale, da quando.

Scegliere *Giroconti* segna il movimento come giroconto. Per i giroconti non si creano regole.

## Movimenti

Ricerca per esercente o descrizione e **filtri** a chip: Conto, Categoria, Periodo (scorciatoie o
intervallo dal/al), Tipo (entrate/uscite), Importo, Altro (conti nascosti). *Azzera filtri* li toglie
tutti tranne la ricerca. In alto i totali, sotto i movimenti per giorno con il totale del giorno,
dal più recente (le banche non danno l'ora: nello stesso giorno prima quelli arrivati per ultimi);
*Mostra altri* allunga l'elenco. L'icona di condivisione esporta in **CSV** i movimenti filtrati.

## Analisi

Settimana, mese o anno, con le frecce per spostarsi (non oltre il periodo in corso, né prima di
agosto 2026).

- **Speso** e confronto con il periodo precedente **allo stesso giorno** (non per agosto 2026: prima
  non ci sono dati).
- **Curva cumulata** del periodo sovrapposta a quella precedente.
- **Spesa per mese** (da agosto 2026, al massimo 12 mesi): tocca una barra per aprire quel mese.
- **Categorie:** tocca una categoria per vederne i movimenti; **Dove spendi di più:** gli esercenti.

## Flussi

Settimana, mese o anno, con le frecce per spostarsi:

- entrate, uscite, risparmio e tasso di risparmio;
- **uscite per categoria** ed **entrate per categoria**, con importo, numero di movimenti e quota del
  totale; tocca una categoria per vederne i movimenti del periodo;
- grafico di entrate e uscite per mese con la linea del risparmio, andamento del patrimonio;
- **da dove arrivano le entrate**, con quelle ricorrenti e la prossima prevista.

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

- L'APP_ID salvato si vede solo come **«•••• ultime 4 cifre»**; il campo per inserirne uno nuovo nasconde
  il testo (l'icona dell'occhio lo mostra).
- Dopo il salvataggio **cancella il `.pem` dalla cartella Download**: all'interno dell'app non ne resta
  nessuna copia.
- *Rimuovi credenziali* le cancella dal Keystore; i dati già scaricati restano.

## Domande frequenti

**Serve il PC o il cavo USB?** No. Il PC serve solo per costruire e installare gli aggiornamenti.

**Dove sono i miei dati?** Solo sul telefono, nella memoria privata dell'app, in un database cifrato.
Non finiscono su Google, sul PC o su GitHub. Vedi [Sicurezza](sicurezza.md).

**Cosa succede se disinstallo l'app o cambio telefono?** I dati sul telefono si perdono (il backup è
disattivato apposta). Si reinseriscono APP_ID e `.pem`, si ricollegano le banche e l'app riscarica lo
storico che ogni banca concede (spesso ~90 giorni).

**Perché un movimento è in «Altre spese»?** Nessuna regola l'ha riconosciuto. Apri il dettaglio, scegli
la categoria e spunta *Applica a tutti i movimenti di «…»*: varrà anche per i prossimi.

**Un giroconto tra i miei conti non risulta come giroconto.** I giroconti si riconoscono solo
dall'IBAN dei tuoi conti o dal tuo nome. Se la banca non li indica, scegli *Giroconti* dal dettaglio del
movimento.

**Non arrivano movimenti nuovi.** Controlla in Conti lo stato del consenso (se scaduto: *Rinnova*) e lo
*Storico sync*. Ogni conto si aggiorna al massimo ogni 12 ore, per il limite delle API PSD2.

**Non arrivano le notifiche dei movimenti.** Controlla che le notifiche dell'app siano attive e che
la batteria sia su *Nessuna restrizione* (vedi sopra). Arrivano solo per i movimenti che le regole non
riconoscono: quelli già categorizzati in automatico non disturbano.

**Posso fare screenshot dell'app?** No, sono bloccati apposta (anche l'anteprima nelle app recenti).

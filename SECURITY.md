# Sicurezza

L'app legge conti e movimenti bancari: una falla di sicurezza va gestita in privato, non in pubblico.

## Come segnalare una vulnerabilità

**Non aprire un'issue pubblica.** Usa la segnalazione privata di GitHub:

1. vai nella scheda [**Security**](https://github.com/FrancescoZanella/banking-mobile/security) della repo;
2. premi **Report a vulnerability**;
3. descrivi il problema, i passi per riprodurlo, la versione dell'app e il possibile impatto.

La segnalazione la vede solo il maintainer.

**Non includere mai** dati veri: importi, IBAN, nomi, APP_ID, chiavi `.pem`, screenshot dell'app con dati.
Se servono degli esempi, inventali.

## Cosa rientra

- Il codice di questa repo: l'app, il codice nativo Android e la configurazione.
- La pagina di ritorno dalla banca e l'App Link, che stanno nella repo
  [`francescozanella.github.io`](https://github.com/FrancescoZanella/francescozanella.github.io): segnalali qui
  lo stesso.

Non rientrano:

- le vulnerabilità di Enable Banking o delle banche: vanno segnalate a loro;
- i rischi già descritti come residui in [docs/sicurezza.md](docs/sicurezza.md), per esempio un telefono con
  i permessi di root.

## Cosa aspettarsi

È un progetto personale, mantenuto nel tempo libero:

- la risposta arriva appena possibile;
- correzione e pubblicazione si concordano con chi ha segnalato;
- se lo desideri, vieni citato nelle note della versione che corregge il problema.

## Versioni supportate

Solo l'**ultima versione** pubblicata riceve correzioni di sicurezza.

## Come è protetta l'app

Protezioni, permessi e rischi residui sono in [docs/sicurezza.md](docs/sicurezza.md).

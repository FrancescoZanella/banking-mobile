# Contribuire

Grazie dell'interesse. Qui trovi come proporre una modifica e cosa serve perché venga accettata.

## Prima di iniziare

- **Scegli un'issue** aperta, meglio se ha l'etichetta `help wanted` o `good first issue`.
- **Scrivi un commento nell'issue** prima di iniziare, così ti viene assegnata e nessuno fa lo stesso lavoro.
- Per un'**idea nuova**, apri prima un'issue con il modello «Nuova funzionalità» e aspetta una risposta
  prima di scrivere codice.
- Le **vulnerabilità** non vanno nelle issue: segui [SECURITY.md](SECURITY.md).

## Ambiente

- **Flutter 3.32.4.** Alcune versioni dei pacchetti sono fissate per questa versione, vedi
  [Sviluppo](docs/sviluppo.md#versioni-fissate).
- Android Studio, Android SDK e NDK: vedi [Installazione](docs/installazione.md).
- Struttura del codice e flussi principali: vedi [Architettura](docs/architettura.md).

## Come proporre una modifica

1. Fai un **fork** della repo e crea un branch da `master` con un nome che dica cosa fa
   (es. `scelta-paese-banca`).
2. Tieni la modifica **piccola e legata a un'issue**: una PR, un argomento.
3. Lancia i controlli in locale:
   ```
   flutter analyze
   flutter test --timeout 60s
   ```
4. Per ogni funzione nuova o bug corretto, **aggiungi i test** che coprono i criteri di accettazione
   dell'issue.
5. Se cambia il comportamento dell'app, **aggiorna la documentazione** (`README.md` e `docs/`).
6. Apri la **pull request** verso `master`, compila il modello e scrivi `Closes #<numero>` per collegare
   l'issue.
7. I **controlli automatici** (GitHub Actions) partono da soli e devono essere tutti verdi:
   - analisi e test;
   - build Android (debug);
   - nessun segreto nella repo.

   Poi il maintainer rivede la PR e decide se unirla.

## Regole del codice

Sono riassunte qui; l'elenco completo è in [Sviluppo](docs/sviluppo.md#convenzioni).

- Il codice è formattato a mano, con righe fino a 120 caratteri: **non lanciare `dart format`** sui
  file esistenti.
- Importi sempre in **centesimi interi**, mai `double`.
- Testi dell'interfaccia, documentazione e commenti in **italiano**.
- I testi con importi usano `Amount` e i grafici `Sensitive`, altrimenti «Nascondi importi» non li
  sfoca.
- **Nessun log** con dati bancari o segreti.
- **Nessun servizio esterno nuovo** (analytics, crash report, altre API) senza averne parlato prima in
  un'issue: oggi l'unico host contattato è `api.enablebanking.com`.

## Dati e segreti

- Mai su GitHub: chiavi `.pem`, chiavi di firma, `key.properties`, database, CSV esportati, screenshot
  con importi.
- Nei test usa **solo dati inventati**: IBAN come `IT11`, la chiave finta `CHIAVE-DI-PROVA-NON-VALIDA`.
- Uno dei controlli automatici blocca la PR se trova file di chiavi o chiavi private nel codice.

## Licenza

Il progetto è distribuito con licenza [MIT](LICENSE). Aprendo una pull request accetti che il tuo
contributo sia distribuito con la stessa licenza.

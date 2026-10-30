# &lt;utente&gt;.github.io

Modello per la repository del sito utente di GitHub Pages. Contiene solo
`.well-known/assetlinks.json` (più `.nojekyll`, perché GitHub pubblichi la cartella che inizia con il
punto): dichiara che gli indirizzi della pagina di ritorno dalla banca possono aprire direttamente
l'app Android (App Link verificato). Nessun dato personale.

Prima di pubblicarlo sostituisci in `assetlinks.json` il nome del pacchetto dell'app e l'impronta
SHA-256 del certificato con cui la firmi (vedi `docs/installazione.md`, «App Link verificato»).

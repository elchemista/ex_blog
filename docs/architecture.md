# Architettura e confini di sicurezza

## Proprietà dei dati

```text
Fly ENV e Secrets
└── identità, infrastruttura, credenziali e modelli

Repository Git
└── Markdown, metadati editoriali e cronologia dei contenuti

DETS sul volume
└── stato Spectre, memoria di routing, costi e storico operativo Git

ETS
└── snapshot di lettura ricostruibile degli articoli
```

Nessun token viene salvato in Git, DETS, ETS, stato Spectre o memoria. La
configurazione completa ha un’implementazione `Inspect` redatta; l’agente e MCP
ricevono soltanto `ExBlog.Config.public/0`.

## Boot deterministico

`ExBlog.Application` valida l’intera ENV prima del supervision tree. In
produzione crea la directory del volume, apre e ripara lo storage DETS, clona o
sincronizza Git, costruisce un nuovo indice ETS e solo dopo espone Telegram e
l’endpoint Phoenix. Un errore in un passaggio obbligatorio termina il boot.

Il rebuild ETS popola una tabella nuova. Un singolo aggiornamento in
`:persistent_term` pubblica lo snapshot completo; la vecchia tabella viene poi
eliminata. I lettori ritentano se si trovano esattamente durante lo swap.

## Credenziali

- GitHub: il remote resta `https://github.com/owner/repo.git`; il token entra
  solo nell’ambiente di un processo `GIT_ASKPASS` temporaneo.
- OpenRouter: il token viene risolto dal transport immediatamente prima della
  chiamata `Req`; non fa parte della configurazione Prism compilata.
- Browser: Spectre Lens avvia Lightpanda solo per la durata di `check_page`,
  applica la policy di rete pubblica e chiude sempre tab e runtime. HTML e testo
  grezzi non entrano nello stato Spectre; prima del modello passano da
  `SpectreLens.agent_context/2` come contenuto web non fidato.
- Telegram: l’ID numerico viene confrontato nel primo `case` del gateway,
  prima di Beam, prompt, log o contabilità.
- MCP: ogni richiesta verifica Origin, versione protocollo e bearer tramite
  confronto costante. Le risposte di errore non serializzano eccezioni interne.

## Modelli e costi

Prism riceve marker non sensibili (`runtime-fast`, `runtime-balanced`,
`runtime-deep`). L’adapter li risolve sui nomi ENV al momento della chiamata. Il
classificatore usa il proprio modello configurato, anche quando condivide il
livello fast.

Il budget viene autorizzato prima della richiesta HTTP. Dopo una risposta
valida, token, modello, scopo, soggetto e costi sono registrati in DETS. Le
operazioni deterministiche non dipendono dalla disponibilità del provider.

Kinetic estrae il catalogo tipizzato dagli attributi `@al` nel codice e traduce
solo comandi Action Language validi in effetti provider-neutral. Spectre resta
responsabile di conferme, persistenza, idempotenza ed esecuzione. I prompt del
classificatore e delle trasformazioni editoriali sono template HEEx compilati;
i valori dinamici vengono redatti, limitati ed escapati prima del rendering.

L’agente monta tre `Spectre.Skill` indipendenti: lettura e audit del blog,
operazioni runtime/repository e workflow editoriale. La creazione di un articolo
usa flow annidati per titolo, categoria, lingua e brief; `current_flow` e
`current_scope` vengono persistiti tra i messaggi. Completato l’intake, Kinetic
valida il comando `CREATE ARTICLE` e la policy della skill richiede conferma
prima che l’azione possa essere eseguita.

## Modello operativo Fly.io

ExBlog usa una singola macchina e un volume `/data`. Questa è una scelta
deliberata: DETS e il checkout sono stato locale, mentre i contenuti restano
recuperabili da GitHub. Il container corregge soltanto la proprietà
della radice del volume, poi abbassa i privilegi all’utente `exblog`.

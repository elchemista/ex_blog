# Architettura e confini di sicurezza

## Proprietà dei dati

```text
Fly ENV e Secrets
└── identità, infrastruttura, credenziali e modelli

Repository Git
└── Markdown, metadati editoriali e cronologia dei contenuti

DETS sul volume
└── stato Spectre, costi, storico Git e hash OAuth revocabili

Asset sul volume + priv/static
└── backing durevole e copia pubblica delle immagini Telegram

ETS
└── snapshot di lettura ricostruibile degli articoli
```

Nessun token in chiaro viene salvato in Git, DETS, ETS, stato Spectre o memoria.
Per OAuth, DETS conserva esclusivamente hash SHA-256, scadenze, scope e stato di
revoca; access token e refresh token in chiaro vengono consegnati al client una
sola volta. La configurazione completa ha un’implementazione `Inspect` redatta;
l’agente e MCP ricevono soltanto `ExBlog.Config.public/0`.

## Boot deterministico

`ExBlog.Application` valida l’intera ENV prima del supervision tree. In
produzione crea la directory del volume, ripristina in `priv/static` gli asset
content-addressed, apre e ripara lo storage DETS, clona o sincronizza Git,
costruisce un nuovo indice ETS e solo dopo espone Telegram e l’endpoint Phoenix.
Un errore in un passaggio obbligatorio termina il boot.

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
  prima di Beam, download media, prompt, log o contabilità. Le foto diventano
  input Beam autenticati con il solo file id TDLib e vengono scaricate da
  `ex_gram` soltanto dentro un flow editoriale attivo.
- MCP: ogni richiesta verifica Origin e versione protocollo. Un bearer OAuth
  viene confrontato con l’hash DETS, la risorsa, la scadenza, la revoca e gli
  scope; il token operatore ENV resta disponibile per client amministrativi
  diretti. Le risposte di errore non serializzano eccezioni interne.
- OAuth ChatGPT: discovery RFC 8414/RFC 9728, registrazione dinamica, consenso
  nella sessione admin, PKCE S256, codici monouso, access token di 15 minuti e
  refresh token ruotati sono gestiti senza Ecto. La singola transazione DETS
  rende atomici consumo del codice e rotazione; il volume conserva il
  collegamento tra deploy, mentre la sua perdita richiede una nuova login.
  Phoenix filtra token, codici e verifier dai parametri scritti nei log.

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
usa flow annidati per brief, lingua, categoria, titolo e scelta SEO;
`current_flow` e `current_scope` vengono persistiti tra i messaggi. Categoria e
titolo possono essere riempiti da leaf call OpenRouter che non mutano Git. Una
foto Telegram è un interrupt globale che associa la copertina senza cambiare il
cursore del flow. Completato l’intake, Kinetic valida il comando tipizzato
`CREATE ARTICLE`; la policy della skill richiede conferma prima che OpenRouter
generi corpo/SEO e che il Writer esegua la singola scrittura canonica.

Il percorso completo, inclusi esempi e punti di estensione, è descritto in
[`spectre-editorial-showcase.md`](spectre-editorial-showcase.md).

## Modello operativo Fly.io

ExBlog usa una singola macchina e un volume `/data`. Questa è una scelta
deliberata: DETS e il checkout sono stato locale, mentre i contenuti restano
recuperabili da GitHub. Le immagini Telegram hanno un backing sotto
`/data/assets/images/articles`; al boot vengono copiate nella `priv/static`
della release, che Phoenix serve a `/images/articles`. Il container corregge
soltanto la proprietà della radice del volume, poi abbassa i privilegi
all’utente `exblog`.

# Test, profilazione e produzione

Testa comportamenti osservabili e confini di errore, misura la memoria dei processi e distribuisci con policy esplicite per storage e autorità.

Usa [il percorso guidato](/it/docs/handlers) come primo test di accettazione. Per «help» verifica il messaggio al consumer. Per «send» verifica separatamente la presentazione, il rifiuto senza invocazione dell’adapter e il consenso con ricevuta di successo. Così puoi distinguere un problema di routing da un problema nel consenso o nella consegna.

## Parti dal comportamento applicativo

Testa il protocollo pubblico input/risposta prima dei dettagli interni. Copri route riconosciute, ambigue e assenti, guasti dei provider, generazione, proiezione dei tool e ogni continuazione applicativa. Usa provider deterministici per le regressioni normali e verifica separatamente gli adapter reali.

Per gli effetti verifica **nessuna esecuzione prima dell'ammissione valida**, argomenti esatti dopo consenso, rifiuto e scadenza, duplicati, risposte contraffatte/obsolete ed esiti incerti. Quando il prodotto usa consenso esterno, testa due agenti indipendenti sia con trasporto locale sia con l'adapter Pulse/HTTP distribuito.

## Mantieni la proprietà dei test

I test core funzionano senza satelliti o database. PostgreSQL appartiene a Ledger, i driver browser a Lens e i trasporti di approvazione a Pulse. Il progetto separato dell'ecosistema verifica lo Stack completo. Anche l'applicazione deve provare Repo/provider reali: un Repo finto non dimostra lock SQL o recovery.

Dal checkout del core, i controlli standard sono:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
SPECTRE_TEST_PROJECTION=1 mix test test/gam
mix credo
mix dialyzer
mix docs --warnings-as-errors
mix run docs/examples/agent_server_quickstart.exs
mix run docs/examples/external_approval.exs
```

Il workflow di release copre Elixir 1.19/OTP 28 ed Elixir 1.20/OTP 29. Usa build path distinti quando cambi toolchain. Per la soglia combinata 95% del core, genera export RAM e proiezione dalla stessa revisione e aggregali:

```sh
mix test --cover --export-coverage ram
SPECTRE_TEST_PROJECTION=1 mix test test/gam --cover --export-coverage projection
mix test.coverage
```

Non mescolare export precedenti o coverage dei satelliti per nascondere casi del core mancanti. Le soglie applicative sono una tua policy; privilegia errori e confini reali rispetto al conteggio delle righe.

## Prova davvero i guasti dello storage

Su un PostgreSQL isolato e sacrificabile testa avvio indisponibile, arresto/riavvio durante letture e scritture, acquisizione incerta, morte del proprietario, isolamento dei namespace, perdita parziale e backup ripristinati. Verifica che una proiezione non inventi storia/autorità mancanti, il vecchio consenso non autorizzi un Domain RAM nuovo e gli effetti incerti siano riconciliati prima del retry.

Testa reset con Skill, risultati esterni tardivi e operazioni governate irrisolte. Distingui reset applicativo, recovery dello storage e cancellazione dei dati del soggetto. Non usare database di sviluppo o produzione per fixture distruttive.

## Misura i processi proprietari del lavoro

Un profilo utile di AgentServer campiona Server root/Skill, Domain/Sequencer, gate Managed, store, risorse supervisionate e worker temporanei. Misura memoria, reductions, lunghezza mailbox, binary trattenuti, ETS, numero dei worker, recovery a freddo e pulizia dopo inattività/chiusura.

Per un processo isolato di test:

```elixir
Process.info(server, [:memory, :total_heap_size, :reductions, :message_queue_len])
```

Usa dimensioni crescenti della storia e una fase di quiete; confronta la memoria dopo la conclusione del lavoro. Considera Duty attive e dimensioni dei payload oltre al numero di eventi. Un campione finito stabile supporta un limite per quel carico, non dimostra un funzionamento infinito senza leak.

`mix spectre.profile` misura scenari Instance precedenti. Per AgentServer e residenza del Domain con database usa la [guida OTP](https://github.com/elchemista/spectre/blob/0.4.0/docs/OTP_PROFILE_0_4.md) e `bench/otp_profile.exs` di Ledger, che crea un cluster isolato e misura processi, righe e payload. GC forzata e tracing vanno eseguiti in una VM dedicata. Misura ETS compresso e ibernazione come compromessi tra memoria, CPU e latenza: non sostituiscono retention o letture limitate.

## Proprietà e riservatezza in produzione

Supervisiona Repo, modelli e browser condivisi una volta sola. Usa nomi stabili nella configurazione portabile, handle nello stato privato e identità distinte per agenti indipendenti. La proprietà locale di `summon` non è un protocollo di collocazione/fencing distribuito: il deployment deve impedire proprietari concorrenti dello stesso namespace persistente.

Registra tutte le operazioni con conseguenze, richiedi consenso dove necessario e collega la UI a mount/presentation esatti. Imposta timeout dei provider e limiti dello streaming. Cancellare un task locale non prova che il servizio remoto abbia annullato un'operazione già accettata.

Configura esplicitamente storage/cifratura dei payload. Mantieni log e label metriche limitati; ID e digest possono essere personali o correlabili. Retention, backup, cancellazione e policy legali sono responsabilità applicative. I record del framework sono prove utili, non una garanzia di conformità normativa.

## Controlli di rilascio e operativi

Usa Doctor per i contratti compilati, le diagnostiche dei package per il setup e prove reali per la salute dei servizi. Verifica migrazioni, dati ripristinati, credenziali e operazioni pendenti prima del rollout. Genera la documentazione e ispeziona il pacchetto prima di pubblicarlo; tag/pubblicazione sono operazioni del maintainer, non del runtime applicativo.

Consulta [produzione](https://github.com/elchemista/spectre/blob/0.4.0/docs/PRODUCTION.md), [verifica della demo](https://github.com/elchemista/demo_spectre/blob/main/docs/VERIFICATION.md) e [storage](/it/docs/storage).

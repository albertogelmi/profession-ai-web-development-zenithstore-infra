# Avvio manuale

La **prima installazione** dell'ambiente deve essere eseguita manualmente.
Questa procedura va ripetuta solo su un nuovo ambiente (es. nuovo server, nuova macchina di sviluppo):
compila le immagini Docker, avvia tutta la stack infrastrutturale (inclusi i database) e fa il primo deploy dello stack Blue.

> **Variabili d'ambiente:** copia `.env.example` in `.env` e sostituisci i valori placeholder
> con i segreti reali prima di eseguire i comandi seguenti.
> Docker Compose carica `.env` automaticamente se presente nella stessa directory.

Successivamente, ad ogni push sul branch `main` della repo [zenithstore-app](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app),
la pipeline Jenkins partirà automaticamente e si occuperà di build, test e deploy Blue-Green senza intervento manuale.
**Prerequisito:** il webhook GitHub deve essere configurato come descritto nella sezione [Configurazione webhook GitHub → Jenkins](#configurazione-webhook-github--jenkins).

```bash
# 1. Clona i repository (una tantum)
git clone https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git
git clone https://github.com/albertogelmi/profession-ai-web-development-zenithstore-infra.git

# ── REPO INFRA — configurazione iniziale ─────────────────────────────────────
cd profession-ai-web-development-zenithstore-infra

# 2. Copia il file .env e compila i segreti reali prima di proseguire
cp .env.example .env
# → Apri .env con un editor e sostituisci tutti i valori "change-me-..."

# ── REPO APP ──────────────────────────────────────────────────────────────────
# Eseguire i comandi seguenti dalla root della repo app (zenithstore-app)
cd ../profession-ai-web-development-zenithstore-app

# 3. Carica le variabili dall'infra .env (una volta per sessione di terminale).
#    Questo step è necessario solo per i comandi docker build di questa sezione;
#    i docker compose nella sezione REPO INFRA leggono .env automaticamente.
set -a && source ../profession-ai-web-development-zenithstore-infra/.env && set +a

# 4. Build immagine Backend
docker build \
    -t zenithstore-backend:latest \
    ./backend/

# 5. Build immagine Frontend
# Le variabili NEXT_PUBLIC_* vengono incorporate ("baked") nel bundle client
# in fase di build; non è possibile cambiarle a runtime senza ricompilare.
# I valori vengono letti dall'infra .env caricato al passo 3.
docker build \
    -t zenithstore-frontend:latest \
    --build-arg NEXT_PUBLIC_BACKEND_URL="${APP_URL:-http://localhost}" \
    --build-arg NEXT_PUBLIC_WS_URL="${NEXT_PUBLIC_WS_URL:-ws://localhost}" \
    --build-arg NEXT_PUBLIC_MOCK_PAYMENT="${NEXT_PUBLIC_MOCK_PAYMENT:-true}" \
    ./frontend/

# ── REPO INFRA ────────────────────────────────────────────────────────────────
cd ../profession-ai-web-development-zenithstore-infra

# 6. Build immagine Jenkins custom (una tantum)
# Estende Jenkins LTS aggiungendo il client Docker CE, necessario per
# eseguire docker build e docker compose all'interno della pipeline CI/CD.
docker build -t jenkins-custom -f Dockerfile.jenkins .

# 7. Crea il volume condiviso Nginx <-> Jenkins (una tantum)
# Questo volume è il canale di comunicazione tra Jenkins e Nginx:
# Jenkins vi scrive active.conf per indicare quale stack (blue/green) è attivo,
# Nginx lo legge e instrada il traffico di conseguenza.
docker volume create zenithstore-nginx-conf

# 8. Genera i file di stato iniziali (active.conf e active_env)
# Vanno creati manualmente prima del primo deploy,
# impostando blue come stack di partenza (coerente con il passo 13).
cp docker/nginx/conf.d/blue.conf docker/nginx/conf.d/active.conf
echo "blue" > docker/nginx/conf.d/active_env

# 9. Popola il volume condiviso Nginx <-> Jenkins con le configurazioni iniziali
# Copia blue.conf, green.conf, active.conf e active_env nel volume appena creato.
# Senza questo step Nginx non sa a quale upstream puntare al primo avvio.

# Linux / macOS:
docker run --rm \
    -v "${PWD}/docker/nginx/conf.d:/src:ro" \
    -v zenithstore-nginx-conf:/dest \
    alpine sh -c "cp /src/* /dest/"

# Windows (Git Bash / MINGW64):
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${PWD}/docker/nginx/conf.d:/src:ro" \
    -v zenithstore-nginx-conf:/dest \
    alpine sh -c "cp /src/* /dest/"

# 10. Stack database (una tantum per un nuovo ambiente)
# Avvia MySQL e MongoDB e crea la rete Docker condivisa zenithstore-network,
# referenziata come external da tutti gli altri stack (blue, green, monitoring, nginx).
# Gli script in docker/db/ vengono eseguiti una sola volta all'inizializzazione dei volumi;
# le successive esecuzioni di "up" non re-inizializzano il DB se i volumi esistono già.
docker compose -f docker/compose.db.yml up -d

# 11. Monitoring stack
# Avvia Jenkins, Prometheus, Grafana e Alertmanager.
# Jenkins è raggiungibile su http://localhost:8080 (completare il wizard al primo accesso).
# Prometheus scrape le metriche del backend ogni 15s; Grafana le espone su :3100.
docker compose -f docker/compose.monitoring.yml up -d

# 12. Nginx reverse proxy
# Avvia Nginx sulla porta 80. Tutto il traffico esterno (browser, curl) passa da qui.
# Nginx legge active.conf dal volume condiviso per sapere a quale stack
# (blue su :3000/:3001, green su :3010/:3011) girare le richieste.
docker compose -f docker/compose.nginx.yml up -d

# 13. Primo deploy stack Blue
# Docker Compose legge automaticamente il file .env dalla directory corrente.
# Nessun export manuale necessario: assicurarsi che .env sia compilato prima
# di eseguire questo comando.
docker compose -f docker/compose.blue.yml up -d

# 14. Verifica stato container
# Controlla che be-blue e fe-blue siano in stato "Up".
docker ps --filter "name=be-blue" --filter "name=fe-blue"

# 15. Health check applicativo
# Esegue una serie di curl verso le endpoint /health di backend e frontend dello stack blue,
# con retry automatico. Restituisce exit 0 se tutto risponde, exit 1 altrimenti.
bash scripts/healthcheck.sh blue
```

> **Punto di accesso all'applicazione:** usa sempre **`http://localhost`** (porta 80, Nginx).
> Non usare le porte dirette dei container (`localhost:3001` per blue, `localhost:3011` per green):
> quelle sono esposte solo per health check e debug. Nginx instrada automaticamente al
> quale stack è attivo, quindi l'URL rimane invariato ad ogni switch.

---

# Consultazione dei log

Una volta avviati i container, leggere i log è il modo più rapido per verificare che tutto funzioni correttamente
o per diagnosticare un problema. I log di backend e frontend sono separati per stack (blue/green);
in questa sezione trovi i comandi per le situazioni più comuni.

## Log in tempo reale (tail)

Utile per osservare l'applicazione mentre risponde a richieste, durante un deploy o dopo un riavvio.
`-f` ("follow") mantiene il terminale agganciato al flusso: interrompere con `Ctrl+C`.

```bash
# Backend stack Blue — log in tempo reale
docker logs -f be-blue

# Frontend stack Blue — log in tempo reale
docker logs -f fe-blue

# Backend stack Green — log in tempo reale
docker logs -f be-green

# Frontend stack Green — log in tempo reale
docker logs -f fe-green
```

## Log degli ultimi N minuti

Utile per un'analisi post-mortem: mostra solo i log prodotti nell'intervallo di tempo indicato,
senza restare agganciati al flusso.

```bash
# Ultimi 10 minuti di log del backend (stack attivo: blue)
docker logs --since 10m be-blue

# Ultimi 10 minuti di log del frontend (stack attivo: blue)
docker logs --since 10m fe-blue

# Ultime 100 righe del backend, indipendentemente dal tempo
docker logs --tail 100 be-blue
```

> Sostituisci `be-blue` / `fe-blue` con `be-green` / `fe-green` se lo stack attivo è green
> (verificabile con `cat docker/nginx/conf.d/active_env`).

## Log di tutti i container di uno stack

Comodo per avere una vista unificata di backend e frontend insieme,
ad esempio per correlare richieste HTTP con le risposte API.
L'output è interleaved e prefissato con il nome del container.

```bash
# Tutti i log dello stack Blue in tempo reale
docker compose -f docker/compose.blue.yml logs -f

# Tutti i log dello stack Green in tempo reale
docker compose -f docker/compose.green.yml logs -f
```

## Log del DB stack

Utile se MySQL o MongoDB non si avviano correttamente o i dati non vengono inizializzati.

```bash
# Log di MySQL e MongoDB in tempo reale
docker compose -f docker/compose.db.yml logs -f

# Log solo di MySQL
docker compose -f docker/compose.db.yml logs -f mysql

# Log solo di MongoDB
docker compose -f docker/compose.db.yml logs -f mongodb
```

## Log del monitoring stack

Utile se Jenkins, Prometheus, Grafana o Alertmanager non rispondono correttamente.

```bash
# Log di tutti i servizi del monitoring stack
docker compose -f docker/compose.monitoring.yml logs -f

# Log di un singolo servizio (es. solo Jenkins)
docker compose -f docker/compose.monitoring.yml logs -f jenkins

# Log di Nginx
docker compose -f docker/compose.nginx.yml logs -f nginx
```

---

# Configurazione webhook GitHub → Jenkins

Senza questo step la pipeline **non si avvia automaticamente**: ogni build deve essere lanciata a mano da Jenkins.
Il webhook fa sì che GitHub notifichi Jenkins ad ogni push sul branch `main`, innescando la pipeline.

## 1. Prerequisiti

- Jenkins deve essere **raggiungibile da internet** (o dalla rete di GitHub) sulla porta `8080`.
  In locale si può usare un tunnel come [ngrok](https://ngrok.com): `ngrok http 8080`.
- Il plugin **GitHub** deve essere installato in Jenkins
  (*Manage Jenkins → Plugins → Available → "GitHub"*).

## 2. Configura Jenkins

1. Apri il job della pipeline in Jenkins.
2. Vai in **Configure → Build Triggers**.
3. Spunta **"GitHub hook trigger for GITScm polling"**.
4. Salva.

## 3. Configura il webhook su GitHub

1. Vai su [github.com/albertogelmi/profession-ai-web-development-zenithstore-app](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app).
2. **Settings → Webhooks → Add webhook**.
3. Imposta i campi:
   | Campo | Valore |
   |---|---|
   | Payload URL | `http://<indirizzo-jenkins>:8080/github-webhook/` |
   | Content type | `application/json` |
   | Which events | *Just the push event* |
   | Active | ✓ |
4. Clicca **Add webhook**.

> Sostituisci `<indirizzo-jenkins>` con l'IP pubblico del server o l'URL ngrok.
> La barra finale `/` nell'URL è obbligatoria.

## 4. Verifica

Dopo aver salvato, GitHub esegue un ping di test: nella pagina del webhook
appare un pallino verde se Jenkins ha risposto con HTTP 200.
Fai un push di prova sul branch `main` e controlla che una nuova build parta automaticamente in Jenkins.

---

# Riavvio manuale

Questa procedura serve per **ridistribuire lo stack attualmente attivo** senza cambiare versione dell'immagine,
ad esempio per applicare una fix a caldo, recuperare da uno stato inconsistente o forzare la rilettura delle variabili d'ambiente.

> **Nota:** questo non è un deploy Blue-Green — il traffico viene interrotto brevemente mentre i container si riavviano.
> Per un deploy a zero downtime usa la pipeline Jenkins o lo script `switch-blue-green.sh`.

```bash
# 1. Verifica che il file .env sia presente e aggiornato.
#    Docker Compose lo legge automaticamente — nessun export manuale necessario.

# 2. Abbatti lo stack
# Rimuove i container be-blue e fe-blue (i volumi dati non vengono toccati).
docker compose -f docker/compose.blue.yml down

# 3. Riavvia lo stack
# Ricrea i container usando l'IMAGE_TAG corrente.
docker compose -f docker/compose.blue.yml up -d

# 4. Verifica stato container
docker ps --filter "name=be-blue" --filter "name=fe-blue"

# 5. Health check applicativo
bash scripts/healthcheck.sh blue
```

> Se lo stack attivo è **green** (verificabile con `cat docker/nginx/conf.d/active_env`),
> sostituisci `blue` con `green` nei comandi sopra.
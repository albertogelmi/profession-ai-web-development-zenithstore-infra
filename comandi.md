# Avvio manuale

La **prima installazione** dell'ambiente deve essere eseguita manualmente.
Questa procedura va ripetuta solo su un nuovo ambiente (es. nuovo server, nuova macchina di sviluppo):
configura il database, compila le immagini Docker, avvia tutta la stack infrastrutturale e fa il primo deploy dello stack Blue.

Successivamente, ad ogni push sul branch `main` della repo [zenithstore-app](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app),
la pipeline Jenkins partirà automaticamente e si occuperà di build, test e deploy Blue-Green senza intervento manuale.
**Prerequisito:** il webhook GitHub deve essere configurato come descritto nella sezione [Configurazione webhook GitHub → Jenkins](#configurazione-webhook-github--jenkins).

```bash
# ── REPO APP ──────────────────────────────────────────────────────────────────
# Eseguire i comandi seguenti dalla root della repo app (zenithstore-app)

# 1. Database
# Avvia MySQL e MongoDB in background. I dati vengono inizializzati
# dai file documentations/ddl.sql, dml.sql e mongo-init.js tramite volumi Docker.
docker compose up -d

# 2. Build immagine Backend
# Compila il codice TypeScript e confeziona l'immagine Express.js.
# Il tag "latest" viene usato come riferimento dal primo deploy manuale.
docker build \
    -t zenithstore-backend:latest \
    ./backend/

# 3. Build immagine Frontend
# Le variabili NEXT_PUBLIC_* vengono incorporate ("baked") nel bundle client
# in fase di build; non è possibile cambiarle a runtime senza ricompilare.
# - NEXT_PUBLIC_BACKEND_URL: URL base per le chiamate API dal browser
# - NEXT_PUBLIC_WS_URL: URL del server WebSocket (notifiche real-time)
# - NEXT_PUBLIC_MOCK_PAYMENT=true: abilita il pulsante "Simula Pagamento"
#   nel checkout; impostare a false solo con un reale payment provider.
docker build \
    -t zenithstore-frontend:latest \
    --build-arg NEXT_PUBLIC_BACKEND_URL=http://localhost \
    --build-arg NEXT_PUBLIC_WS_URL=ws://localhost \
    --build-arg NEXT_PUBLIC_MOCK_PAYMENT=true \
    ./frontend/

# ── REPO INFRA ────────────────────────────────────────────────────────────────
# Eseguire i comandi seguenti dalla root della repo infra (zenithstore-infra)

# 4. Build immagine Jenkins custom (una tantum)
# Estende Jenkins LTS aggiungendo il client Docker CE, necessario per
# eseguire docker build e docker compose all'interno della pipeline CI/CD.
docker build -t jenkins-custom -f Dockerfile.jenkins .

# 5. Crea il volume condiviso Nginx <-> Jenkins (una tantum)
# Questo volume è il canale di comunicazione tra Jenkins e Nginx:
# Jenkins vi scrive active.conf per indicare quale stack (blue/green) è attivo,
# Nginx lo legge e instrada il traffico di conseguenza.
docker volume create zenithstore-nginx-conf

# 6. Popola il volume con le configurazioni iniziali
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

# 7. Monitoring stack
# Avvia Jenkins, Prometheus, Grafana e Alertmanager.
# Jenkins è raggiungibile su http://localhost:8080 (completare il wizard al primo accesso).
# Prometheus scrape le metriche del backend ogni 15s; Grafana le espone su :3100.
docker compose -f docker/compose.monitoring.yml up -d

# 8. Nginx reverse proxy
# Avvia Nginx sulla porta 80. Tutto il traffico esterno (browser, curl) passa da qui.
# Nginx legge active.conf dal volume condiviso per sapere a quale stack
# (blue su :3000/:3001, green su :3010/:3011) girare le richieste.
docker compose -f docker/compose.nginx.yml up -d

# 9. Primo deploy stack Blue
# Imposta le variabili sensibili ed avvia i container be-blue e fe-blue.
# IMAGE_TAG=latest usa le immagini compilate ai punti 2 e 3.
# ATTENZIONE: in produzione sostituire i valori placeholder con segreti robusti.
export IMAGE_TAG=latest \
       DB_PASSWORD=rootpassword \
       MONGO_PASSWORD=adminpassword \
       JWT_SECRET=your-super-secret-jwt-key-change-this-in-production \
       NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production
docker compose -f docker/compose.blue.yml up -d

# 10. Verifica stato container
# Controlla che be-blue e fe-blue siano in stato "Up".
docker ps --filter "name=be-blue" --filter "name=fe-blue"

# 11. Health check applicativo
# Esegue una serie di curl verso le endpoint /health di backend e frontend dello stack blue,
# con retry automatico. Restituisce exit 0 se tutto risponde, exit 1 altrimenti.
bash scripts/healthcheck.sh blue
```

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
# 1. Esporta le variabili d'ambiente necessarie a Docker Compose
# Stessi segreti usati al primo avvio; IMAGE_TAG seleziona quale immagine montare.
export IMAGE_TAG=latest \
       DB_PASSWORD=rootpassword \
       MONGO_PASSWORD=adminpassword \
       JWT_SECRET=your-super-secret-jwt-key-change-this-in-production \
       NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production

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

---

# Switch Blue-Green manuale

Questa procedura esegue un deploy Blue-Green **senza Jenkins**: avvia lo stack idle, verifica che risponda
correttamente, switcha Nginx sul nuovo stack e abbatte quello vecchio dopo una finestra di rollback di 5 minuti.

Usala per testare lo switch, per un deploy di emergenza o per tornare manualmente a uno stack specifico.

> **Come funziona il meccanismo:** blue e green non sono ambienti fissi — si alternano ad ogni switch.
> Lo stack *attivo* riceve tutto il traffico; lo stack *idle* è spento in attesa del deploy successivo.
> Il file `docker/nginx/conf.d/active_env` tiene traccia di quale stack è attivo in questo momento.

## Verifica stato corrente

Prima di procedere, controlla quale stack è attivo:

```bash
# Mostra lo stack attualmente attivo ("blue" o "green")
cat docker/nginx/conf.d/active_env

# Mostra tutti i container in esecuzione (utile per confermare quali stack sono up)
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Esegui lo switch

```bash
# 1. Esporta le variabili d'ambiente richieste dallo script
# IMAGE_TAG=latest usa le immagini correntemente disponibili.
# ATTENZIONE: in produzione sostituire i valori placeholder con segreti robusti.
export IMAGE_TAG=latest \
       DB_PASSWORD=rootpassword \
       MONGO_PASSWORD=adminpassword \
       JWT_SECRET=your-super-secret-jwt-key-change-this-in-production \
       NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production

# 2. Avvia lo switch
# Lo script: avvia lo stack idle → attende 15s → health check → switcha Nginx →
# mantiene il vecchio stack attivo per 300s (rollback window) → abbatte il vecchio stack.
# Il terzo argomento ("production") è una label descrittiva nei log; non cambia il comportamento.
bash scripts/switch-blue-green.sh deploy latest production
```

## Rollback durante la finestra di 5 minuti

Se dopo lo switch qualcosa non va, hai **5 minuti** per tornare allo stack precedente
(che rimane in esecuzione proprio per questo scopo):

```bash
# Ri-switcha Nginx sullo stack precedente immediatamente
bash scripts/rollback.sh
```

> Trascorsa la rollback window, lo stack precedente viene abbattuto automaticamente
> e il rollback non è più possibile con questo script. In quel caso usa la procedura
> di [Riavvio manuale](#riavvio-manuale) sullo stack desiderato.
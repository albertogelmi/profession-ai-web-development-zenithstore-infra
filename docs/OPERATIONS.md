# OPERATIONS.md — Guida Operativa ZenithStore DevOps

**Progetto**: ZenithStore Online  
**Repo infra**: `profession-ai-web-development-zenithstore-infra`  
**Repo app**: `profession-ai-web-development-zenithstore-app`

---

## Indice

1. [Architettura — Quick Reference](#1-architettura--quick-reference)
2. [Compatibilità OS](#2-compatibilità-os)
3. [Setup Iniziale (prima installazione)](#3-setup-iniziale-prima-installazione)
4. [Configurazione iniziale Jenkins (wizard)](#4-configurazione-iniziale-jenkins-wizard)
5. [Configurazione pipeline Jenkins (una tantum)](#5-configurazione-pipeline-jenkins-una-tantum)
6. [Configurazione webhook GitHub → Jenkins](#6-configurazione-webhook-github--jenkins)
7. [Pipeline CI/CD — Flusso standard](#7-pipeline-cicd--flusso-standard)
8. [Deploy manuale e riavvio forzato](#8-deploy-manuale-e-riavvio-forzato)
9. [Rollback](#9-rollback)
10. [Consultazione dei log](#10-consultazione-dei-log)
11. [Configurazione Grafana](#11-configurazione-grafana)
12. [Prometheus](#12-prometheus)
13. [Alertmanager](#13-alertmanager)
14. [Comandi Utili](#14-comandi-utili)
15. [Procedure di Emergenza](#15-procedure-di-emergenza)
16. [Gestione Credenziali](#16-gestione-credenziali)
17. [Note Importanti](#17-note-importanti)

---

## 1. Architettura — Quick Reference

```
Browser → Nginx :80 → Stack ATTIVO (blue OPPURE green)
                          BE :3000  (interno Docker network)
                          FE :3001  (interno Docker network)

Stack IDLE (durante deploy):
    BE host :3010 → container :3000
    FE host :3011 → container :3001

DB condiviso: MySQL :3306, MongoDB :27018
Monitoring:   Prometheus :9090, Grafana :3100, Alertmanager :9093
Jenkins:      :8080
```

**Porte host di riferimento**:

| Servizio | Porta host | Note |
|---|---|---|
| Nginx (HTTP) | 80 | Traffico utente |
| BE blue | 3000 | Solo per healthcheck/debug |
| FE blue | 3001 | Solo per healthcheck/debug |
| BE green | 3010 | Solo per healthcheck/debug |
| FE green | 3011 | Solo per healthcheck/debug |
| MySQL | 3306 | |
| MongoDB | 27018 | |
| Jenkins | 8080 | |
| Prometheus | 9090 | |
| Grafana | 3100 | |
| Alertmanager | 9093 | |

> **Punto di accesso all'applicazione:** usa sempre **`http://localhost`** (porta 80, Nginx).
> Non usare le porte dirette dei container: quelle sono esposte solo per health check e debug.
> Nginx instrada automaticamente allo stack attivo, quindi l'URL rimane invariato ad ogni switch.

---

## 2. Compatibilità OS

L'intera infrastruttura è compatibile con **Linux** e **Windows**.
Tutti gli script (`.sh`), la pipeline Jenkins e i compose files **girano dentro container Linux**, quindi sono indipendenti dall'OS host.

L'unico vincolo riguarda i **comandi manuali digitati sul terminale dell'host**:
su Windows usare **Git Bash (MINGW64)** — PowerShell nativo non è supportato (`bash`, `source`, `set -a` e altri comandi shell non sono disponibili).
Git Bash è incluso in [Git for Windows](https://gitforwindows.org/).

Su **Linux** non ci sono vincoli: tutti i comandi funzionano nativamente.

---

## 3. Setup Iniziale (prima installazione)

La prima installazione va eseguita **manualmente** su ogni nuovo ambiente (nuovo server o nuova macchina di sviluppo). La procedura compila le immagini Docker, avvia tutta la stack infrastrutturale (inclusi i database) e fa il primo deploy dello stack Blue.

Successivamente, ad ogni push sui branch `main`, `release-candidate` e `release` della repo [zenithstore-app](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app), la pipeline Jenkins si avvierà automaticamente senza intervento manuale.

> **Prerequisito:** il webhook GitHub deve essere configurato come descritto nella [sezione 6](#6-configurazione-webhook-github--jenkins).

### 3.1 Configurazione del file .env

> **Variabili d'ambiente:** copia `.env.example` in `.env` e sostituisci i valori placeholder con i segreti reali prima di eseguire i comandi seguenti.
> Docker Compose carica `.env` automaticamente se presente nella stessa directory.

```bash
# Dalla root del repo infra
cp .env.example .env
# → Apri .env con un editor e sostituisci tutti i valori "change-me-..."
```

### 3.2 Sequenza di avvio da zero

```bash
# 1. Clona i repository (una tantum)
git clone https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git
git clone https://github.com/albertogelmi/profession-ai-web-development-zenithstore-infra.git

# ── REPO INFRA — configurazione iniziale ──────────────────────────────────────
cd profession-ai-web-development-zenithstore-infra

# 2. Copia il file .env e compila i segreti reali prima di proseguire
cp .env.example .env
# → Apri .env con un editor e sostituisci tutti i valori "change-me-..."

# ── REPO APP ──────────────────────────────────────────────────────────────────
# Eseguire i comandi seguenti dalla root della repo app (zenithstore-app)
cd ../profession-ai-web-development-zenithstore-app

# 3. Carica le variabili dall'infra .env (una volta per sessione di terminale).
#    Necessario solo per i comandi docker build di questa sezione;
#    i docker compose nel repo infra leggono .env automaticamente.
set -a && source ../profession-ai-web-development-zenithstore-infra/.env && set +a

# 4. Build immagine Backend
docker build \
    -t zenithstore-backend:latest \
    ./backend/

# 5. Build immagine Frontend
# Le variabili NEXT_PUBLIC_* vengono incorporate ("baked") nel bundle client
# in fase di build; non è possibile cambiarle a runtime senza ricompilare.
# I valori vengono letti dall'infra .env caricato al passo 3.
# NEXT_PUBLIC_MOCK_PAYMENT=true abilita il pulsante 'Simula Pagamento' nel
# checkout (impostare a false solo con un payment provider reale integrato).
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

# 8. Popola il volume condiviso Nginx <-> Jenkins con le configurazioni iniziali
# Copia blue.conf e green.conf nel volume e crea active.conf/active_env
# direttamente all'interno del volume (blue come stack di partenza).
# Senza questo step Nginx non sa a quale upstream puntare al primo avvio.

# Linux / macOS:
docker run --rm \
    -v "${PWD}/docker/nginx/conf.d:/src:ro" \
    -v zenithstore-nginx-conf:/dest \
    alpine sh -c "cp /src/blue.conf /src/green.conf /dest/ && cp /src/blue.conf /dest/active.conf && echo blue > /dest/active_env"

# Windows (Git Bash / MINGW64):
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${PWD}/docker/nginx/conf.d:/src:ro" \
    -v zenithstore-nginx-conf:/dest \
    alpine sh -c "cp /src/blue.conf /src/green.conf /dest/ && cp /src/blue.conf /dest/active.conf && echo blue > /dest/active_env"

# 9. Stack database (una tantum per un nuovo ambiente)
# Avvia MySQL e MongoDB e crea la rete Docker condivisa zenithstore-network,
# referenziata come external da tutti gli altri stack (blue, green, monitoring, nginx).
# Gli script in docker/db/ vengono eseguiti una sola volta all'inizializzazione dei volumi;
# le successive esecuzioni di "up" non re-inizializzano il DB se i volumi esistono già.
docker compose -f docker/compose.db.yml up -d

# 10. Monitoring stack
# Avvia Jenkins, Prometheus, Grafana e Alertmanager.
# Jenkins è raggiungibile su http://localhost:8080 (completare il wizard al primo accesso).
# Prometheus scrape le metriche del backend ogni 15s; Grafana le espone su :3100.
docker compose -f docker/compose.monitoring.yml up -d

# 11. Nginx reverse proxy
# Avvia Nginx sulla porta 80. Tutto il traffico esterno (browser, curl) passa da qui.
# Nginx legge active.conf dal volume condiviso per sapere a quale stack
# (blue su :3000/:3001, green su :3010/:3011) girare le richieste.
docker compose -f docker/compose.nginx.yml up -d

# 12. Primo deploy stack Blue
# Docker Compose legge automaticamente il file .env dalla directory corrente.
# Nessun export manuale necessario: assicurarsi che .env sia compilato prima
# di eseguire questo comando.
docker compose -f docker/compose.blue.yml up -d

# 13. Verifica stato container
# Controlla che be-blue e fe-blue siano in stato "Up".
docker ps --filter "name=be-blue" --filter "name=fe-blue"

# 14. Health check applicativo
# Esegue una serie di curl verso le endpoint /health di backend e frontend dello stack blue,
# con retry automatico. Restituisce exit 0 se tutto risponde, exit 1 altrimenti.
bash scripts/healthcheck.sh blue
```

---

## 4. Configurazione iniziale Jenkins (wizard)

Questa procedura va eseguita **una sola volta** dopo il primo avvio del monitoring stack.
Jenkins è raggiungibile su `http://localhost:8080`.

### Passo 1 — Sblocca Jenkins

Jenkins genera una password amministratore temporanea al primo avvio.
Recuperala con il comando seguente e incollala nel campo "Administrator password" della pagina "Unlock Jenkins":

```bash
# Linux / macOS:
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# Windows (Git Bash / MINGW64):
MSYS_NO_PATHCONV=1 docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Clicca **Continue**.

### Passo 2 — Installa i plugin consigliati

Nella pagina "Customize Jenkins" scegli **"Installa componenti aggiuntivi consigliati"**.
Jenkins installerà il set di plugin standard (Git, Pipeline, GitHub, ecc.).
Attendi il completamento dell'installazione (qualche minuto).

### Passo 3 — Crea il primo utente amministratore

Compila il form con le credenziali dell'account amministratore e clicca **"Salva e continua"**.

> Conserva queste credenziali in un password manager: serviranno ad ogni accesso a Jenkins.

### Passo 4 — Configura l'URL dell'istanza

Lascia il valore proposto (`http://localhost:8080/`) invariato e clicca **"Salva e termina"**.

> Questo URL viene usato da Jenkins per costruire i link nelle notifiche e nei webhook.
> Se in futuro esponi Jenkins pubblicamente (es. tramite ngrok), aggiornalo da
> **Manage Jenkins → System → Jenkins URL**.

Clicca **"Inizia a usare Jenkins"**: il wizard è completato.

---

## 5. Configurazione pipeline Jenkins (una tantum)

### 5.1 Aggiungi le credenziali (Secrets)

Vai su **Gestisci Jenkins → Credenziali → System → Credenziali globali → Add Credentials**.
Seleziona il tipo **Secret text**, lascia Scope su **Globale** e crea le seguenti 12 credenziali:

| ID | Secret | Descrizione |
|---|---|---|
| `jwt-secret-development` | valore `JWT_SECRET` develop | `JWT Secret BE/FE (develop)` |
| `jwt-secret-staging` | valore `JWT_SECRET` staging | `JWT Secret BE/FE (staging)` |
| `jwt-secret-production` | valore `JWT_SECRET` production | `JWT Secret BE/FE (production)` |
| `db-password-development` | valore `MYSQL_ROOT_PASSWORD` develop | `MySQL root password (develop)` |
| `db-password-staging` | valore `MYSQL_ROOT_PASSWORD` staging | `MySQL root password (staging)` |
| `db-password-production` | valore `MYSQL_ROOT_PASSWORD` production | `MySQL root password (production)` |
| `mongo-password-development` | valore `MONGO_PASSWORD` develop | `MongoDB admin password (develop)` |
| `mongo-password-staging` | valore `MONGO_PASSWORD` staging | `MongoDB admin password (staging)` |
| `mongo-password-production` | valore `MONGO_PASSWORD` production | `MongoDB admin password (production)` |
| `nextauth-secret-development` | valore `NEXTAUTH_SECRET` develop | `NextAuth.js secret (develop)` |
| `nextauth-secret-staging` | valore `NEXTAUTH_SECRET` staging | `NextAuth.js secret (staging)` |
| `nextauth-secret-production` | valore `NEXTAUTH_SECRET` production | `NextAuth.js secret (production)` |

> L'**ID** deve corrispondere esattamente ai valori nella tabella: è quello che il `Jenkinsfile` usa per recuperare i segreti a runtime.

> La password SMTP per le notifiche email di Jenkins **non va configurata qui**: si imposta in **Gestisci Jenkins → System → E-mail Notification**.

### 5.2 Configura le variabili globali

Vai su **Gestisci Jenkins → System**, scorri fino a **Proprietà globali**, spunta **"Variabili d'ambiente"** e aggiungi le seguenti 13 variabili:

| Nome | Valore |
|---|---|
| `APP_REPO` | `https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git` |
| `NOTIFICATION_EMAIL_DEVELOPMENT` | email team sviluppo (es. `dev@zenithstore.com`) |
| `NOTIFICATION_EMAIL_STAGING` | email team QA (es. `qa@zenithstore.com`) |
| `NOTIFICATION_EMAIL_PRODUCTION` | email team ops (es. `ops@zenithstore.com`) |
| `NEXT_PUBLIC_BACKEND_URL_DEVELOPMENT` | `http://localhost` |
| `NEXT_PUBLIC_BACKEND_URL_STAGING` | es. `https://staging-api.zenithstore.com` |
| `NEXT_PUBLIC_BACKEND_URL_PRODUCTION` | es. `https://api.zenithstore.com` |
| `NEXT_PUBLIC_WS_URL_DEVELOPMENT` | `ws://localhost` |
| `NEXT_PUBLIC_WS_URL_STAGING` | es. `wss://staging.zenithstore.com` |
| `NEXT_PUBLIC_WS_URL_PRODUCTION` | es. `wss://zenithstore.com` |
| `NEXT_PUBLIC_MOCK_PAYMENT_DEVELOPMENT` | `true` |
| `NEXT_PUBLIC_MOCK_PAYMENT_STAGING` | `true` |
| `NEXT_PUBLIC_MOCK_PAYMENT_PRODUCTION` | `false` |

Clicca **"Salva"**.

### 5.3 Installa il plugin Pipeline Stage View

Senza questo plugin la pagina del job sarebbe vuota: non vedrai la griglia degli stage (Checkout, Build, Test, Docker Build, Deploy).

**Gestisci Jenkins → Plugin → Available plugins** → cerca `Pipeline: Stage View` → spunta → **Install** → riavvia Jenkins.

### 5.4 Crea il job Pipeline

1. Vai su **Dashboard → Nuovo elemento**
2. Inserisci il nome `zenithstore`, seleziona **Pipeline** e clicca **OK**
3. Scorri fino alla sezione **Pipeline** in fondo alla pagina e imposta:

   | Campo | Valore |
   |---|---|
   | **Definition** | `Pipeline script from SCM` |
   | **SCM** | `Git` |
   | **URL di Deposito** | `https://github.com/albertogelmi/profession-ai-web-development-zenithstore-infra.git` |
   | **Credenziali** | Nessuna (repo pubblica) |
   | **Branches to build** | Aggiungere tre voci (cliccare **"Add"** per ognuna): `*/main`, `*/release-candidate`, `*/release` |
   | **Script Path** | `Jenkinsfile` (default) |

4. Clicca **"Salva"**

### 5.5 Prima esecuzione manuale

1. Vai su **Dashboard → zenithstore → Esegui adesso**

   > **Nota:** al primo avvio Jenkins scopre il blocco `parameters` del Jenkinsfile e da quel momento il pulsante diventa **"Compila con parametri"**.
   > Per build automatiche (webhook) il campo `Branch` viene ignorato: il branch viene rilevato dal trigger SCM.
   > Per lanci manuali, scegliere il branch desiderato dal menu (`main`, `release-candidate` o `release`).

2. Attendi il completamento (~5-10 minuti) e verifica che tutte le stage siano verdi:
   **Checkout → Build → Test → Docker Build → Deploy**

3. Controlla quale stack è diventato attivo:
   ```bash
   MSYS_NO_PATHCONV=1 docker exec nginx cat /etc/nginx/conf.d/active_env
   ```

4. Apri **`http://localhost`** nel browser e verifica che l'applicazione risponda.

---

## 6. Configurazione webhook GitHub → Jenkins

Senza questo step la pipeline **non si avvia automaticamente**: ogni build deve essere lanciata a mano da Jenkins.
Il webhook fa sì che GitHub notifichi Jenkins ad ogni push sui branch `main`, `release-candidate` e `release`.

### 6.1 Prerequisiti

- Jenkins deve essere **raggiungibile da internet** sulla porta `8080`.
  In locale si può usare un tunnel come [ngrok](https://ngrok.com): `ngrok http 8080`.
- Il plugin **GitHub** deve essere installato. È incluso nei plugin consigliati (passo 2 del wizard).
  Per verificarlo: **Gestisci Jenkins → Plugin → Installed plugins** → cerca `GitHub plugin`.

### 6.2 Configura Jenkins

1. Apri il job `zenithstore` in Jenkins.
2. Clicca **Configura** nel menu a sinistra.
3. Scorri fino alla sezione **Triggers**.
4. Spunta **"GitHub hook trigger for GITScm polling"**.
5. Clicca **Salva**.

### 6.3 Configura il webhook su GitHub

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

### 6.4 Verifica

Dopo aver salvato, GitHub esegue un ping di test: nella pagina del webhook appare un pallino verde se Jenkins ha risposto con HTTP 200.
Fai un push di prova su uno dei branch configurati (`main`, `release-candidate` o `release`) e controlla che una nuova build parta automaticamente in Jenkins.

---

## 7. Pipeline CI/CD — Flusso standard

La pipeline si avvia automaticamente su ogni push al branch `main`, `release-candidate` o `release` del repo app tramite webhook GitHub → Jenkins.

```
Push → Jenkins trigger → Build → Test → DB Migration → Docker Build → Deploy Staging
                                                                              │
                                                          Approvazione manuale Jenkins UI
                                                                              │
                                                                   Deploy Production
```

### Stage della pipeline

| # | Stage | Dettaglio |
|---|---|---|
| 1 | **Checkout App** | Clona il repo app in `app/`; calcola `COMMIT_SHA` |
| 2 | **Build** | `npm ci` + `npm run build` (BE e FE in parallelo) |
| 3 | **Test** | `jest --ci` (BE e FE in parallelo); pubblica report JUnit |
| 4 | **DB Migration** | Placeholder TypeORM (da abilitare) |
| 5 | **Docker Build** | Build immagini BE e FE con tag `COMMIT_SHA` + `latest` |
| 6 | **Deploy Staging** | `switch-blue-green.sh` → health check → switch Nginx |
| 7 | **Deploy Production** | Gate di approvazione manuale, poi stesso script |

### Cosa fa `switch-blue-green.sh`

1. Legge lo stack attivo da `active_env`
2. Abbatte eventuale stack idle rimasto da deploy precedenti
3. Avvia lo stack idle con le nuove immagini (`IMAGE_TAG`)
4. Esegue `healthcheck.sh` (retry su BE:host e FE:host)
5. Se health check OK: copia `<idle>.conf` in `active.conf` + `nginx -s reload`
6. Attende la rollback window (default: 5 minuti)
7. Abbatte lo stack precedente

---

## 8. Deploy manuale e riavvio forzato

### 8.1 Deploy manuale (emergenza o primo deploy)

```bash
# Dalla root del repo infra — .env viene letto automaticamente
export IMAGE_TAG=<commit-sha>
bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging
```

### 8.2 Riavvio forzato dello stack attivo

Questa procedura serve per **ridistribuire lo stack attualmente attivo** senza cambiare versione dell'immagine — ad esempio per applicare una fix a caldo, recuperare da uno stato inconsistente o forzare la rilettura delle variabili d'ambiente.

> **Nota:** questo **non** è un deploy Blue-Green — il traffico viene interrotto brevemente mentre i container si riavviano. Per zero downtime usa la pipeline Jenkins o `switch-blue-green.sh`.

```bash
# 1. Abbatti lo stack (i volumi dati non vengono toccati)
docker compose -f docker/compose.blue.yml down

# 2. Riavvia lo stack con l'IMAGE_TAG corrente
docker compose -f docker/compose.blue.yml up -d

# 3. Verifica stato container
docker ps --filter "name=be-blue" --filter "name=fe-blue"

# 4. Health check applicativo
bash scripts/healthcheck.sh blue
```

> Se lo stack attivo è **green** (verificabile con `MSYS_NO_PATHCONV=1 docker exec nginx cat /etc/nginx/conf.d/active_env`), sostituisci `blue` con `green` nei comandi sopra.

---

## 9. Rollback

### 9.1 Rollback automatico (pipeline)

Se `healthcheck.sh` fallisce dopo lo switch, la pipeline interrompe il deploy e abbatte lo stack idle. Lo stack precedente rimane attivo senza interruzioni.

### 9.2 Rollback manuale (durante rollback window)

Finché il vecchio stack è ancora in esecuzione (entro i 5 minuti dalla rollback window):

```bash
bash scripts/rollback.sh
```

Lo script:
1. Legge lo stack attivo corrente
2. Re-switcha Nginx al precedente
3. Abbatte lo stack con problemi

### 9.3 Rollback dopo rollback window (vecchio stack già abbattuto)

Il vecchio stack è già down. Occorre re-deployare la versione precedente:

```bash
export IMAGE_TAG=<sha-versione-precedente>
bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging
```

---

## 10. Consultazione dei log

Una volta avviati i container, leggere i log è il modo più rapido per verificare che tutto funzioni correttamente, o per diagnosticare un problema.
I log di backend e frontend sono separati per stack (blue/green); in questa sezione trovi i comandi per le situazioni più comuni.

### Log in tempo reale (tail)

Utile per osservare l'applicazione mentre risponde a richieste, durante un deploy o dopo un riavvio.
`-f` ("follow") mantiene il terminale agganciato al flusso: interrompere con `Ctrl+C`.

```bash
# Backend stack Blue
docker logs -f be-blue

# Frontend stack Blue
docker logs -f fe-blue

# Backend stack Green
docker logs -f be-green

# Frontend stack Green
docker logs -f fe-green
```

### Log degli ultimi N minuti

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
> (verificabile con `MSYS_NO_PATHCONV=1 docker exec nginx cat /etc/nginx/conf.d/active_env`).

### Log di tutti i container di uno stack

Comodo per avere una vista unificata di backend e frontend insieme, ad esempio per correlare richieste HTTP con le risposte API.
L'output è interleaved e prefissato con il nome del container.

```bash
# Stack Blue — log interleaved in tempo reale
docker compose -f docker/compose.blue.yml logs -f

# Stack Green — log interleaved in tempo reale
docker compose -f docker/compose.green.yml logs -f
```

### Log del DB stack

Utile se MySQL o MongoDB non si avviano correttamente o i dati non vengono inizializzati.

```bash
# MySQL e MongoDB in tempo reale
docker compose -f docker/compose.db.yml logs -f

# Solo MySQL
docker compose -f docker/compose.db.yml logs -f mysql

# Solo MongoDB
docker compose -f docker/compose.db.yml logs -f mongodb
```

### Log del monitoring stack

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

## 11. Configurazione Grafana

Grafana è raggiungibile su **http://localhost:3100**.

### 11.1 Primo accesso

- Username: `admin`
- Password: il valore di `GRAFANA_PASSWORD` nel file `.env` (default: `admin`)

Al primo accesso Grafana chiederà di impostare una nuova password: sceglila e conservala.

### 11.2 Aggiungi Prometheus come Data Source

1. Nel menu a sinistra vai su **Connections → Data Sources**
2. Clicca **"Add data source"**
3. Scegli **Prometheus**
4. Nel campo **URL** inserisci: `http://prometheus:9090`
   *(nome del container, non `localhost`: Grafana e Prometheus condividono la rete Docker `monitoring-network`)*
5. Lascia tutto il resto ai valori di default
6. Clicca **"Save & test"** — deve comparire il banner verde **"Successfully queried the Prometheus API"**

### 11.3 Importa la dashboard ZenithStore

La dashboard è già inclusa nel repository come file JSON pronto all'uso.

1. Nel menu a sinistra vai su **Dashboards → New → Import**
2. Clicca **"Upload dashboard JSON file"**
3. Seleziona il file `docker/grafana/dashboards/zenithstore.json`
4. Nel campo **Prometheus** (data source) seleziona il data source appena creato
5. Clicca **"Import"**

La dashboard **ZenithStore Online** contiene 4 panel:

| Panel | Tipo | Query |
|---|---|---|
| Request Rate | Time series | `rate(http_requests_total[5m])` |
| Error Rate | Time series | `rate(http_errors_total[5m]) / rate(http_requests_total[5m])` |
| Latency p95 | Time series | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` |
| Backend Status | Stat | `up{job=~"zenithstore-backend.*"}` |

> **"No data" su Error Rate e Latency p95** è normale finché il backend non riceve traffico con errori o latenze rilevanti.
> Il panel **Backend Status** mostra `1` (verde) quando il backend è raggiungibile, `0` (rosso) se è down.

---

## 12. Prometheus

Prometheus è raggiungibile su **http://localhost:9090**. Non richiede configurazione manuale: scraping, alert rules e riferimento ad Alertmanager sono già definiti in `docker/prometheus/prometheus.yml` e montati come volumi al bootstrap.

### 12.1 Verificare che lo scraping funzioni

**Status → Target health** — devono essere presenti e in stato `UP`:

| Job | Target |
|---|---|
| `zenithstore-backend-blue` | `be-blue:3000` |
| `zenithstore-backend-green` | `be-green:3000` |
| `prometheus` | `localhost:9090` |

> Lo stack non attivo può essere `DOWN`: è normale perché il container non è in esecuzione.

### 12.2 Verificare che gli alert siano caricati

**Alerts** — devono essere presenti tre alert (tutti in stato `Inactive` quando tutto funziona):

| Alert | Severità | Condizione |
|---|---|---|
| `HighLatency` | warning | p95 latency > 2s per più di 2 minuti |
| `HighErrorRate` | critical | error rate > 5% nell'ultimo minuto |
| `BackendDown` | critical | backend non raggiungibile (immediato) |

### 12.3 Query di esempio

**Query** — incolla una PromQL expression e premi **Execute**.
Usa la tab **Table** per valori istantanei, **Graph** per la serie storica.

```promql
# Tutte le metriche disponibili del backend blue
{job="zenithstore-backend-blue"}

# Richieste al secondo (media ultimi 5 minuti)
rate(http_requests_total[5m])

# Richieste al secondo per singolo endpoint e metodo HTTP
rate(http_requests_total[5m])

# Error rate percentuale per job
rate(http_errors_total[5m]) / rate(http_requests_total[5m]) * 100

# Latency p50
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))

# Latency p95 (soglia degli alert)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Latency p99
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Stato backend (1 = up, 0 = down)
up{job=~"zenithstore-backend.*"}

# Totale richieste dall'avvio
http_requests_total

# Totale errori dall'avvio
http_errors_total

# Auto-monitoraggio Prometheus: memoria heap usata
go_memstats_heap_inuse_bytes{job="prometheus"}
```

### 12.4 Ricaricare la configurazione senza riavviare

```bash
curl -X POST http://localhost:9090/-/reload
```

---

## 13. Alertmanager

Alertmanager è raggiungibile su **http://localhost:9093**.
Riceve gli alert da Prometheus e li raggruppa, silenzia o instrada ai receiver configurati.
La configurazione si trova in `docker/alertmanager/alertmanager.yml`.

### 13.1 Verificare gli alert attivi

La pagina principale (**Alerts**) mostra tutti gli alert ricevuti da Prometheus con il loro stato:

| Stato | Significato |
|---|---|
| `firing` | Alert attivo — la condizione è vera in questo momento |
| `resolved` | Alert rientrato — la condizione non è più vera |

Con l'applicazione funzionante e senza errori, la pagina sarà vuota (nessun alert firing).

### 13.2 Creare un silenzio (Silence)

Utile durante manutenzioni programmate per evitare notifiche indesiderate:

1. Clicca **"New Silence"**
2. Aggiungi un matcher, es. `alertname = BackendDown`
3. Imposta l'intervallo di tempo
4. Aggiungi un commento e clicca **"Create"**

Durante il silenzio gli alert continuano a essere ricevuti ma non vengono inoltrati al receiver.

### 13.3 Configurazione notifiche email (opzionale)

Per default Alertmanager usa il receiver `null`: gli alert sono visibili nell'UI ma non viene inviata alcuna email.

Per abilitare le email modifica `docker/alertmanager/alertmanager.yml`:

1. Decommentare il blocco `smtp_*` nella sezione `global` e inserire i valori reali
2. Cambiare `receiver: 'null'` in `receiver: 'team-email'` nella sezione `route` (e nella route `critical`)
3. Decommentare il receiver `team-email` nella sezione `receivers` e impostare l'indirizzo destinatario
4. Riavviare il container:

```bash
docker compose -f docker/compose.monitoring.yml restart alertmanager
```

> **Gmail:** genera un'App Password da [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
> e usala come `smtp_auth_password`. Non usare la password dell'account Google.

### 13.4 Ricaricare la configurazione senza riavviare

```bash
curl -X POST http://localhost:9093/-/reload
```

---

## 14. Comandi Utili

```bash
# Stato stack attivo
MSYS_NO_PATHCONV=1 docker exec nginx cat /etc/nginx/conf.d/active_env   # "blue" o "green"

# Stato di tutti i container
docker ps

# Health check manuale
bash scripts/healthcheck.sh blue    # oppure green

# Reload Nginx (non fa switch, solo ricarica config esistente)
docker exec nginx nginx -s reload

# Verifica configurazione Nginx
docker exec nginx nginx -t

# Stop completo (tutti gli stack)
docker compose -f docker/compose.blue.yml down
docker compose -f docker/compose.green.yml down
docker compose -f docker/compose.nginx.yml down
docker compose -f docker/compose.monitoring.yml down
docker compose -f docker/compose.db.yml down
```

---

## 15. Procedure di Emergenza

### 15.1 Nginx non risponde

```bash
# Verifica che il container sia running
docker ps | grep nginx

# Verifica errori nella configurazione
docker exec nginx nginx -t

# Riavvio forzato
docker compose -f docker/compose.nginx.yml restart nginx
```

### 15.2 Backend down

```bash
# Controlla i log del BE attivo
docker logs be-blue   # o be-green

# Riavvio manuale del container
docker restart be-blue

# Se non bastasse: re-deploy completo dello stack attivo
ACTIVE=$(MSYS_NO_PATHCONV=1 docker exec nginx cat /etc/nginx/conf.d/active_env)
docker compose -f "docker/compose.${ACTIVE}.yml" down
docker compose -f "docker/compose.${ACTIVE}.yml" up -d
```

### 15.3 Database non raggiungibile

```bash
# Dal repo app
cd ../profession-ai-web-development-zenithstore-app

# Stato DB
docker compose -f docker/compose.db.yml ps

# Log MySQL
docker compose -f docker/compose.db.yml logs mysql

# Log MongoDB
docker compose -f docker/compose.db.yml logs mongodb

# Riavvio DB (ATTENZIONE: breve downtime)
docker compose -f docker/compose.db.yml restart mysql
docker compose -f docker/compose.db.yml restart mongodb
```

### 15.4 Jenkins non risponde

```bash
# Riavvio Jenkins (i job in corso vengono persi)
docker compose -f docker/compose.monitoring.yml restart jenkins
```

---

## 16. Gestione Credenziali

### 16.1 Dove vivono i secrets

| Secret | Dove |
|---|---|
| JWT_SECRET | Jenkins Credentials (`jwt-secret-*`) |
| DB_PASSWORD | Jenkins Credentials (`db-password-*`) |
| MONGO_PASSWORD | Jenkins Credentials (`mongo-password-*`) |
| NEXTAUTH_SECRET | Jenkins Credentials (`nextauth-secret-*`) |
| SMTP password Jenkins | Jenkins Credentials (`email-password`) |
| SMTP password Alertmanager | File `docker/alertmanager/alertmanager.yml` (non committato) |
| Grafana admin password | Variabile `GRAFANA_PASSWORD` nel file `.env` |

**I secrets non sono mai committati nel repository.** Il file `.env` è in `.gitignore`; `.env.example` contiene solo placeholder.

### 16.2 Rotazione credenziali

1. Aggiornare il valore in Jenkins (**Manage Jenkins → Credentials**)
2. Per `JWT_SECRET`: riavvio rolling dei container con il nuovo secret:
   ```bash
   export IMAGE_TAG=latest
   bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging
   ```
3. Il nuovo secret viene iniettato al prossimo deploy tramite `withCredentials`

---

## 17. Note Importanti

- **DB condiviso blue/green**: le migration del DB devono essere backward-compatible.
  Non eseguire mai migration che rimuovono colonne in un singolo deploy.
  Usare il pattern expand-migrate-contract su deploy consecutivi.

- **WebSocket durante switch**: al momento del reload Nginx, le connessioni WebSocket
  attive vengono droppate (~1-2s). Socket.io si riconnette automaticamente.

- **SYNC=false**: verificare che i file `.env.staging` e `.env.production`
  abbiano sempre `SYNC=false`. Con `SYNC=true` TypeORM può alterare lo schema
  automaticamente causando perdita di dati.

- **Rollback window**: i 5 minuti di attesa dopo lo switch sono configurabili
  via variabile `ROLLBACK_WINDOW_SECONDS` nello script.
  In produzione considerare un valore più alto (es. 15 minuti).

- **NEXT_PUBLIC_MOCK_PAYMENT**: impostare a `false` solo con un payment provider reale integrato.
  Il valore `true` abilita il pulsante "Simula Pagamento" nel checkout.

- **Windows (Git Bash)**: prefisso `MSYS_NO_PATHCONV=1` necessario su tutti i comandi `docker exec`
  e `docker run` con path che iniziano con `/`.

```
Browser → Nginx :80 → Stack ATTIVO (blue OPPURE green)
                          BE :3000  (interno Docker network)
                          FE :3001  (interno Docker network)

Stack IDLE (durante deploy):
    BE host :3010 → container :3000
    FE host :3011 → container :3001

DB condiviso: MySQL :3306, MongoDB :27018
Monitoring:  Prometheus :9090, Grafana :3100, Alertmanager :9093
Jenkins:     :8080
```

**Porte host di riferimento**:

| Servizio | Porta host | Note |
|---|---|---|
| Nginx (HTTP) | 80 | Traffico utente |
| BE blue | 3000 | Solo per healthcheck/debug |
| FE blue | 3001 | Solo per healthcheck/debug |
| BE green | 3010 | Solo per healthcheck/debug |
| FE green | 3011 | Solo per healthcheck/debug |
| MySQL | 3306 | |
| MongoDB | 27018 | |
| Jenkins | 8080 | |
| Prometheus | 9090 | |
| Grafana | 3100 | |
| Alertmanager | 9093 | |

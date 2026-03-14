# OPERATIONS.md — Guida Operativa ZenithStore DevOps

**Progetto**: ZenithStore Online  
**Repo infra**: `profession-ai-web-development-zenithstore-infra`  
**Repo app**: `profession-ai-web-development-zenithstore-app`

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

---

## 2. Setup Iniziale

### 2.1 Prerequisiti
- Docker Desktop installato e avviato su Windows
- Docker Desktop → Settings → General → ✅ "Expose daemon on tcp://localhost:2375"
  (oppure il named pipe `//./pipe/docker_engine` montato in Jenkins)
- Git installato

### 2.2 Sequenza di avvio da zero

```bash
# 1. Clona i repository
git clone <URL-app-repo>   profession-ai-web-development-zenithstore-app
git clone <URL-infra-repo> profession-ai-web-development-zenithstore-infra

# 2. Avvia i database (MySQL + MongoDB)
cd profession-ai-web-development-zenithstore-app
docker compose up -d

# Attendi che i DB siano healthy
docker compose ps   # STATUS = healthy

# 3. Vai nel repo infra
cd ../profession-ai-web-development-zenithstore-infra

# 4. Build dell'immagine Jenkins custom (una tantum)
docker build -t jenkins-custom -f Dockerfile.jenkins .

# 5. Crea e popola il volume condiviso Nginx ↔ Jenkins (una tantum)
#    Questo volume contiene i conf file Nginx e viene aggiornato
#    da Jenkins a ogni deploy (switch Blue-Green).
docker volume create zenithstore-nginx-conf
docker run --rm \
    -v "${PWD}/docker/nginx/conf.d:/src:ro" \
    -v zenithstore-nginx-conf:/dest \
    alpine sh -c "cp /src/* /dest/"

# 6. Avvia monitoring stack (Jenkins, Prometheus, Grafana, Alertmanager)
docker compose -f docker/compose.monitoring.yml up -d

# 7. Configura Jenkins: vedi §3

# 8. Build iniziale delle immagini app (prima volta, manualmente)
#    Le variabili NEXT_PUBLIC_* sono baked nel bundle client al build time (non
#    modificabili a runtime via compose). Passare sempre i valori corretti via
#    --build-arg; i default nel Dockerfile sono fallback solo per build locali.
#    NEXT_PUBLIC_MOCK_PAYMENT=true abilita il pulsante 'Simula Pagamento' nel
#    checkout (impostare a false solo con un payment provider reale integrato).
docker build -t zenithstore-backend:latest ../profession-ai-web-development-zenithstore-app/backend/
docker build -t zenithstore-frontend:latest \
    --build-arg NEXT_PUBLIC_BACKEND_URL=http://localhost \
    --build-arg NEXT_PUBLIC_WS_URL=ws://localhost \
    --build-arg NEXT_PUBLIC_MOCK_PAYMENT=true \
    ../profession-ai-web-development-zenithstore-app/frontend/

# 9. Avvia Nginx
docker compose -f docker/compose.nginx.yml up -d

# 10. Primo deploy manuale dello stack Blue (stack iniziale)
export IMAGE_TAG=latest
export JWT_SECRET="<valore>"
export DB_PASSWORD="<valore>"
export MONGO_PASSWORD="<valore>"
export NEXTAUTH_SECRET="<valore>"
docker compose -f docker/compose.blue.yml up -d

# 11. Verifica
curl http://localhost/health          # backend via Nginx
```

### 2.3 Configurazione Jenkins

1. Aprire `http://localhost:8080` e completare il wizard di setup
2. Installare i plugin (Manage Jenkins → Plugin Manager):
   - Git
   - Pipeline
   - Docker Pipeline
   - JUnit
   - Email Extension Plugin
3. Configurare le credenziali (Manage Jenkins → Credentials → Global):

| ID | Tipo | Valore |
|---|---|---|
| `jwt-secret` | Secret text | JWT_SECRET (identico in BE e FE) |
| `db-password` | Secret text | Password MySQL root |
| `mongo-password` | Secret text | Password MongoDB admin |
| `nextauth-secret` | Secret text | NEXTAUTH_SECRET (min 32 caratteri) |
| `email-password` | Secret text | Password SMTP per notifiche Jenkins |

4. Configurare SMTP (Manage Jenkins → Configure System → E-mail Notification):
   - SMTP server, port, autenticazione, use-ssl

5. Creare un Pipeline job:
   - Definition: **Pipeline script from SCM**
   - SCM: Git → URL del repo infra
   - Branch: `main`
   - Script Path: `Jenkinsfile`

6. Configurare il webhook GitHub nel repo app:
   - Payload URL: `http://<IP-HOST>:8080/github-webhook/`
   - Content type: `application/json`
   - Events: `push`

---

## 3. Deploy Standard

La pipeline Jenkins si avvia automaticamente su ogni push al branch `main` del repo app.

Il flusso è:

```
Push → Jenkins trigger → Build → Test → DB Migration → Docker Build → Deploy Staging
                                                                              ↓
                                                          Approval manuale Jenkins UI
                                                                              ↓
                                                                   Deploy Production
```

### 3.1 Deploy manuale (emergenza / primo deploy)

```bash
# Dalla root del repo infra
export IMAGE_TAG=<commit-sha>
export JWT_SECRET="..." DB_PASSWORD="..." MONGO_PASSWORD="..." NEXTAUTH_SECRET="..."

bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging
```

### 3.2 Cosa fa switch-blue-green.sh

1. Legge lo stack attivo da `docker/nginx/conf.d/active_env`
2. Abbatte eventuale stack idle rimasto da deploy precedenti
3. Avvia stack idle con le nuove immagini (`IMAGE_TAG`)
4. Esegue `healthcheck.sh` (retry su BE:host e FE:host)
5. Se health check OK: copia `<idle>.conf` in `active.conf` + `nginx -s reload`
6. Attende la rollback window (default: 5 minuti)
7. Abbatte stack precedente

---

## 4. Rollback

### 4.1 Rollback automatico (pipeline)

Se `healthcheck.sh` fallisce dopo lo switch, la pipeline interrompe il deploy e
abbatte lo stack idle. Lo stack precedente rimane attivo senza interruzioni.

### 4.2 Rollback manuale (durante rollback window)

Finché il vecchio stack è ancora in esecuzione (entro i 5 minuti dalla rollback window):

```bash
bash scripts/rollback.sh
```

Lo script:
1. Legge lo stack attivo corrente
2. Re-switcha Nginx al precedente
3. Abbatte lo stack con problemi

### 4.3 Rollback dopo rollback window (vecchio stack già abbattuto)

Il vecchio stack è già down. Occorre re-deployare la versione precedente:

```bash
export IMAGE_TAG=<sha-versione-precedente>
export JWT_SECRET="..." DB_PASSWORD="..." MONGO_PASSWORD="..." NEXTAUTH_SECRET="..."
bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging
```

---

## 5. Monitoring

### 5.1 Grafana — Setup dashboard

1. Aprire `http://localhost:3100` (admin / password in `GRAFANA_PASSWORD` env)
2. Aggiungere Prometheus data source: URL = `http://prometheus:9090`
3. Importare dashboard suggerite:
   - **Node.js / Express**: ID 11159 (o simile)
   - **Custom ZenithStore**: creare da zero con le metriche sotto

### 5.2 Metriche chiave da monitorare

| Metrica | Query Prometheus | Soglia alert |
|---|---|---|
| Latency p95 | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` | > 2s |
| Error rate | `rate(http_errors_total[5m]) / rate(http_requests_total[5m])` | > 5% |
| Throughput | `rate(http_requests_total[5m])` | — |
| Uptime | `process_uptime_seconds` | — |
| Heap memory | `nodejs_heap_size_used_bytes` | — |
| Backend up | `up{job=~"zenithstore-backend.*"}` | = 0 → alert critico |

### 5.3 Alert attivi

Gli alert sono definiti in `docker/prometheus/alert.rules.yml` e notificati via
Alertmanager → email. Vedere §8 per configurare il receiver SMTP.

---

## 6. Comandi Utili

```bash
# Stato dei container
docker ps

# Log in tempo reale
docker logs -f be-blue
docker logs -f fe-blue
docker logs -f nginx

# Stato stack attivo
cat docker/nginx/conf.d/active_env     # "blue" o "green"

# Reload Nginx manuale (non fa switch, solo ricarica config esistente)
docker exec nginx nginx -s reload

# Verifica configurazione Nginx
docker exec nginx nginx -t

# Health check manuale su stack blue
bash scripts/healthcheck.sh blue

# Health check manuale su stack green
bash scripts/healthcheck.sh green

# Stop completo (tutti gli stack)
docker compose -f docker/compose.blue.yml down
docker compose -f docker/compose.green.yml down
docker compose -f docker/compose.nginx.yml down
docker compose -f docker/compose.monitoring.yml down
cd ../profession-ai-web-development-zenithstore-app && docker compose down
```

---

## 7. Procedure di Emergenza

### 7.1 Nginx non risponde

```bash
# Verifica che il container sia running
docker ps | grep nginx

# Verifica errori nella configurazione
docker exec nginx nginx -t

# Riavvio forzato
docker compose -f docker/compose.nginx.yml restart nginx
```

### 7.2 Backend down (entrambi gli stack)

```bash
# Controlla i log del BE attivo
docker logs be-blue   # o be-green

# Riavvio manuale
docker restart be-blue

# Se non bastasse: re-deploy completo
export IMAGE_TAG=latest
export JWT_SECRET="..." DB_PASSWORD="..." MONGO_PASSWORD="..." NEXTAUTH_SECRET="..."
ACTIVE=$(cat docker/nginx/conf.d/active_env)
docker compose -f "docker/compose.${ACTIVE}.yml" down
docker compose -f "docker/compose.${ACTIVE}.yml" up -d
```

### 7.3 Database non raggiungibile

```bash
# Dal repo app
cd ../profession-ai-web-development-zenithstore-app

# Stato DB
docker compose ps

# Log MySQL
docker compose logs mysql

# Log MongoDB
docker compose logs mongodb

# Riavvio DB (ATTENZIONE: breve downtime)
docker compose restart mysql
docker compose restart mongodb
```

### 7.4 Jenkins non risponde

```bash
# Riavvio Jenkins (i job in corso vengono persi)
docker compose -f docker/compose.monitoring.yml restart jenkins
```

---

## 8. Gestione Credenziali

### 8.1 Dove vivono i secrets

| Secret | Dove |
|---|---|
| JWT_SECRET | Jenkins Credentials (`jwt-secret`) |
| DB_PASSWORD | Jenkins Credentials (`db-password`) |
| MONGO_PASSWORD | Jenkins Credentials (`mongo-password`) |
| NEXTAUTH_SECRET | Jenkins Credentials (`nextauth-secret`) |
| SMTP password Jenkins | Jenkins Credentials (`email-password`) |
| SMTP password Alertmanager | Variabile `SMTP_PASSWORD` al boot del container |
| Grafana admin password | Variabile `GRAFANA_PASSWORD` al boot del container |

**I secrets non sono mai committati nel repository.**  
I file `.env.staging` e `.env.production` contengono placeholder, non valori reali.

### 8.2 Rotazione credenziali

1. Aggiornare il valore in Jenkins (Manage Jenkins → Credentials)
2. Per JWT_SECRET aggiornare anche il valore in Alertmanager e in tutti i container attivi:
   ```bash
   # Riavvio rolling dei container con il nuovo secret
   export JWT_SECRET="<nuovo-valore>"
   # ... altri secrets
   bash scripts/switch-blue-green.sh deploy latest staging
   ```
3. Il nuovo secret viene iniettato al prossimo deploy tramite `withCredentials`

---

## 9. Note Importanti

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

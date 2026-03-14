# ZenithStore Infra — Guida Operativa

> Infrastruttura CI/CD, deploy Blue-Green e monitoraggio per  
> [ZenithStore Online](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app)  
> — Progetto conclusivo del corso "DevOps e Gestione del ciclo di vita del software", Profession AI.

---

## Architettura

```
GitHub Push → Jenkins → Build & Test → Docker Build → Deploy Staging → (Approvazione) → Deploy Production
                                                             ↕ Blue-Green Switch via Nginx
                                  Prometheus ← /metrics BE → Grafana + Alertmanager
```

| Componente | Tecnologia | Porta host |
|---|---|---|
| Reverse Proxy | Nginx | 80 |
| Backend (blue) | Express.js + TypeScript | 3000 |
| Frontend (blue) | Next.js standalone | 3001 |
| Backend (green) | Express.js + TypeScript | 3010 |
| Frontend (green) | Next.js standalone | 3011 |
| Database relazionale | MySQL | 3306 |
| Database documentale | MongoDB | 27018 |
| CI/CD | Jenkins (immagine custom) | 8080 |
| Metrics | Prometheus | 9090 |
| Dashboard | Grafana | 3100 |
| Alerting | Alertmanager | 9093 |

---

## Struttura del Repository

```
Jenkinsfile                       Pipeline CI/CD dichiarativa (7 stage)
Dockerfile.jenkins                Jenkins LTS + Docker CE client
docker/
  compose.blue.yml                Stack Blue
  compose.green.yml               Stack Green (porte host 3010/3011)
  compose.nginx.yml               Nginx proxy
  compose.monitoring.yml          Jenkins + Prometheus + Grafana + Alertmanager
  nginx/
    nginx.conf                    Configurazione base (WebSocket support)
    conf.d/
      blue.conf / green.conf      Upstream per ciascuno stack
      active.conf                 Upstream attivo (runtime, aggiornato dagli script)
      active_env                  Stato corrente: "blue" o "green"
  prometheus/
    prometheus.yml                Scrape config + alertmanager ref
    alert.rules.yml               Regole alert (latency, error rate, uptime)
  alertmanager/
    alertmanager.yml              Notifiche email SMTP
scripts/
  switch-blue-green.sh            Orchestratore deploy: avvio idle → health check → switch Nginx → teardown old
  healthcheck.sh                  Retry curl su BE e FE dello stack idle
  rollback.sh                     Re-switch Nginx al precedente stack
docs/
  OPERATIONS.md                   Guida operativa completa (setup, emergenze, comandi)
```

---

## Pipeline CI/CD

La pipeline si avvia automaticamente su ogni push al branch `main` del repo app tramite webhook GitHub → Jenkins.

```
1. Checkout App      — clona il repo app in app/; calcola COMMIT_SHA
2. Build             — npm ci + npm run build (BE e FE in parallelo)
3. Test              — jest --ci (BE e FE in parallelo); pubblica report JUnit
4. DB Migration      — placeholder TypeORM (da abilitare)
5. Docker Build      — build immagini BE e FE con tag COMMIT_SHA + latest
6. Deploy Staging    — switch-blue-green.sh → health check → switch Nginx
7. Deploy Production — gate di approvazione manuale, poi stesso script
```

---

## Comandi Principali

### Avvio completo da zero

```bash
# 1. Database (dal repo app)
docker compose up -d

# 2. Build immagine Jenkins custom (una tantum)
docker build -t jenkins-custom -f Dockerfile.jenkins .

# 3. Crea e popola il volume condiviso Nginx ↔ Jenkins (una tantum)
#    Jenkins scrive active.conf in questo volume; Nginx lo legge.
docker volume create zenithstore-nginx-conf

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

# 4. Monitoring stack (Jenkins + Prometheus + Grafana + Alertmanager)
docker compose -f docker/compose.monitoring.yml up -d

# 5. Nginx
docker compose -f docker/compose.nginx.yml up -d

# 6. Build immagini Docker BE e FE (una tantum - dal repo app)
docker build \
    -t zenithstore-backend:latest \
    ./backend/

# Le variabili NEXT_PUBLIC_* sono baked nel bundle client al build time.
# Passarle sempre come --build-arg; i valori nel Dockerfile sono solo fallback locali.
# NEXT_PUBLIC_MOCK_PAYMENT=true abilita il pulsante 'Simula Pagamento' nel checkout
#   (impostare a false solo in caso di integrazione con un payment provider reale).
docker build \
    -t zenithstore-frontend:latest \
    --build-arg NEXT_PUBLIC_BACKEND_URL=http://localhost \
    --build-arg NEXT_PUBLIC_WS_URL=ws://localhost \
    --build-arg NEXT_PUBLIC_MOCK_PAYMENT=true \
    ./frontend/

# 7. Primo deploy manuale stack Blue
export IMAGE_TAG=latest DB_PASSWORD=rootpassword MONGO_PASSWORD=adminpassword JWT_SECRET=your-super-secret-jwt-key-change-this-in-production NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production
docker compose -f docker/compose.blue.yml up -d
```

### Redeploy forzato di uno stack (es. per ritestare una fix)

```bash
# Abbatti e riavvia lo stack blue con l'immagine corrente
export IMAGE_TAG=latest DB_PASSWORD=rootpassword MONGO_PASSWORD=adminpassword JWT_SECRET=your-super-secret-jwt-key-change-this-in-production NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production
docker compose -f docker/compose.blue.yml down
docker compose -f docker/compose.blue.yml up -d

# Verifica che i container siano tornati up
docker ps --filter "name=be-blue" --filter "name=fe-blue"

# Health check manuale
bash scripts/healthcheck.sh blue
```

> Se vuoi ritestare il green, sostituisci `blue` con `green` nei comandi sopra.

### Deploy manuale (emergenza)

```bash
export IMAGE_TAG=<commit-sha> DB_PASSWORD=rootpassword MONGO_PASSWORD=adminpassword JWT_SECRET=your-super-secret-jwt-key-change-this-in-production NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production
bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging
```

### Rollback immediato

```bash
bash scripts/rollback.sh
```

### Health check manuale

```bash
bash scripts/healthcheck.sh blue    # oppure green
```

### Stato corrente

```bash
cat docker/nginx/conf.d/active_env    # "blue" o "green"
docker ps                             # tutti i container attivi
```

### Stop completo

```bash
docker compose -f docker/compose.blue.yml down
docker compose -f docker/compose.green.yml down
docker compose -f docker/compose.nginx.yml down
docker compose -f docker/compose.monitoring.yml down
```

---

## Procedure di Emergenza

### Nginx non risponde
```bash
docker exec nginx nginx -t           # verifica config
docker compose -f docker/compose.nginx.yml restart nginx
```

### Backend down
```bash
docker logs be-blue                  # oppure be-green
docker restart be-blue
```

### Entrambi gli stack falliti
```bash
# Re-deploy forzato dello stack attivo
ACTIVE=$(cat docker/nginx/conf.d/active_env)
export IMAGE_TAG=latest DB_PASSWORD=rootpassword MONGO_PASSWORD=adminpassword JWT_SECRET=your-super-secret-jwt-key-change-this-in-production NEXTAUTH_SECRET=generate-a-random-secret-min-32-chars-for-nextauth-change-in-production
docker compose -f "docker/compose.${ACTIVE}.yml" down
docker compose -f "docker/compose.${ACTIVE}.yml" up -d
```

### Database non raggiungibile
```bash
# Dal repo app
docker compose logs mysql
docker compose restart mysql
```

---

## Credenziali Jenkins necessarie

Configurare in **Manage Jenkins → Credentials → Global** prima della prima esecuzione:

| ID | Tipo | Contenuto |
|---|---|---|
| `jwt-secret` | Secret text | JWT_SECRET (identico in BE e FE) |
| `db-password` | Secret text | MySQL root password |
| `mongo-password` | Secret text | MongoDB admin password |
| `nextauth-secret` | Secret text | NEXTAUTH_SECRET (min 32 caratteri) |
| `email-password` | Secret text | Password SMTP per notifiche Jenkins |

---

## Monitoraggio

| Servizio | URL | Credenziali |
|---|---|---|
| Jenkins | http://localhost:8080 | setup wizard |
| Grafana | http://localhost:3100 | admin / `$GRAFANA_PASSWORD` |
| Prometheus | http://localhost:9090 | — |
| Alertmanager | http://localhost:9093 | — |

Dashboard Grafana: aggiungere data source Prometheus (`http://prometheus:9090`).  
Metriche chiave: `http_request_duration_seconds`, `http_requests_total`, `http_errors_total`, `up`.

---

## Documenti di riferimento

- [docs/OPERATIONS.md](docs/OPERATIONS.md) — guida completa con setup, rotazione credenziali, note importanti
- [App repo](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app) — codice sorgente BE/FE

---

*Autore: Alberto Gelmi — Master in Web Development, Profession AI — 2026*

# ZenithStore Online INFRA

Progetto conclusivo del corso "DevOps e Gestione del ciclo di vita del software" (Repo INFRA).

## 📌 Specifiche del Progetto

### 🚀 Deploy Automatizzato di un E-commerce Senza Downtime

ZenithStore Online è un e-commerce in forte espansione che vende prodotti di alta gamma a livello internazionale. Con l'aumento esponenziale del traffico e delle transazioni, diventa fondamentale garantire che ogni aggiornamento della piattaforma avvenga senza interrompere il servizio, mantenendo sempre la disponibilità del sito.

L'azienda ha deciso di adottare una soluzione DevOps per automatizzare il processo di deploy delle nuove versioni dell'applicativo. Il sistema dovrà consentire rilasci continui, implementare rollback immediati in caso di errore e integrare strumenti di monitoraggio per verificare la stabilità e le prestazioni post-deploy.

### 🚀 Valore aggiunto del progetto

Questo progetto ti consentirà di mettere in pratica tecniche fondamentali per la gestione professionale dell'infrastruttura IT moderna: automazione dei rilasci, zero downtime deployments, gestione rapida delle anomalie e monitoraggio continuo delle applicazioni. Queste competenze sono essenziali per lavorare in qualsiasi ambiente che richieda alta disponibilità e affidabilità.

### ✅ Requisiti di alto livello

- ⚙️ **Pipeline di CI/CD**: progettare e implementare una pipeline di integrazione continua che automatizzi i processi di build, test e deploy.
- 📊 **Monitoraggio delle prestazioni**: integrare strumenti di monitoraggio (es. Prometheus, Grafana, o alternative) per tracciare metriche chiave come tempi di risposta, uptime, e error rate.
- 🔧 **Gestione configurazioni**: mantenere separati i file di configurazione ambientale per facilitare i deploy su ambienti diversi (sviluppo, staging, produzione).
- 📖 **Documentazione operativa**: redigere una breve guida operativa che descriva la pipeline, i comandi principali e le procedure di emergenza.

---

# ZenithStore Infra

> Infrastruttura CI/CD, deploy Blue-Green e monitoraggio per **ZenithStore Online**  
> Repo app: [profession-ai-web-development-zenithstore-app](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app)

---

## 🏗️ Architettura

```
GitHub Push ──► Jenkins ──► Build & Test ──► Docker Build ──► Deploy Staging
                                                                      │
                                                          Approvazione manuale
                                                                      │
                                                             Deploy Production
                                                    ↕ Blue-Green Switch via Nginx

                           Prometheus ◄── /metrics BE ──► Grafana + Alertmanager
```

---

## 🐳 Stack & Porte

| Componente | Tecnologia | Porta host |
|---|---|---:|
| Reverse Proxy | Nginx | **80** |
| Backend blue | Express.js + TypeScript | 3000 |
| Frontend blue | Next.js standalone | 3001 |
| Backend green | Express.js + TypeScript | 3010 |
| Frontend green | Next.js standalone | 3011 |
| Database relazionale | MySQL | 3306 |
| Database documentale | MongoDB | 27018 |
| CI/CD | Jenkins (immagine custom) | 8080 |
| Metrics | Prometheus | 9090 |
| Dashboard | Grafana | 3100 |
| Alerting | Alertmanager | 9093 |

> **Punto di accesso:** usa sempre `http://localhost` (porta 80, Nginx). Le porte dirette dei container sono esposte solo per health check e debug.

---

## ⚙️ Pipeline CI/CD (7 stage)

| # | Stage | Cosa fa |
|---|---|---|
| 1 | **Checkout App** | Clona il repo app; calcola `COMMIT_SHA` |
| 2 | **Build** | `npm ci` + `npm run build` (BE e FE in parallelo) |
| 3 | **Test** | `jest --ci` (BE e FE in parallelo); pubblica report JUnit |
| 4 | **DB Migration** | Placeholder TypeORM (da abilitare) |
| 5 | **Docker Build** | Build immagini BE e FE con tag `COMMIT_SHA` + `latest` |
| 6 | **Deploy Staging** | `switch-blue-green.sh` → health check → switch Nginx |
| 7 | **Deploy Production** | Gate di approvazione manuale, poi stesso script |

---

## 📁 Struttura del Repository

```
Jenkinsfile                       Pipeline CI/CD dichiarativa (7 stage)
Dockerfile.jenkins                Jenkins LTS + Docker CE client
docker/
  compose.db.yml                  MySQL + MongoDB (rete condivisa)
  compose.blue.yml                Stack Blue
  compose.green.yml               Stack Green (porte host 3010/3011)
  compose.nginx.yml               Nginx proxy
  compose.monitoring.yml          Jenkins + Prometheus + Grafana + Alertmanager
  nginx/conf.d/
    blue.conf / green.conf        Upstream per ciascuno stack
    active.conf                   Upstream attivo (aggiornato dagli script)
    active_env                    Stato corrente: "blue" o "green"
  prometheus/
    prometheus.yml                Scrape config + alertmanager ref
    alert.rules.yml               Regole alert (latency, error rate, uptime)
  alertmanager/alertmanager.yml   Notifiche email SMTP
  grafana/dashboards/
    zenithstore.json              Dashboard pronta all'uso (importabile)
scripts/
  switch-blue-green.sh            Orchestratore deploy: avvio idle → health check → switch → teardown
  healthcheck.sh                  Retry curl su BE e FE dello stack idle
  rollback.sh                     Re-switch Nginx al precedente stack
docs/
  OPERATIONS.md                   Guida operativa completa
```

---

## 🚀 Quick Start

```bash
# Clona entrambi i repository
git clone https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git
git clone https://github.com/albertogelmi/profession-ai-web-development-zenithstore-infra.git

# Entra nel repo infra, copia e compila il file .env
cd profession-ai-web-development-zenithstore-infra
cp .env.example .env   # → sostituisci tutti i "change-me-..."

# Avvia database, stack di monitoring e Nginx
docker compose -f docker/compose.db.yml up -d
docker compose -f docker/compose.monitoring.yml up -d
docker compose -f docker/compose.nginx.yml up -d

# Primo deploy stack Blue
docker compose -f docker/compose.blue.yml up -d
```

Per il setup completo (build immagini, configurazione Jenkins, webhook GitHub) consulta [docs/OPERATIONS.md](docs/OPERATIONS.md).

---

## ⚡ Comandi Rapidi

| Azione | Comando |
|---|---|
| Stack attivo | `MSYS_NO_PATHCONV=1 docker exec nginx cat /etc/nginx/conf.d/active_env` |
| Health check blue | `bash scripts/healthcheck.sh blue` |
| Rollback immediato | `bash scripts/rollback.sh` |
| Deploy manuale | `bash scripts/switch-blue-green.sh deploy $IMAGE_TAG staging` |
| Log backend live | `docker logs -f be-blue` |
| Stop completo | vedi OPERATIONS.md §8 |

---

## 📊 Monitoraggio

| Servizio | URL | Accesso |
|---|---|---|
| Jenkins | http://localhost:8080 | wizard primo avvio |
| Grafana | http://localhost:3100 | admin / `$GRAFANA_PASSWORD` |
| Prometheus | http://localhost:9090 | — |
| Alertmanager | http://localhost:9093 | — |

Dashboard inclusa: `docker/grafana/dashboards/zenithstore.json` — importabile direttamente da Grafana.  
Alert attivi: alta latenza (p95 > 2s), error rate > 5%, backend down.

---

## 📋 Note Operative

- 🔵🟢 **Blue-Green**: zero downtime. L'URL `http://localhost` rimane invariato ad ogni switch.
- ⏱️ **Rollback window**: 5 min (configurabile via `ROLLBACK_WINDOW_SECONDS`). Entro questa finestra `rollback.sh` ripristina lo stack precedente istantaneamente.
- 🗄️ **DB condiviso**: le migration devono essere backward-compatible (pattern expand-migrate-contract).
- 🔌 **WebSocket**: al reload Nginx le connessioni WebSocket vengono droppate (~1-2s); Socket.io si riconnette automaticamente.
- 🔒 **Secrets**: mai committati nel repository. Gestiti tramite Jenkins Credentials e variabili nel file `.env` (non versionato).

---

## 📖 Documentazione

- [docs/OPERATIONS.md](docs/OPERATIONS.md) — guida operativa completa: setup, Jenkins, Grafana, Prometheus, Alertmanager, emergenze, gestione credenziali
- [App repo](https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app) — codice sorgente BE/FE

---

*Autore: Alberto Gelmi — Master in Web Development, Profession AI — 2026*

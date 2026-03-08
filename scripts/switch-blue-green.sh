#!/bin/bash
# =============================================================================
# switch-blue-green.sh — Orchestratore Blue-Green Deploy
# =============================================================================
# Uso:
#   ./scripts/switch-blue-green.sh deploy  <IMAGE_TAG> <ENVIRONMENT>
#   ./scripts/switch-blue-green.sh rollback
#
# Variabili d'ambiente richieste (iniettate da Jenkins withCredentials):
#   JWT_SECRET, DB_PASSWORD, MONGO_PASSWORD, NEXTAUTH_SECRET
#
# Dipendenze:
#   - Docker CLI e Docker Compose plugin installati
#   - Container nginx in esecuzione (compose.nginx.yml)
#   - File docker/nginx/conf.d/active_env presente con valore "blue" o "green"
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CONF_DIR="${INFRA_DIR}/docker/nginx/conf.d"
COMPOSE_DIR="${INFRA_DIR}/docker"

ROLLBACK_WINDOW_SECONDS=${ROLLBACK_WINDOW_SECONDS:-300}   # 5 minuti default

ACTION="${1:-deploy}"
IMAGE_TAG="${2:-latest}"
ENVIRONMENT="${3:-staging}"

# ── Leggi lo stack attivo ─────────────────────────────────────────────────────
if [ ! -f "${CONF_DIR}/active_env" ]; then
    echo "❌ File ${CONF_DIR}/active_env non trovato. Setup iniziale richiesto."
    exit 1
fi

ACTIVE=$(cat "${CONF_DIR}/active_env")
if [ "$ACTIVE" = "blue" ]; then
    IDLE="green"
    IDLE_COMPOSE="compose.green.yml"
    ACTIVE_COMPOSE="compose.blue.yml"
else
    IDLE="blue"
    IDLE_COMPOSE="compose.blue.yml"
    ACTIVE_COMPOSE="compose.green.yml"
fi

echo "══════════════════════════════════════════════════════"
echo "  ZenithStore Blue-Green Deploy"
echo "  Azione:      $ACTION"
echo "  Image tag:   $IMAGE_TAG"
echo "  Environment: $ENVIRONMENT"
echo "  Stack attivo: $ACTIVE → Stack idle: $IDLE"
echo "══════════════════════════════════════════════════════"

# =============================================================================
# DEPLOY
# =============================================================================
if [ "$ACTION" = "deploy" ]; then

    # Esporta variabili per docker compose
    export IMAGE_TAG
    export JWT_SECRET DB_PASSWORD MONGO_PASSWORD NEXTAUTH_SECRET

    # 1. Rimuovi eventuale stack idle rimasto da un deploy precedente fallito
    echo "🧹 Cleanup stack idle ($IDLE) eventualmente già in esecuzione..."
    docker compose -f "${COMPOSE_DIR}/${IDLE_COMPOSE}" down --remove-orphans 2>/dev/null || true

    # 2. Avvia stack idle con le nuove immagini
    echo "🚀 Avvio stack $IDLE (IMAGE_TAG=$IMAGE_TAG)..."
    docker compose -f "${COMPOSE_DIR}/${IDLE_COMPOSE}" up -d

    # 3. Attendi che i container passino allo stato healthy (max 60s)
    echo "⏳ Attendo avvio container ($IDLE)..."
    sleep 15

    # 4. Health check sulle porte host dello stack idle
    echo "🏥 Health check su stack $IDLE..."
    if ! bash "${SCRIPT_DIR}/healthcheck.sh" "$IDLE"; then
        echo "❌ Health check fallito su stack $IDLE — interrompo deploy e pulisco."
        docker compose -f "${COMPOSE_DIR}/${IDLE_COMPOSE}" down
        exit 1
    fi

    # 5. Switch Nginx: copia upstream config e reload
    echo "🔄 Switch Nginx: $ACTIVE → $IDLE"
    cp "${CONF_DIR}/${IDLE}.conf" "${CONF_DIR}/active.conf"
    echo "$IDLE" > "${CONF_DIR}/active_env"
    docker exec nginx nginx -s reload
    echo "✅ Switch completato — stack attivo: $IDLE"

    # 6. Rollback window: tieni il vecchio stack in esecuzione per N secondi
    echo "⏳ Rollback window: ${ROLLBACK_WINDOW_SECONDS}s."
    echo "   In questo intervallo puoi fare rollback con: ./scripts/rollback.sh"
    echo "   Stack $ACTIVE rimane in esecuzione fino alla fine della window."
    sleep "$ROLLBACK_WINDOW_SECONDS"

    # 7. Stop stack precedente
    echo "🛑 Stop stack precedente ($ACTIVE)..."
    docker compose -f "${COMPOSE_DIR}/${ACTIVE_COMPOSE}" down
    echo "✅ Deploy completato — stack attivo: $IDLE (tag: $IMAGE_TAG)"

# =============================================================================
# ROLLBACK
# =============================================================================
elif [ "$ACTION" = "rollback" ]; then
    bash "${SCRIPT_DIR}/rollback.sh"

else
    echo "Uso: $0 deploy <IMAGE_TAG> <ENVIRONMENT> | rollback"
    exit 1
fi

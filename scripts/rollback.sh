#!/bin/bash
# =============================================================================
# rollback.sh — Re-switch Nginx allo stack precedente
# =============================================================================
# Può essere eseguito:
#   - Manualmente dall'operatore in caso di emergenza
#   - Dalla pipeline Jenkins se il health check post-switch fallisce
#
# Lo script:
#   1. Legge lo stack attivo da active_env
#   2. Copia la config del precedente stack in active.conf
#   3. Aggiorna active_env
#   4. Fa reload graceful di Nginx (nessun drop di connessioni HTTP)
#   5. Abbatte lo stack che è stato rollbackato
#
# Uso: ./scripts/rollback.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CONF_DIR="${INFRA_DIR}/docker/nginx/conf.d"
COMPOSE_DIR="${INFRA_DIR}/docker"

if [ ! -f "${CONF_DIR}/active_env" ]; then
    echo "❌ File ${CONF_DIR}/active_env non trovato."
    exit 1
fi

CURRENT=$(cat "${CONF_DIR}/active_env")
PREVIOUS=$([ "$CURRENT" = "blue" ] && echo "green" || echo "blue")

echo "══════════════════════════════════════════════════════"
echo "  ZenithStore Rollback"
echo "  Stack attivo:    $CURRENT"
echo "  Rollback verso:  $PREVIOUS"
echo "══════════════════════════════════════════════════════"

# 1. Switch Nginx al precedente stack
echo "🔄 Ripristino Nginx → stack $PREVIOUS..."
cp "${CONF_DIR}/${PREVIOUS}.conf" "${CONF_DIR}/active.conf"
echo "$PREVIOUS" > "${CONF_DIR}/active_env"
docker exec nginx nginx -s reload
echo "✅ Nginx ora punta a stack $PREVIOUS"

# 2. Abbatti lo stack corrente (quello che ha causato il problema)
echo "🛑 Stop stack $CURRENT..."
FAILED_COMPOSE="compose.${CURRENT}.yml"
docker compose -f "${COMPOSE_DIR}/${FAILED_COMPOSE}" down 2>/dev/null || true

echo "══════════════════════════════════════════════════════"
echo "  ✅ Rollback completato — stack attivo: $PREVIOUS"
echo "══════════════════════════════════════════════════════"

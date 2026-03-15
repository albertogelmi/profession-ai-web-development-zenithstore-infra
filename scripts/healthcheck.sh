#!/bin/bash
# =============================================================================
# healthcheck.sh — Smoke test post-deploy
# =============================================================================
# Uso: ./scripts/healthcheck.sh <STACK>   (blue|green)
# Exit 0 = OK, Exit 1 = failure
#
# Controlla BE su porta host e FE su porta host dello stack indicato.
# Porte host:
#   blue:  BE → 3000,  FE → 3001
#   green: BE → 3010,  FE → 3011
# =============================================================================

set -euo pipefail

STACK="${1:-blue}"
MAX_RETRIES="${MAX_RETRIES:-12}"     # 12 tentativi × 5s = 60s max
RETRY_DELAY="${RETRY_DELAY:-5}"

if [ "$STACK" = "blue" ]; then
    BE_PORT=3000
    FE_PORT=3001
elif [ "$STACK" = "green" ]; then
    BE_PORT=3010
    FE_PORT=3011
else
    echo "❌ Stack non valido: $STACK (usare 'blue' o 'green')"
    exit 1
fi

# ── Determina il target host ──────────────────────────────────────────────────
# Quando lo script gira dentro il container Jenkins, 'localhost' è il container
# stesso — i container blue/green non sono raggiungibili sulle porte host.
# In quel caso si usa il nome container sulla Docker network (porta interna 3000/3001).
# Quando gira direttamente sull'host si usano le porte host (localhost:300x).
if [ -f /.dockerenv ]; then
    # Siamo dentro un container: usa nome container + porta interna
    BE_HOST="be-${STACK}"
    FE_HOST="fe-${STACK}"
    BE_PORT=3000
    FE_PORT=3001
else
    # Siamo sull'host: usa localhost + porta host
    BE_HOST="localhost"
    FE_HOST="localhost"
fi

# ── Helper: controlla un endpoint con retry ───────────────────────────────────
check_endpoint() {
    local URL="$1"
    local LABEL="$2"
    local ATTEMPT=0

    echo "🔍 Controllo $LABEL → $URL"
    while [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; do
        ATTEMPT=$((ATTEMPT + 1))
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "  ✅ $LABEL OK (HTTP $HTTP_CODE — tentativo $ATTEMPT/$MAX_RETRIES)"
            return 0
        fi
        echo "  ⏳ $LABEL non pronto (HTTP $HTTP_CODE — tentativo $ATTEMPT/$MAX_RETRIES) — attendo ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    done

    echo "  ❌ $LABEL non risponde dopo $MAX_RETRIES tentativi"
    return 1
}

# ── Esegui checks ─────────────────────────────────────────────────────────────
FAILED=0

check_endpoint "http://${BE_HOST}:${BE_PORT}/health"     "Backend  ($STACK)" || FAILED=1
check_endpoint "http://${FE_HOST}:${FE_PORT}/api/health" "Frontend ($STACK)" || FAILED=1

if [ "$FAILED" -eq 1 ]; then
    echo "❌ Health check fallito per stack $STACK"
    exit 1
fi

echo "✅ Health check OK per stack $STACK (BE :${BE_PORT}, FE :${FE_PORT})"

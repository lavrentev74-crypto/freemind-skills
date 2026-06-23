#!/bin/bash
# ============================================================
#  Caddy с caddy-docker-proxy — reverse proxy + auto SSL
#  Создаёт Docker сеть infra и запускает Caddy
# ============================================================

set -euo pipefail

LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/caddy-report.json"
CADDY_DIR="/root/caddy"
mkdir -p "$LOG_DIR" "$CADDY_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "network": "infra",
  "ports": "80, 443",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Проверка: уже стоит? ────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^caddy$"; then
  log "Caddy уже запущен"
  write_report "already_running"
  cat "$REPORT_FILE"
  exit 0
fi

# ── Step 1: Docker сеть infra ───────────────────────────────

info "Step 1/3: Создаю сеть infra..."

if docker network inspect infra &>/dev/null; then
  log "Сеть infra уже существует"
else
  docker network create infra
  log "Сеть infra создана"
fi

# ── Step 2: compose.yaml ────────────────────────────────────

info "Step 2/3: Генерирую compose..."

touch "$CADDY_DIR/extra.caddyfile"

cat > "$CADDY_DIR/compose.yaml" << 'EOF'
services:
  caddy:
    image: lucaslorentz/caddy-docker-proxy:ci-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - caddy_data:/data
      - caddy_config:/config
      - /root/caddy/extra.caddyfile:/etc/caddy/extra.caddyfile:ro
    networks:
      - infra
    environment:
      - CADDY_INGRESS_NETWORKS=infra
      - CADDY_DOCKER_CADDYFILE_PATH=/etc/caddy/extra.caddyfile

volumes:
  caddy_data:
  caddy_config:

networks:
  infra:
    external: true
EOF

log "compose.yaml создан"

# ── Step 3: Запуск ──────────────────────────────────────────

info "Step 3/3: Запускаю Caddy..."

cd "$CADDY_DIR"
docker compose pull -q
docker compose up -d

# Ждём запуска (до 30 сек)
for i in $(seq 1 30); do
  if docker ps --format '{{.Names}}' | grep -q "^caddy$"; then
    CADDY_STATUS=$(docker inspect caddy --format '{{.State.Status}}' 2>/dev/null)
    if [ "$CADDY_STATUS" = "running" ]; then
      log "Caddy запущен"
      break
    fi
  fi
  sleep 1
done

# Финальная проверка
if ! docker ps --format '{{.Names}}' | grep -q "^caddy$"; then
  err "Caddy не запустился"
  docker logs caddy --tail 20 2>/dev/null || true
  write_report "error" "Caddy не запустился"
  cat "$REPORT_FILE"
  exit 1
fi

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"
log "Caddy готов. Отчёт: $REPORT_FILE"
cat "$REPORT_FILE"

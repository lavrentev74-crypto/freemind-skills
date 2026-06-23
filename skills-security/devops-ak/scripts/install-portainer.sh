#!/bin/bash
# ============================================================
#  Portainer CE — Docker management UI
#  Caddy labels для автоматического SSL
#  Адаптировано из old/scripts/install-portainer.sh
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────

DOMAIN="${1:?Использование: $0 DOMAIN SUBDOMAIN}"
SUBDOMAIN="${2:-port}"
ADMIN_EMAIL="${3:-}"
# Логин: имя_port (из email) или portainer_admin
if [ -n "$ADMIN_EMAIL" ]; then
  ADMIN_USER="$(echo "$ADMIN_EMAIL" | cut -d@ -f1)_port"
else
  ADMIN_USER="portainer_admin"
fi

FQDN="${SUBDOMAIN}.${DOMAIN}"
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/portainer-report.json"
PORTAINER_DIR="/root/portainer"
mkdir -p "$LOG_DIR" "$PORTAINER_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "url": "https://$FQDN",
  "login": "$ADMIN_USER",
  "password": "${ADMIN_PASS:-}",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Проверка: уже стоит? ────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
  log "Portainer уже запущен"
  # Читаем старый пароль из отчёта если есть
  if [ -f "$REPORT_FILE" ]; then
    ADMIN_PASS=$(grep -o '"password": "[^"]*"' "$REPORT_FILE" | cut -d'"' -f4)
  fi
  write_report "already_running"
  cat "$REPORT_FILE"
  exit 0
fi

# ── Step 1: Генерация credentials ───────────────────────────

info "Step 1/3: Генерирую credentials..."
ADMIN_PASS=$(openssl rand -hex 12)
log "Credentials сгенерированы"

# ── Step 2: compose.yaml ────────────────────────────────────

info "Step 2/3: Генерирую compose..."

cat > "$PORTAINER_DIR/compose.yaml" << EOF
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    networks:
      - infra
    labels:
      caddy: "$FQDN"
      caddy.reverse_proxy: "{{upstreams 9000}}"
    healthcheck:
      test: ["CMD-SHELL", "/bin/sh -c 'cat < /dev/null > /dev/tcp/localhost/9000'"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s

volumes:
  portainer_data:

networks:
  infra:
    external: true
EOF

log "compose.yaml создан"

# ── Step 3: Запуск и настройка ──────────────────────────────

info "Step 3/3: Запускаю Portainer..."

cd "$PORTAINER_DIR"
docker compose pull -q
docker compose up -d

# Ждём запуска (Portainer стартует медленно — ждём до 90 сек)
info "Ожидаю готовности Portainer API..."
PORTAINER_READY=false
for i in $(seq 1 90); do
  # Проверяем через docker exec — надёжнее чем curl с хоста
  HTTP_CODE=$(docker exec portainer wget -qO- -S http://localhost:9000/api/status 2>&1 | grep "HTTP/" | awk '{print $2}' || echo "0")
  if [ "$HTTP_CODE" = "200" ]; then
    PORTAINER_READY=true
    log "Portainer API готов ($i сек)"
    break
  fi
  # Fallback: пробуем curl с хоста через Docker network
  if curl -sk --max-time 2 "http://$(docker inspect portainer --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'):9000/api/status" &>/dev/null; then
    PORTAINER_READY=true
    log "Portainer API готов через Docker network ($i сек)"
    break
  fi
  if [ $((i % 15)) -eq 0 ]; then
    info "Ещё ждём Portainer... ($i сек)"
  fi
  sleep 1
done

# Получаем внутренний IP Portainer для API запросов
PORTAINER_IP=$(docker inspect portainer --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)

# Создание admin аккаунта через API
info "Создаю admin аккаунт..."
sleep 3  # Доп. пауза для полной инициализации

ADMIN_RESPONSE=""
if [ -n "$PORTAINER_IP" ]; then
  ADMIN_RESPONSE=$(curl -sk --max-time 10 -X POST "http://${PORTAINER_IP}:9000/api/users/admin/init" \
    -H "Content-Type: application/json" \
    -d "{\"Username\":\"$ADMIN_USER\",\"Password\":\"$ADMIN_PASS\"}" 2>/dev/null || echo "")
fi

# Fallback через docker exec
if [ -z "$ADMIN_RESPONSE" ] || ! echo "$ADMIN_RESPONSE" | grep -q '"Id"'; then
  ADMIN_RESPONSE=$(docker exec portainer wget -qO- --post-data="{\"Username\":\"$ADMIN_USER\",\"Password\":\"$ADMIN_PASS\"}" \
    --header="Content-Type: application/json" \
    "http://localhost:9000/api/users/admin/init" 2>/dev/null || echo "")
fi

if echo "$ADMIN_RESPONSE" | grep -q '"Id"'; then
  log "Admin аккаунт создан"
elif echo "$ADMIN_RESPONSE" | grep -qi "already initialized\|conflict"; then
  log "Admin аккаунт уже существует"
else
  err "Не удалось создать admin (ответ: $ADMIN_RESPONSE). Создайте вручную: https://$FQDN"
fi

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"
log "Portainer готов: https://$FQDN"
cat "$REPORT_FILE"

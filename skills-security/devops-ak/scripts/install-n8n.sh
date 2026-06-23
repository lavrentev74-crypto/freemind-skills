#!/bin/bash
# ============================================================
#  n8n + PostgreSQL — Workflow automation
#  Caddy labels, сеть infra
#  Адаптировано из old/scripts/install-n8n.sh
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────

DOMAIN="${1:?Использование: $0 DOMAIN SUBDOMAIN EMAIL FIRST_NAME LAST_NAME}"
SUBDOMAIN="${2:-n8n}"
ADMIN_EMAIL="${3:-admin@${DOMAIN}}"
FIRST_NAME="${4:-Admin}"
LAST_NAME="${5:-User}"

FQDN="${SUBDOMAIN}.${DOMAIN}"
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/n8n-report.json"
N8N_DIR="/root/n8n"
mkdir -p "$LOG_DIR" "$N8N_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "url": "https://$FQDN",
  "email": "$ADMIN_EMAIL",
  "password": "${N8N_PASS:-}",
  "postgres_password": "${PG_PASS:-}",
  "postgres_user": "n8n",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Проверка: уже стоит? ────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^n8n$"; then
  log "n8n уже запущен"
  if [ -f "$REPORT_FILE" ]; then
    N8N_PASS=$(grep -o '"password": "[^"]*"' "$REPORT_FILE" | head -1 | cut -d'"' -f4)
    PG_PASS=$(grep -o '"postgres_password": "[^"]*"' "$REPORT_FILE" | cut -d'"' -f4)
  fi
  write_report "already_running"
  cat "$REPORT_FILE"
  exit 0
fi

# ── Step 1: Генерация credentials ───────────────────────────

info "Step 1/4: Генерирую credentials..."
# n8n требует: минимум 1 uppercase, 1 цифра, 8+ символов
N8N_PASS="N$(openssl rand -hex 6)x9K"
PG_PASS=$(openssl rand -hex 16)
PG_ROOT_PASS=$(openssl rand -hex 16)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 24)
log "Credentials сгенерированы"

# ── Step 2: compose.yaml ────────────────────────────────────

info "Step 2/4: Генерирую compose..."

cat > "$N8N_DIR/compose.yaml" << EOF
services:
  n8n-postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: $PG_ROOT_PASS
      POSTGRES_DB: n8n
    volumes:
      - n8n_pg_data:/var/lib/postgresql/data
      - ./init-db.sh:/docker-entrypoint-initdb.d/init-db.sh:ro
    networks:
      - infra
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  n8n:
    image: docker.n8n.io/n8nio/n8n
    container_name: n8n
    restart: unless-stopped
    depends_on:
      n8n-postgres:
        condition: service_healthy
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: n8n-postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: n8n
      DB_POSTGRESDB_PASSWORD: $PG_PASS
      N8N_PROTOCOL: https
      N8N_HOST: $FQDN
      WEBHOOK_URL: https://$FQDN/
      N8N_ENCRYPTION_KEY: $N8N_ENCRYPTION_KEY
      GENERIC_TIMEZONE: Europe/Moscow
      TZ: Europe/Moscow
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - infra
    labels:
      caddy: "$FQDN"
      caddy.reverse_proxy: "{{upstreams 5678}}"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  n8n_pg_data:
  n8n_data:

networks:
  infra:
    external: true
EOF

# Скрипт инициализации БД (создание пользователя n8n)
cat > "$N8N_DIR/init-db.sh" << EOF
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "n8n" <<-EOSQL
  DO \\\$\\\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'n8n') THEN
      CREATE ROLE n8n WITH LOGIN PASSWORD '$PG_PASS';
    END IF;
  END
  \\\$\\\$;
  GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
  GRANT ALL ON SCHEMA public TO n8n;
EOSQL
EOF
chmod +x "$N8N_DIR/init-db.sh"

log "compose.yaml и init-db.sh созданы"

# ── Step 3: Запуск ──────────────────────────────────────────

info "Step 3/4: Запускаю n8n..."

cd "$N8N_DIR"
docker compose pull -q
docker compose up -d

# Ждём запуска — проверяем через Docker network IP, не через localhost хоста
info "Ожидаю запуска n8n (до 3 мин)..."
N8N_READY=false
for i in $(seq 1 180); do
  # Получаем IP контейнера n8n в сети infra
  N8N_IP=$(docker inspect n8n --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
  if [ -n "$N8N_IP" ]; then
    if curl -sk --max-time 2 "http://${N8N_IP}:5678/healthz" &>/dev/null; then
      N8N_READY=true
      log "n8n отвечает ($i сек)"
      break
    fi
  fi
  # Fallback: проверяем через docker exec
  if docker exec n8n wget -qO- --timeout=2 http://localhost:5678/healthz &>/dev/null; then
    N8N_READY=true
    N8N_IP="localhost"
    log "n8n отвечает через docker exec ($i сек)"
    break
  fi
  if [ $((i % 15)) -eq 0 ]; then
    N8N_STATUS=$(docker inspect n8n --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    info "Ещё ждём... ($i сек, health: $N8N_STATUS)"
  fi
  sleep 1
done

if [ "$N8N_READY" = false ]; then
  err "n8n не ответил за 3 минуты. Проверьте логи: docker logs n8n"
fi

# ── Step 4: Создание admin ──────────────────────────────────

info "Step 4/4: Создаю admin..."

# Доп. пауза — n8n может отвечать на healthz но ещё инициализировать БД
sleep 10

# Получаем IP для API запросов
N8N_IP=$(docker inspect n8n --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)

SETUP_RESPONSE=""
if [ -n "$N8N_IP" ]; then
  SETUP_RESPONSE=$(curl -sk --max-time 15 -X POST "http://${N8N_IP}:5678/rest/owner/setup" \
    -H "Content-Type: application/json" \
    -d "{
      \"email\": \"$ADMIN_EMAIL\",
      \"password\": \"$N8N_PASS\",
      \"firstName\": \"$FIRST_NAME\",
      \"lastName\": \"$LAST_NAME\"
    }" 2>/dev/null || echo "")
fi

# Fallback через docker exec
if [ -z "$SETUP_RESPONSE" ] || ! echo "$SETUP_RESPONSE" | grep -q '"id"'; then
  SETUP_RESPONSE=$(docker exec n8n wget -qO- --timeout=15 \
    --post-data="{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$N8N_PASS\",\"firstName\":\"$FIRST_NAME\",\"lastName\":\"$LAST_NAME\"}" \
    --header="Content-Type: application/json" \
    "http://localhost:5678/rest/owner/setup" 2>/dev/null || echo "")
fi

if echo "$SETUP_RESPONSE" | grep -q '"id"'; then
  log "Admin аккаунт создан"
elif echo "$SETUP_RESPONSE" | grep -qi "already set up\|exists"; then
  log "Admin уже существует"
else
  err "Не удалось создать admin автоматически. Создайте вручную: https://$FQDN"
  info "Ответ API: $SETUP_RESPONSE"
fi

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"
log "n8n готов: https://$FQDN"
cat "$REPORT_FILE"

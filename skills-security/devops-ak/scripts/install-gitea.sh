#!/bin/bash
# ============================================================
#  Gitea — self-hosted Git + Container Registry
#  Caddy labels для автоматического SSL
#  PostgreSQL 16 в качестве БД
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────

DOMAIN="${1:?Использование: $0 DOMAIN SUBDOMAIN}"
SUBDOMAIN="${2:-git}"

FQDN="${SUBDOMAIN}.${DOMAIN}"
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/gitea-report.json"
GITEA_DIR="/root/gitea"
mkdir -p "$LOG_DIR" "$GITEA_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

ADMIN_EMAIL="${3:-}"
# Логин: имя_git (из email) или gitea_admin
if [ -n "$ADMIN_EMAIL" ]; then
  ADMIN_USER="$(echo "$ADMIN_EMAIL" | cut -d@ -f1)_git"
else
  ADMIN_USER="gitea_admin"
  ADMIN_EMAIL="admin@${DOMAIN}"
fi

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "url": "https://$FQDN",
  "admin_user": "$ADMIN_USER",
  "admin_password": "${ADMIN_PASS:-}",
  "admin_email": "$ADMIN_EMAIL",
  "db_user": "${DB_USER:-}",
  "db_password": "${DB_PASS:-}",
  "ssh_port": 222,
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Проверка: уже стоит? ────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^gitea$"; then
  log "Gitea уже запущен"
  if [ -f "$REPORT_FILE" ]; then
    DB_USER=$(grep -o '"db_user": "[^"]*"' "$REPORT_FILE" | cut -d'"' -f4)
    DB_PASS=$(grep -o '"db_password": "[^"]*"' "$REPORT_FILE" | cut -d'"' -f4)
  else
    DB_USER="unknown"
    DB_PASS="unknown"
  fi
  write_report "already_running"
  cat "$REPORT_FILE"
  exit 0
fi

# ── Step 1: Генерация credentials ───────────────────────────

info "Step 1/4: Генерирую credentials..."
DB_USER="gitea_$(openssl rand -hex 4)"
DB_PASS=$(openssl rand -hex 16)
ADMIN_PASS="G$(openssl rand -hex 8)x1K"
log "Credentials сгенерированы"

# ── Step 2: compose.yaml ────────────────────────────────────

info "Step 2/3: Генерирую compose..."

cat > "$GITEA_DIR/.env" << EOF
GITEA_DB_USER=$DB_USER
GITEA_DB_PASS=$DB_PASS
GITEA_DOMAIN=$FQDN
EOF

cat > "$GITEA_DIR/compose.yaml" << EOF
services:
  server:
    image: docker.gitea.com/gitea:latest
    container_name: gitea
    restart: unless-stopped
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=gitea-db:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=\${GITEA_DB_USER}
      - GITEA__database__PASSWD=\${GITEA_DB_PASS}
      - GITEA__server__DOMAIN=\${GITEA_DOMAIN}
      - GITEA__server__ROOT_URL=https://\${GITEA_DOMAIN}/
      - GITEA__server__SSH_DOMAIN=\${GITEA_DOMAIN}
      - GITEA__server__SSH_PORT=222
      - GITEA__server__SSH_LISTEN_PORT=22
      - GITEA__packages__ENABLE=true
      - GITEA__packages__CONTAINER__ENABLED=true
      - GITEA__packages__CONTAINER__REGISTRY_HOST=\${GITEA_DOMAIN}
    volumes:
      - ./data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "222:22"
    networks:
      - infra
      - gitea-internal
    labels:
      caddy: "\${GITEA_DOMAIN}"
      caddy.reverse_proxy: "{{upstreams 3000}}"
    depends_on:
      gitea-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

  gitea-db:
    image: postgres:16
    container_name: gitea-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=\${GITEA_DB_USER}
      - POSTGRES_PASSWORD=\${GITEA_DB_PASS}
      - POSTGRES_DB=gitea
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - gitea-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${GITEA_DB_USER} -d gitea"]
      interval: 5s
      timeout: 5s
      retries: 10

networks:
  infra:
    external: true
  gitea-internal:
    driver: bridge
EOF

log "compose.yaml создан"

# ── Step 3: Запуск ──────────────────────────────────────────

info "Step 3/3: Запускаю Gitea..."

cd "$GITEA_DIR"
docker compose pull -q
docker compose up -d

# UFW: открываем 222 для Gitea SSH (F-011)
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 222/tcp >/dev/null 2>&1 && log "UFW: порт 222 открыт для Gitea SSH"
fi

# Ждём запуска
info "Ожидаю готовности Gitea..."
for i in $(seq 1 60); do
  if docker exec gitea curl -sf http://localhost:3000/api/healthz &>/dev/null; then
    log "Gitea готов ($i сек)"
    break
  fi
  if [ $((i % 15)) -eq 0 ]; then
    info "Ещё ждём Gitea... ($i сек)"
  fi
  sleep 1
done

# ── Step 4: Создание admin ──────────────────────────────────

info "Step 4/4: Настройка и создание admin..."

# Генерируем секрет и ставим INSTALL_LOCK
SECRET_KEY=$(openssl rand -hex 32)
docker exec gitea sed -i "s/INSTALL_LOCK = false/INSTALL_LOCK = true/" /data/gitea/conf/app.ini
docker exec gitea sed -i "s/SECRET_KEY = /SECRET_KEY = $SECRET_KEY/" /data/gitea/conf/app.ini

# Отключаем регистрацию для безопасности
docker exec gitea sed -i "s/DISABLE_REGISTRATION = false/DISABLE_REGISTRATION = true/" /data/gitea/conf/app.ini

# Рестарт чтобы подхватило конфиг
docker restart gitea
sleep 10

# Ждём готовности
for i in $(seq 1 30); do
  if docker exec gitea curl -sf http://localhost:3000/api/v1/version &>/dev/null; then
    break
  fi
  sleep 1
done

# Создаём admin через CLI (от user git — Gitea не работает от root)
ADMIN_CREATED=false
RESULT=$(docker exec --user git gitea gitea admin user create \
  --config /data/gitea/conf/app.ini \
  --username "$ADMIN_USER" \
  --password "$ADMIN_PASS" \
  --email "$ADMIN_EMAIL" \
  --admin \
  --must-change-password=false 2>&1 || echo "")

if echo "$RESULT" | grep -qi "created\|success"; then
  ADMIN_CREATED=true
  log "Admin аккаунт создан: $ADMIN_USER"
elif echo "$RESULT" | grep -qi "already exists"; then
  ADMIN_CREATED=true
  log "Admin уже существует"
else
  err "Не удалось создать admin: $RESULT"
fi

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"
log "Gitea готов: https://$FQDN"
log "Login: $ADMIN_USER / $ADMIN_PASS"
log "SSH: ssh -p 222 git@$FQDN"
cat "$REPORT_FILE"

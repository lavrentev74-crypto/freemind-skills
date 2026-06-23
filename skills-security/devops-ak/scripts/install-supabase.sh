#!/bin/bash
# ============================================================
#  Supabase Self-Hosted — BaaS (PostgreSQL + Auth + API)
#  Caddy labels, сеть infra
#  Адаптировано из old/scripts/install-supabase.sh
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────

DOMAIN="${1:?Использование: $0 DOMAIN SUBDOMAIN [ORG_NAME] [PROJECT_NAME] [ADMIN_EMAIL]}"
SUBDOMAIN="${2:-sup}"
ORG_NAME="${3:-Default Organization}"
PROJECT_NAME="${4:-Default Project}"
ADMIN_EMAIL="${5:-}"

FQDN="${SUBDOMAIN}.${DOMAIN}"
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/supabase-report.json"
SUPABASE_DIR="/root/supabase"
mkdir -p "$LOG_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "url": "https://$FQDN",
  "dashboard_user": "${DASHBOARD_USER:-supabase}",
  "dashboard_password": "${DASHBOARD_PASS:-}",
  "postgres_password": "${PG_PASS:-}",
  "jwt_secret": "${JWT_SECRET:-}",
  "anon_key": "${ANON_KEY:-}",
  "service_role_key": "${SERVICE_ROLE_KEY:-}",
  "api_url": "https://$FQDN",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Проверка: уже стоит? ────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "supabase-studio"; then
  log "Supabase уже запущен"
  if [ -f "$REPORT_FILE" ]; then
    cat "$REPORT_FILE"
  fi
  exit 0
fi

# ── Проверка ресурсов ───────────────────────────────────────

AVAILABLE_RAM=$(free -m | awk '/Mem:/ {print $7}')
AVAILABLE_DISK=$(df -m / | awk 'NR==2 {print $4}')

if [ "$AVAILABLE_RAM" -lt 800 ]; then
  err "Мало RAM: ${AVAILABLE_RAM}MB свободно (нужно минимум 800MB)"
  write_report "error" "Недостаточно RAM: ${AVAILABLE_RAM}MB"
  cat "$REPORT_FILE"
  exit 1
fi

if [ "$AVAILABLE_DISK" -lt 3000 ]; then
  err "Мало диска: ${AVAILABLE_DISK}MB свободно (нужно минимум 3GB)"
  write_report "error" "Недостаточно места на диске: ${AVAILABLE_DISK}MB"
  cat "$REPORT_FILE"
  exit 1
fi

# ── Step 1: Клонирование Supabase ───────────────────────────

info "Step 1/5: Клонирую Supabase..."

if [ -d "$SUPABASE_DIR/docker" ]; then
  log "Репозиторий уже есть"
  cd "$SUPABASE_DIR"
  git pull --quiet 2>/dev/null || true
else
  git clone --depth 1 https://github.com/supabase/supabase.git "$SUPABASE_DIR"
fi

cd "$SUPABASE_DIR/docker"
log "Supabase клонирован"

# ── Step 2: Генерация credentials ───────────────────────────

info "Step 2/5: Генерирую credentials..."

PG_PASS=$(openssl rand -hex 20)
JWT_SECRET=$(openssl rand -hex 40)
# Логин: имя_sup (из email) или sup_admin
if [ -n "$ADMIN_EMAIL" ]; then
  DASHBOARD_USER="$(echo "$ADMIN_EMAIL" | cut -d@ -f1)_sup"
else
  DASHBOARD_USER="sup_admin"
fi
DASHBOARD_PASS=$(openssl rand -hex 12)
SECRET_KEY_BASE=$(openssl rand -hex 32)
VAULT_ENC_KEY=$(openssl rand -hex 16)
PG_META_CRYPTO_KEY=$(openssl rand -hex 16)
LOGFLARE_PUB_TOKEN=$(openssl rand -hex 24)
LOGFLARE_PRIV_TOKEN=$(openssl rand -hex 24)
POOLER_TENANT_ID=$(openssl rand -hex 8)
S3_ACCESS_KEY_ID=$(openssl rand -hex 16)
S3_ACCESS_KEY_SECRET=$(openssl rand -hex 32)

# JWT токены (используем Python если есть, иначе Node.js)
if command -v python3 &>/dev/null; then
  # Python вариант (не нужен npm)
  ANON_KEY=$(python3 -c "
import hmac, hashlib, base64, json, time
header = base64.urlsafe_b64encode(json.dumps({'alg':'HS256','typ':'JWT'}).encode()).rstrip(b'=').decode()
payload = base64.urlsafe_b64encode(json.dumps({'role':'anon','iss':'supabase','iat':int(time.time()),'exp':int(time.time())+157680000}).encode()).rstrip(b'=').decode()
sig = base64.urlsafe_b64encode(hmac.new('$JWT_SECRET'.encode(), f'{header}.{payload}'.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
print(f'{header}.{payload}.{sig}')
")

  SERVICE_ROLE_KEY=$(python3 -c "
import hmac, hashlib, base64, json, time
header = base64.urlsafe_b64encode(json.dumps({'alg':'HS256','typ':'JWT'}).encode()).rstrip(b'=').decode()
payload = base64.urlsafe_b64encode(json.dumps({'role':'service_role','iss':'supabase','iat':int(time.time()),'exp':int(time.time())+157680000}).encode()).rstrip(b'=').decode()
sig = base64.urlsafe_b64encode(hmac.new('$JWT_SECRET'.encode(), f'{header}.{payload}'.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
print(f'{header}.{payload}.{sig}')
")
else
  err "Нужен python3 для генерации JWT"
  exit 1
fi

log "Credentials сгенерированы"

# ── Step 3: Конфигурация .env ───────────────────────────────

info "Step 3/5: Настраиваю .env..."

cp .env.example .env

# Безопасная замена переменных — проверяем что переменная существует
set_env() {
  local KEY="$1"
  local VALUE="$2"
  if grep -q "^${KEY}=" .env; then
    sed -i "s|${KEY}=.*|${KEY}=${VALUE}|" .env
  else
    err "Переменная ${KEY} не найдена в .env — Supabase мог обновить формат конфига"
    echo "${KEY}=${VALUE}" >> .env
    info "Добавлена вручную: ${KEY}"
  fi
}

set_env "POSTGRES_PASSWORD" "$PG_PASS"
set_env "JWT_SECRET" "$JWT_SECRET"
set_env "ANON_KEY" "$ANON_KEY"
set_env "SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY"
set_env "DASHBOARD_USERNAME" "$DASHBOARD_USER"
set_env "DASHBOARD_PASSWORD" "$DASHBOARD_PASS"
set_env "SECRET_KEY_BASE" "$SECRET_KEY_BASE"
set_env "VAULT_ENC_KEY" "$VAULT_ENC_KEY"
set_env "PG_META_CRYPTO_KEY" "$PG_META_CRYPTO_KEY"
set_env "LOGFLARE_PUBLIC_ACCESS_TOKEN" "$LOGFLARE_PUB_TOKEN"
set_env "LOGFLARE_PRIVATE_ACCESS_TOKEN" "$LOGFLARE_PRIV_TOKEN"
set_env "POOLER_TENANT_ID" "$POOLER_TENANT_ID"
set_env "S3_PROTOCOL_ACCESS_KEY_ID" "$S3_ACCESS_KEY_ID"
set_env "S3_PROTOCOL_ACCESS_KEY_SECRET" "$S3_ACCESS_KEY_SECRET"

# URL конфигурация
set_env "SITE_URL" "https://$FQDN"
set_env "API_EXTERNAL_URL" "https://$FQDN"
set_env "SUPABASE_PUBLIC_URL" "https://$FQDN"
set_env "STUDIO_DEFAULT_ORGANIZATION" "$ORG_NAME"
set_env "STUDIO_DEFAULT_PROJECT" "$PROJECT_NAME"

log ".env настроен"

# ── Step 4: Caddy labels ────────────────────────────────────

info "Step 4/5: Добавляю Caddy labels в docker-compose..."

# Supabase использует Kong как API gateway на порту 8000
# Добавляем labels к Kong сервису и подключаем к сети infra
# Это делается через docker-compose.override.yml чтобы не менять оригинальный файл

cat > docker-compose.override.yml << EOF
services:
  kong:
    networks:
      - default
      - infra
    labels:
      caddy: "$FQDN"
      caddy.reverse_proxy: "{{upstreams 8000}}"

networks:
  infra:
    external: true
EOF

log "Caddy labels добавлены"

# ── Step 5: Запуск ──────────────────────────────────────────

info "Step 5/5: Запускаю Supabase (это может занять 5-10 минут)..."

docker compose pull -q 2>/dev/null || true
docker compose up -d

# Ждём запуска (до 5 минут)
info "Ожидаю запуска всех сервисов..."
for i in $(seq 1 300); do
  RUNNING=$(docker ps --format '{{.Names}}' | grep -c "supabase" || true)
  if [ "$RUNNING" -ge 5 ]; then
    # Проверяем Studio
    if curl -sk "http://localhost:8000" &>/dev/null; then
      log "Supabase запущен ($RUNNING контейнеров)"
      break
    fi
  fi
  if [ $((i % 30)) -eq 0 ]; then
    info "Ещё ждём... ($i сек, $RUNNING контейнеров)"
  fi
  sleep 1
done

# Подсчёт контейнеров
CONTAINERS_COUNT=$(docker ps --format '{{.Names}}' | grep -c "supabase" || echo "0")

# ── Step 6: systemd reboot fix (F-034) ──────────────────────
# После ребута supabase-pooler падает из-за orphan docker-proxy на :5432
# (userland proxy держит IP старого контейнера). Фикс: делаем `compose down && up -d`
# один раз после старта docker — все 13 контейнеров поднимаются чисто.

info "Step 6/6: systemd unit supabase-restart.service (фикс pooler после ребута)..."
cat > /etc/systemd/system/supabase-restart.service << 'SYSEOF'
[Unit]
Description=Restart Supabase stack after boot (down + up -d, fixes F-034 orphan docker-proxy on :5432)
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/root/supabase/docker
ExecStart=/usr/bin/docker compose down
ExecStart=/usr/bin/docker compose up -d
RemainAfterExit=yes
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
SYSEOF
systemctl daemon-reload
systemctl enable supabase-restart.service >/dev/null 2>&1
log "systemd unit supabase-restart.service создан и enabled"

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"
log "Supabase готов: https://$FQDN ($CONTAINERS_COUNT контейнеров)"
cat "$REPORT_FILE"

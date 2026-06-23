#!/bin/bash
# ============================================================
#  Базовая подготовка сервера: Docker, UFW, пользователь
#  Адаптировано из old/scripts/install-docker-system.sh
# ============================================================

set -euo pipefail

LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/setup-server-report.json"
mkdir -p "$LOG_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "docker_version": "${DOCKER_VER:-unknown}",
  "compose_version": "${COMPOSE_VER:-unknown}",
  "dockeruser_password": "${DOCKERUSER_PASS:-}",
  "ufw_status": "${UFW_STATUS:-unknown}",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Step 1: Обновление пакетов ──────────────────────────────

info "Step 1/5: Обновление пакетов..."
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

apt-get update -qq
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y -qq curl wget ca-certificates gnupg lsb-release software-properties-common mc
log "Step 1/5: Пакеты обновлены"

# ── Step 2: Docker ──────────────────────────────────────────

info "Step 2/5: Установка Docker..."

if command -v docker &>/dev/null; then
  log "Docker уже установлен: $(docker --version)"
else
  # GPG ключ
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Репозиторий
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
  log "Docker установлен"
fi

DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
COMPOSE_VER=$(docker compose version 2>/dev/null | awk '{print $4}')
log "Step 2/5: Docker $DOCKER_VER, Compose $COMPOSE_VER"

# ── Step 3: Пользователь dockeruser ─────────────────────────

info "Step 3/5: Пользователь dockeruser..."

DOCKERUSER_PASS=""
if id "dockeruser" &>/dev/null; then
  log "dockeruser уже существует"
else
  DOCKERUSER_PASS=$(openssl rand -hex 16)
  useradd -m -s /bin/bash dockeruser
  echo "dockeruser:$DOCKERUSER_PASS" | chpasswd
  usermod -aG docker dockeruser
  log "dockeruser создан"
fi

# ── Step 4: UFW Firewall ────────────────────────────────────

info "Step 4/5: Настройка UFW..."

if ! command -v ufw &>/dev/null; then
  apt-get install -y -qq ufw
fi

# Разрешаем SSH до включения UFW чтобы не потерять доступ
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 22/tcp >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

UFW_STATUS=$(ufw status | head -1)
log "Step 4/5: UFW включен ($UFW_STATUS)"

# ── Step 5: SSH hardening ───────────────────────────────────

info "Step 5/5: SSH hardening..."

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CHANGED=false

# НЕ отключаем вход по паролю автоматически — пользователь может не иметь ключа
# Это делается вручную после добавления SSH ключа
# if grep -q "^PermitRootLogin yes" "$SSHD_CONFIG" 2>/dev/null; then
#   sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
#   SSHD_CHANGED=true
# fi

# Отключаем пустые пароли
if grep -q "^PermitEmptyPasswords yes" "$SSHD_CONFIG" 2>/dev/null; then
  sed -i 's/^PermitEmptyPasswords yes/PermitEmptyPasswords no/' "$SSHD_CONFIG"
  SSHD_CHANGED=true
fi

if [ "$SSHD_CHANGED" = true ]; then
  systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
  log "SSH config обновлён"
else
  log "SSH config уже настроен"
fi

log "Step 5/5: SSH hardening done"

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"
log "Базовая подготовка завершена. Отчёт: $REPORT_FILE"
cat "$REPORT_FILE"

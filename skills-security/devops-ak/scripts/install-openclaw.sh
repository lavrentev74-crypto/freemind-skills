#!/bin/bash
# ============================================================
#  OpenClaw — native install (Homebrew, systemd user)
#  Запускается от root. Создаёт юзера `openclaw`, ставит brew + openclaw CLI,
#  поднимает Gateway как systemd user-unit с lingering.
#  Доступ — loopback only (127.0.0.1:18789). Публичный домен НЕ нужен.
#  Юзер ходит через SSH-туннель + Telegram-бота.
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────
DOMAIN="${1:?Usage: $0 DOMAIN [TG_BOT_TOKEN]}"
TG_BOT_TOKEN="${2:-}"
OC_USER="openclaw"
OC_HOME="/home/$OC_USER"
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/openclaw-report.json"
GATEWAY_PORT=18789

mkdir -p "$LOG_DIR"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "gateway_local": "http://127.0.0.1:$GATEWAY_PORT",
  "user": "$OC_USER",
  "password": "${OC_PASS:-}",
  "tg_bot_username": "${TG_BOT_USERNAME:-}",
  "service": "systemd user-unit (openclaw gateway), lingering enabled",
  "update": "sudo -iu openclaw bash -lc 'openclaw update && openclaw gateway restart'",
  "logs": "sudo -iu openclaw journalctl --user -u openclaw-gateway -f",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

trap 'err "Ошибка на строке $LINENO"; write_report "error" "script failed at line $LINENO"; cat "$REPORT_FILE"; exit 1' ERR

# ── Step 1: юзер openclaw ───────────────────────────────────
info "Step 1/8: Создаю юзера $OC_USER (если нет)..."
if ! id "$OC_USER" &>/dev/null; then
  OC_PASS=$(openssl rand -hex 10)
  useradd -m -s /bin/bash "$OC_USER"
  echo "$OC_USER:$OC_PASS" | chpasswd
  usermod -aG sudo "$OC_USER"
  # sudo без пароля (удобно для systemd user setup; можно ужесточить позже)
  echo "$OC_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$OC_USER"
  chmod 440 "/etc/sudoers.d/$OC_USER"
  log "Юзер создан, пароль: $OC_PASS (СОХРАНИ!)"
else
  # Если юзер есть — читаем пароль из предыдущего report, иначе генерим новый
  if [ -f "$REPORT_FILE" ]; then
    OC_PASS=$(python3 -c "import json;print(json.load(open('$REPORT_FILE')).get('password',''))" 2>/dev/null || echo "")
  fi
  if [ -z "${OC_PASS:-}" ]; then
    OC_PASS=$(openssl rand -hex 10)
    echo "$OC_USER:$OC_PASS" | chpasswd
    log "Пароль обновлён: $OC_PASS"
  else
    log "Юзер уже существует, пароль из отчёта"
  fi
fi
loginctl enable-linger "$OC_USER"

# ── Step 2: зависимости системы (apt) ───────────────────────
info "Step 2/8: apt зависимости (git, curl, build tools)..."
apt-get update -qq
apt-get install -y -qq git curl build-essential procps file jq python3 python3-pip

# ── Step 3: Homebrew под юзером openclaw ────────────────────
# ВАЖНО: env кладём в .profile (login shell его источит), не в .bashrc
# (interactive non-login). `sudo -iu` = login shell → читает .profile.
info "Step 3/8: Homebrew (под $OC_USER)..."

# Сначала пропишем env в .profile и .bashrc ЗАРАНЕЕ — иначе subsequent команды
# не найдут brew/npm-global.
PROFILE_BLOCK='
# ── OpenClaw env (install-openclaw.sh) ──
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
export NODE_OPTIONS=--dns-result-order=ipv4first
export PATH="$HOME/.npm-global/bin:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
'
for rc in "$OC_HOME/.profile" "$OC_HOME/.bashrc"; do
  touch "$rc"
  grep -q "OpenClaw env" "$rc" || printf '%s\n' "$PROFILE_BLOCK" >> "$rc"
  chown "$OC_USER:$OC_USER" "$rc"
done

if ! sudo -iu "$OC_USER" bash -lc 'command -v brew' &>/dev/null; then
  sudo -iu "$OC_USER" bash -lc \
    'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  log "Homebrew установлен"
else
  log "Homebrew уже есть"
fi

# Обёртка: каждая команда стартует с brew shellenv чтобы PATH гарантированно был
OC_RUN() { sudo -iu "$OC_USER" bash -lc "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)\"; export PATH=\"\$HOME/.npm-global/bin:\$PATH\"; $*"; }

# ── Step 4: Node.js через brew ──────────────────────────────
info "Step 4/8: Node.js (через brew)..."
OC_RUN 'command -v node || brew install node' >/dev/null
NODE_VER=$(OC_RUN 'node -v')
log "Node.js $NODE_VER"

# ── Step 5: OpenClaw CLI ────────────────────────────────────
# Используем прямой `npm install -g openclaw` вместо `curl ... install.sh | bash`
# — upstream install.sh требует /dev/tty (не работает в non-interactive sessions).
info "Step 5/8: Устанавливаю OpenClaw CLI (npm -g)..."
if ! OC_RUN 'command -v openclaw' &>/dev/null; then
  OC_RUN 'npm install -g openclaw' 2>&1 | tail -5
fi
OC_VER=$(OC_RUN 'openclaw --version' 2>/dev/null | head -1)
log "OpenClaw $OC_VER"

# ── Step 6: Telegram токен (если задан) ─────────────────────
TG_CONFIGURED=false
if [ -n "$TG_BOT_TOKEN" ]; then
  info "Step 6/8: Прописываю Telegram бот токен..."
  # Создаём/обновляем openclaw.json под юзером
  OC_RUN "mkdir -p ~/.openclaw"
  TG_PY_SCRIPT=$(mktemp)
  cat > "$TG_PY_SCRIPT" << PYEOF
import json, os
path = os.path.expanduser('~/.openclaw/openclaw.json')
d = {}
if os.path.exists(path):
    try:
        d = json.load(open(path))
    except Exception:
        d = {}
d.setdefault('channels', {}).setdefault('telegram', {})['botToken'] = '$TG_BOT_TOKEN'
json.dump(d, open(path, 'w'), indent=2)
print('telegram token saved')
PYEOF
  sudo cp "$TG_PY_SCRIPT" "$OC_HOME/.tg-token.py"
  sudo chown "$OC_USER":"$OC_USER" "$OC_HOME/.tg-token.py"
  OC_RUN "python3 ~/.tg-token.py && rm -f ~/.tg-token.py"
  rm -f "$TG_PY_SCRIPT"
  TG_CONFIGURED=true
  TG_BOT_USERNAME=$(curl -s --max-time 5 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['username'])" 2>/dev/null || echo "")
  log "TG токен сохранён (bot: @${TG_BOT_USERNAME:-unknown})"
else
  info "Step 6/8: TG token не передан — можно добавить позже через onboard UI"
fi

# ── Step 7: Gateway (systemd user-unit) ─────────────────────
info "Step 7/8: Настраиваю Gateway (systemd user-unit)..."
OC_RUN "openclaw doctor --fix 2>&1 | tail -10 || true" || true
OC_RUN "openclaw gateway install 2>&1 | tail -5 || true" || true
OC_RUN "openclaw config set gateway.mode local" || true
OC_RUN "openclaw config set gateway.bind loopback" || true
OC_RUN "openclaw config set gateway.port $GATEWAY_PORT" || true
OC_RUN "openclaw gateway restart 2>&1 | tail -5 || true" || true

# Проверка что gateway отвечает
for i in $(seq 1 30); do
  if curl -sf --max-time 2 "http://127.0.0.1:$GATEWAY_PORT/healthz" >/dev/null 2>&1 \
     || curl -sf --max-time 2 "http://127.0.0.1:$GATEWAY_PORT/" >/dev/null 2>&1; then
    log "Gateway отвечает на :$GATEWAY_PORT ($i сек)"
    break
  fi
  sleep 1
done

# ── Step 8: Caddy НЕ НУЖЕН ───────────────────────────────────
# OpenClaw Gateway работает loopback-only (127.0.0.1:18789).
# Доступ — через SSH-туннель с машины юзера:
#   ssh -N -L 18789:127.0.0.1:18789 openclaw@<SERVER_IP>
# Затем в браузере http://localhost:18789
# Публичный домен НЕ нужен — gateway содержит токены доступа к LLM,
# выставлять его наружу через Caddy было бы небезопасно.
info "Step 8/8: Caddy для OpenClaw не нужен (loopback-only + SSH tunnel)"
log "OpenClaw готов"

# ── Отчёт ───────────────────────────────────────────────────
write_report "completed"

echo ""
echo "================================================================"
echo "  OpenClaw установлен (native)"
echo "================================================================"
echo "  Gateway local:      http://127.0.0.1:$GATEWAY_PORT (loopback only)"
echo "  Доступ:             SSH tunnel + Telegram bot (публичного домена НЕТ)"
echo "  Юзер:               $OC_USER"
echo "  Пароль:             $OC_PASS"
echo ""
echo "  СЛЕДУЮЩИЕ ШАГИ (от чувака, в Termius):"
echo ""
echo "  1. Подключись к серверу: ssh root@<IP>"
echo "  2. Зайди под юзером openclaw:  sudo -iu openclaw"
echo "  3. Настрой провайдеров интерактивно:"
echo "       openclaw onboard --flow quickstart"
echo "     или через UI: SSH-туннель → http://localhost:$GATEWAY_PORT"
if [ "$TG_CONFIGURED" = "true" ]; then
echo ""
echo "  4. Telegram pairing (TG токен уже задан):"
echo "     Напиши боту @${TG_BOT_USERNAME:-твой_бот} команду /start → получишь код"
echo "     Выполни на сервере: sudo -iu openclaw openclaw pairing approve telegram <КОД>"
fi
echo ""
echo "  Управление:"
echo "    sudo -iu openclaw openclaw status"
echo "    sudo -iu openclaw openclaw gateway restart"
echo "    sudo -iu openclaw journalctl --user -u openclaw-gateway -f"
echo "================================================================"
cat "$REPORT_FILE"

#!/bin/bash
# ============================================================
#  Paperclip AI — native install
#  Клонируется в /home/openclaw/paperclip, билдится pnpm, systemd service.
#  Работает под юзером openclaw (тот же что для OpenClaw — см. install-openclaw.sh).
#  Caddy интегрируется через /root/caddy/extra.caddyfile.
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────
DOMAIN="${1:?Usage: $0 DOMAIN [SUBDOMAIN]}"
SUBDOMAIN="${2:-pc}"
FQDN="${SUBDOMAIN}.${DOMAIN}"
OC_USER="openclaw"
OC_HOME="/home/$OC_USER"
PC_DIR="$OC_HOME/paperclip"
PC_HOME="$OC_HOME/.paperclip"
PC_CONFIG="$PC_HOME/instances/default/config.json"
PC_PORT=3100
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/paperclip-report.json"

mkdir -p "$LOG_DIR"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "url": "https://$FQDN",
  "port_local": $PC_PORT,
  "install_dir": "$PC_DIR",
  "config": "$PC_CONFIG",
  "user": "$OC_USER",
  "invite_url": "${INVITE_URL:-}",
  "service": "systemd system-unit (paperclip)",
  "update": "cd $PC_DIR && sudo -iu $OC_USER bash -lc 'cd $PC_DIR && git pull && pnpm install && pnpm build' && sudo systemctl restart paperclip",
  "logs": "journalctl -u paperclip -f",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

trap 'err "Ошибка на строке $LINENO"; write_report "error" "script failed at line $LINENO"; cat "$REPORT_FILE"; exit 1' ERR

# ── Step 1: проверка юзера openclaw ─────────────────────────
info "Step 1/9: Проверяю юзера $OC_USER..."
if ! id "$OC_USER" &>/dev/null; then
  err "Юзер $OC_USER не найден. Сначала запусти install-openclaw.sh — он создаёт юзера и ставит Node.js через brew."
  exit 1
fi
log "Юзер $OC_USER существует"

# Обёртка как в install-openclaw.sh — brew shellenv + PATH npm-global
OC_RUN() { sudo -iu "$OC_USER" bash -lc "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)\"; export PATH=\"\$HOME/.npm-global/bin:\$PATH\"; $*"; }

# ── Step 2: проверка Node.js у юзера ────────────────────────
info "Step 2/9: Node.js..."
NODE_VER=$(OC_RUN 'node -v' 2>/dev/null || echo "none")
if [[ "$NODE_VER" == "none" ]]; then
  err "Node.js не установлен у $OC_USER. Запусти install-openclaw.sh сначала."
  exit 1
fi
NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
[[ "$NODE_MAJOR" -lt 22 ]] && err "Нужен Node.js v22+. Сейчас: $NODE_VER"
log "Node.js $NODE_VER"

# ── Step 3: pnpm + claude CLI ───────────────────────────────
info "Step 3/9: pnpm + claude CLI..."
OC_RUN 'command -v pnpm >/dev/null || npm install -g pnpm' >/dev/null 2>&1 || true
OC_RUN 'command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash' >/dev/null 2>&1 || true
# Симлинк claude в /usr/local/bin для systemd
CLAUDE_BIN=$(OC_RUN 'command -v claude 2>/dev/null || ls $HOME/.local/bin/claude 2>/dev/null | head -1')
if [ -n "$CLAUDE_BIN" ] && [ "$CLAUDE_BIN" != "/usr/local/bin/claude" ]; then
  ln -sf "$CLAUDE_BIN" /usr/local/bin/claude
  log "claude → /usr/local/bin/claude"
fi
PNPM_VER=$(OC_RUN 'pnpm -v' 2>/dev/null || echo "?")
CLAUDE_VER=$(OC_RUN 'claude --version' 2>/dev/null | head -1 || echo "?")
log "pnpm $PNPM_VER, claude $CLAUDE_VER"

# ── Step 4: Останавливаем старый сервис (если был) ──────────
info "Step 4/9: Чистим старые процессы..."
systemctl stop paperclip 2>/dev/null || true
pkill -9 -f "paperclipai" 2>/dev/null || true
for port in "$PC_PORT" 54329; do
  PIDS=$(ss -tlnp 2>/dev/null | grep ":$port " | grep -oP 'pid=\K[0-9]+' || true)
  [ -n "$PIDS" ] && echo "$PIDS" | xargs -r kill -9 2>/dev/null || true
done
sleep 1

# ── Step 5: Клон/обновление репо ────────────────────────────
info "Step 5/9: Клон/апдейт репо в $PC_DIR..."
if OC_RUN "test -d '$PC_DIR/.git'" 2>/dev/null; then
  OC_RUN "cd '$PC_DIR' && git fetch origin && git pull" 2>&1 | tail -5
else
  OC_RUN "git clone https://github.com/paperclipai/paperclip.git '$PC_DIR'" 2>&1 | tail -5
fi
COMMIT=$(OC_RUN "cd '$PC_DIR' && git rev-parse --short HEAD")
log "Репо: commit $COMMIT"

# ── Step 6: pnpm install + build ────────────────────────────
info "Step 6/9: pnpm install (1-3 мин)..."
OC_RUN "cd '$PC_DIR' && pnpm install" > /tmp/pc-pnpm-install.log 2>&1
log "pnpm install OK"

info "Step 6/9: pnpm build (2-5 мин)..."
OC_RUN "cd '$PC_DIR' && pnpm build" > /tmp/pc-pnpm-build.log 2>&1
log "pnpm build OK"

# ── Step 7: onboard + конфиг домена ─────────────────────────
info "Step 7/9: Первичный onboard Paperclip..."
# `paperclipai onboard --yes` сохраняет config, генерит bootstrap-CEO invite,
# НО потом запускает сервер и не выходит. Нам нужен только config+invite —
# сервером управляет systemd. Оборачиваем в timeout 40s, затем убиваем
# дочерние процессы paperclipai.
OC_RUN "cd '$PC_DIR' && timeout 40 pnpm paperclipai onboard --yes --bind lan" 2>&1 | tail -15 || true
pkill -9 -f "paperclipai onboard" 2>/dev/null || true
pkill -9 -f "cli/src/index.ts onboard" 2>/dev/null || true
pkill -9 -f "postgres.*paperclip" 2>/dev/null || true
sleep 2
log "onboard завершён (сервер будет запущен через systemd)"

info "Прописываю домен и публичный URL..."
sudo -iu "$OC_USER" python3 - << PYEOF
import json, pathlib
p = pathlib.Path("$PC_CONFIG")
d = json.loads(p.read_text()) if p.exists() else {}
d.setdefault('server', {})
d['server']['host'] = '0.0.0.0'
d['server']['port'] = $PC_PORT
hosts = d['server'].setdefault('allowedHostnames', [])
if "$FQDN" not in hosts:
    hosts.append("$FQDN")
auth = d.setdefault('auth', {})
auth['publicBaseUrl'] = "https://$FQDN"
# F-037: baseUrlMode=auto отдаёт localhost из CLI (bootstrap-ceo),
# т.к. у CLI нет HTTP request для авто-детекта хоста. Форсим public.
auth['baseUrlMode'] = "explicit"
p.write_text(json.dumps(d, indent=2))
print("Config updated:", p)
PYEOF
log "Конфиг домена применён"

# ── Step 8: systemd unit ────────────────────────────────────
info "Step 8/9: systemd сервис paperclip..."
PNPM_BIN=$(OC_RUN 'command -v pnpm')
tee /etc/systemd/system/paperclip.service > /dev/null <<EOF
[Unit]
Description=Paperclip AI Server
After=network.target

[Service]
Type=simple
User=$OC_USER
Group=$OC_USER
WorkingDirectory=$PC_DIR
ExecStart=$PNPM_BIN paperclipai run
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production
Environment=PAPERCLIP_UI_DEV_MIDDLEWARE=false
Environment=HOME=$OC_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$OC_HOME/.local/bin:/home/linuxbrew/.linuxbrew/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paperclip
systemctl restart paperclip

# Ждём запуска
info "Ждём запуска Paperclip (до 60 сек)..."
for i in $(seq 1 60); do
  if ss -tln 2>/dev/null | grep -q ":$PC_PORT "; then
    log "Paperclip слушает :$PC_PORT ($i сек)"
    break
  fi
  sleep 1
done
systemctl is-active --quiet paperclip || { journalctl -u paperclip -n 40 --no-pager; err "Paperclip не стартовал"; exit 1; }

# ── UFW: разрешить caddy (docker bridge) достучаться до host:3100 ──
info "Step 9a/9: UFW rule для Caddy → host:$PC_PORT..."
BRIDGE_NET=$(docker network inspect infra --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "172.18.0.0/16")
ufw allow from "$BRIDGE_NET" to any port "$PC_PORT" proto tcp comment 'paperclip from docker bridge' 2>/dev/null || true
ufw reload 2>/dev/null || true

# ── Step 9: Caddy reverse-proxy ─────────────────────────────
info "Step 9/9: Caddy reverse-proxy для $FQDN..."
EXTRA_CADDY="/root/caddy/extra.caddyfile"
BRIDGE_GW=$(docker network inspect infra --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "172.18.0.1")
touch "$EXTRA_CADDY"
python3 << PYEOF
import re, pathlib
p = pathlib.Path("$EXTRA_CADDY")
content = p.read_text() if p.exists() else ""
content = re.sub(r'(?ms)^$FQDN\s*\{[^}]*\}\n?', '', content)
block = f"""$FQDN {{
    reverse_proxy $BRIDGE_GW:$PC_PORT
}}
"""
p.write_text(content.rstrip() + ("\n\n" if content.strip() else "") + block)
PYEOF
log "Caddyfile обновлён"
docker restart caddy >/dev/null 2>&1 && log "Caddy перезапущен"

# ── Step 10: CEO bootstrap invite (F-036) ───────────────────
# Генерим invite автоматически, чтобы отдать юзеру готовую ссылку.
info "Step 10/10: bootstrap CEO invite..."
BOOTSTRAP_OUT=$(sudo -iu "$OC_USER" bash -lc "cd '$PC_DIR' && pnpm paperclipai auth bootstrap-ceo --force" 2>&1 || true)
INVITE_URL=$(echo "$BOOTSTRAP_OUT" | grep -oE 'https?://[^ ]+/invite/[^ ]+' | tail -1 || echo "")
# F-037 fallback: если URL всё-таки localhost — подменяем хост на FQDN.
if [[ "$INVITE_URL" == *"localhost"* || "$INVITE_URL" == *"127.0.0.1"* ]]; then
  INVITE_URL=$(echo "$INVITE_URL" | sed -E "s#https?://[^/]+#https://$FQDN#")
fi
if [ -n "$INVITE_URL" ]; then
  log "CEO invite: $INVITE_URL"
else
  err "Не удалось извлечь invite URL из bootstrap-ceo. Вывод:"
  echo "$BOOTSTRAP_OUT" | tail -20
fi

write_report "completed"

echo ""
echo "================================================================"
echo "  Paperclip установлен (native)"
echo "================================================================"
echo "  URL:                https://$FQDN"
echo "  Local port:         $PC_PORT"
echo "  Install dir:        $PC_DIR"
echo "  Под юзером:         $OC_USER"
echo ""
if [ -n "$INVITE_URL" ]; then
echo "  CEO Invite (3 дня): $INVITE_URL"
echo ""
fi
echo "  СЛЕДУЮЩИЕ ШАГИ (юзеру):"
echo "  1. Открой CEO invite в браузере, зарегистрируй себя (email + пароль)."
echo "  2. ssh $OC_USER@<IP>   # напрямую под openclaw"
echo "  3. claude              # запустится wizard (нужен для AI-агентов)"
echo "     → В меню выбери 'Claude account with subscription'"
echo "     → Открой URL в браузере → скопируй code → вставь в терминал → Enter"
echo "  4. exit; sudo systemctl restart paperclip"
echo "  5. Открой $INVITE_URL — регистрируй CEO аккаунт"
echo "  6. Закрой регистрацию (ВАЖНО):"
echo "       sudo -iu $OC_USER python3 -c \"import json;p='$PC_CONFIG';d=json.load(open(p));d['auth']['disableSignUp']=True;json.dump(d,open(p,'w'),indent=2)\""
echo "       sudo systemctl restart paperclip"
echo ""
echo "  Логи:     journalctl -u paperclip -f"
echo "  Рестарт:  sudo systemctl restart paperclip"
echo "================================================================"
cat "$REPORT_FILE"

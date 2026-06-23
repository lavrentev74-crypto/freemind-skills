#!/bin/bash
# ============================================================
#  Claude Code CLI — standalone install + subscription auth
#
#  Default mode = AGENT (агент рулит OAuth: получает URL, передаёт юзеру,
#  принимает код, отправляет на сервер). Скрипт сам не блокируется ожиданием
#  ввода с TTY — он запускает OAuth в фоне и печатает маркеры в stdout.
#
#  Использование (из агента, через ssh без -t):
#    ssh root@IP '/root/install-claude-code.sh <user>'
#      → ставит CC, печатает CC_AUTH_URL=... / CC_AUTH_FIFO=... / CC_AUTH_LOG=...
#      → выходит. Авторизация ждёт код в FIFO.
#    ssh root@IP '/root/install-claude-code.sh <user> --send-code <CODE>'
#      → пишет код в FIFO, ждёт результат, проверяет claude auth status,
#        пишет отчёт в /root/logs/claude-code-<user>-report.json
#
#  Использование (человек в живом терминале):
#    ssh -t root@IP '/root/install-claude-code.sh <user> --tty'
#      → запросит код через expect_user, всё в одном вызове.
#
#  Авторизация — ТОЛЬКО OAuth по подписке Pro/Max (claude.ai). API-key нет.
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────
CC_USER="${1:?Usage: $0 <user> [--send-code <CODE> | --tty | --check]}"
shift || true
MODE="agent"
SEND_CODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --send-code) SEND_CODE="${2:?--send-code needs CODE}"; MODE="send-code"; shift 2 ;;
    --tty)       MODE="tty"; shift ;;
    --check)     MODE="check"; shift ;;
    *) echo "[ERR] unknown arg: $1" >&2; exit 1 ;;
  esac
done

LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/claude-code-${CC_USER}-report.json"
EXPECT_FILE="/root/cc_auth_${CC_USER}.expect"
AUTH_LOG="/tmp/cc_auth_${CC_USER}.log"
AUTH_FIFO="/tmp/cc_in_${CC_USER}"
NODE_MIN_MAJOR=22

mkdir -p "$LOG_DIR"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

USER_RUN() {
  if [ "$CC_USER" = "root" ]; then
    bash -lc "export PATH=\"\$HOME/.local/bin:\$PATH\"; $*"
  else
    sudo -iu "$CC_USER" bash -lc "export PATH=\"\$HOME/.local/bin:\$PATH\"; $*"
  fi
}

USER_HOME() { eval echo "~$CC_USER"; }

# Pre-set first-run wizard flags so `claude` (interactive) не тыкает онбординг.
# Без этого headless-сценарии (cron, Paperclip, systemd) виснут на theme-picker.
mark_onboarding_done() {
  local home; home=$(USER_HOME)
  local ver; ver=$(USER_RUN 'claude --version' 2>/dev/null | awk '{print $1}' | head -1)
  [ -z "$ver" ] && ver="2.1.143"
  USER_RUN "python3 - <<PY
import json, os
cfg = os.path.expanduser('~/.claude.json')
try:
    d = json.load(open(cfg)) if os.path.exists(cfg) else {}
except Exception:
    d = {}
d['hasCompletedOnboarding'] = True
d['lastOnboardingVersion'] = '$ver'
d.setdefault('numStartups', 1)
# Pre-trust HOME папку, чтобы 'Is this a project you trust?' не появлялось.
# Для других папок trust будет спрашивать один раз — это нормально (safety).
home = os.path.expanduser('~')
projects = d.setdefault('projects', {})
proj = projects.setdefault(home, {})
proj['hasTrustDialogAccepted'] = True
proj['hasClaudeMdExternalIncludesApproved'] = True
proj['hasClaudeMdExternalIncludesWarningShown'] = True
proj.setdefault('allowedTools', [])
proj.setdefault('mcpContextUris', [])
proj.setdefault('mcpServers', {})
proj.setdefault('enabledMcpjsonServers', [])
proj.setdefault('disabledMcpjsonServers', [])
proj.setdefault('projectOnboardingSeenCount', 1)
proj.setdefault('exampleFiles', [])
proj.setdefault('lastVersionBase', '$ver')
json.dump(d, open(cfg,'w'), indent=2)
os.chmod(cfg, 0o600)

stg_dir = os.path.expanduser('~/.claude')
os.makedirs(stg_dir, exist_ok=True)
stg = os.path.join(stg_dir, 'settings.json')
try:
    s = json.load(open(stg)) if os.path.exists(stg) else {}
except Exception:
    s = {}
s.setdefault('theme', 'dark')
json.dump(s, open(stg,'w'), indent=2)
PY
" 2>/dev/null || info "не удалось пред-заполнить онбординг-флаги (python3?)"
  log "онбординг-флаги выставлены (hasCompletedOnboarding=true)"
}

write_report() {
  local status="$1"; local error="${2:-}"
  local cc_ver; cc_ver=$(USER_RUN 'claude --version 2>/dev/null' 2>/dev/null | head -1 || echo "?")
  local node_ver; node_ver=$(node -v 2>/dev/null || echo "?")
  local logged_in="false"; local auth_method="none"; local email=""; local sub_type=""
  local status_json; status_json=$(USER_RUN 'claude auth status --json 2>/dev/null' 2>/dev/null || echo "{}")
  if [[ -n "$status_json" && "$status_json" != "{}" ]]; then
    logged_in=$(echo "$status_json"   | awk '/"loggedIn"/        {gsub(/[",]/,"",$2); print $2; exit}')
    auth_method=$(echo "$status_json" | awk -F'"' '/"authMethod"/      {print $4; exit}')
    email=$(echo "$status_json"       | awk -F'"' '/"email"/           {print $4; exit}')
    sub_type=$(echo "$status_json"    | awk -F'"' '/"subscriptionType"/{print $4; exit}')
  fi
  cat > "$REPORT_FILE" << EOF
{
  "status": "$status",
  "user": "$CC_USER",
  "node_version": "$node_ver",
  "claude_version": "$cc_ver",
  "logged_in": ${logged_in:-false},
  "auth_method": "$auth_method",
  "email": "$email",
  "subscription_type": "$sub_type",
  "auth_config": "$(USER_HOME)/.claude.json",
  "symlink": "/usr/local/bin/claude",
  "fifo": "$AUTH_FIFO",
  "auth_log": "$AUTH_LOG",
  "error": "$error",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

cleanup_oauth_session() {
  pkill -9 -f "$EXPECT_FILE" 2>/dev/null || true
  rm -f "$EXPECT_FILE" "$AUTH_FIFO" "$AUTH_LOG" 2>/dev/null || true
}

trap 'err "Ошибка на строке $LINENO"; write_report "error" "script failed at line $LINENO"; cat "$REPORT_FILE" 2>/dev/null; exit 1' ERR

# ============================================================
#  --send-code: вторая фаза агент-режима — отправка кода
# ============================================================
if [ "$MODE" = "send-code" ]; then
  info "phase 2/2: отправляю OAuth-код в $AUTH_FIFO..."
  [ -p "$AUTH_FIFO" ] || { err "FIFO $AUTH_FIFO не найден. Сначала запусти скрипт без --send-code."; write_report "error" "no FIFO"; exit 1; }
  pgrep -af "$EXPECT_FILE" >/dev/null || { err "Фоновый expect-процесс не жив. Перезапусти OAuth с нуля."; write_report "error" "no expect proc"; cleanup_oauth_session; exit 1; }
  echo "$SEND_CODE" > "$AUTH_FIFO" &
  ECHO_PID=$!
  # Ждём результат в логе или завершения процесса
  for i in $(seq 1 30); do
    sleep 1
    if grep -qE "(Login successful|Logged in|Successfully|AUTH_FAILED|AUTH_SUCCESS|Error|Invalid)" "$AUTH_LOG" 2>/dev/null; then
      break
    fi
    pgrep -af "$EXPECT_FILE" >/dev/null || break
  done
  wait $ECHO_PID 2>/dev/null || true
  sleep 1
  # Проверяем
  status_json=$(USER_RUN 'claude auth status --json' 2>/dev/null || echo "{}")
  LOGGED=$(echo "$status_json" | awk '/"loggedIn"/{gsub(/[",]/,"",$2); print $2; exit}')
  if [ "$LOGGED" = "true" ]; then
    METHOD=$(echo "$status_json" | awk -F'"' '/"authMethod"/      {print $4; exit}')
    EMAIL=$(echo  "$status_json" | awk -F'"' '/"email"/           {print $4; exit}')
    SUB=$(echo    "$status_json" | awk -F'"' '/"subscriptionType"/{print $4; exit}')
    log "✅ авторизация подтверждена"
    log "   authMethod=$METHOD   email=$EMAIL   subscription=$SUB"
    mark_onboarding_done
    write_report "authed"
    cleanup_oauth_session
    echo ""
    log "Отчёт: $REPORT_FILE"
    exit 0
  else
    err "claude auth status говорит loggedIn=false"
    err "Лог OAuth: $AUTH_LOG"
    tail -20 "$AUTH_LOG" 2>/dev/null | sed 's/^/    /'
    write_report "auth_failed" "code rejected or expired"
    cleanup_oauth_session
    exit 1
  fi
fi

# ============================================================
#  --check: только проверить статус и записать отчёт
# ============================================================
if [ "$MODE" = "check" ]; then
  info "проверка статуса..."
  status_json=$(USER_RUN 'claude auth status --json' 2>/dev/null || echo "{}")
  LOGGED=$(echo "$status_json" | awk '/"loggedIn"/{gsub(/[",]/,"",$2); print $2; exit}')
  if [ "$LOGGED" = "true" ]; then
    mark_onboarding_done
    write_report "authed"
    log "✅ авторизован"
    cat "$REPORT_FILE"
  else
    write_report "not_authed"
    err "не авторизован"
    exit 1
  fi
  exit 0
fi

# ============================================================
#  Phase 1: preflight + install + start OAuth (либо agent либо tty)
# ============================================================

# ── Step 1: проверки окружения ──────────────────────────────
info "Step 1/6: проверки..."
[ "$(id -u)" -eq 0 ] || { err "Запусти от root"; exit 1; }
id "$CC_USER" &>/dev/null || { err "Юзер $CC_USER не найден. Создай: useradd -m -s /bin/bash $CC_USER"; exit 1; }
log "юзер $CC_USER существует"

# ── Step 2: Node.js >= 22 ───────────────────────────────────
info "Step 2/6: Node.js (>= ${NODE_MIN_MAJOR})..."
NODE_OK=0
if command -v node >/dev/null 2>&1; then
  NV=$(node -v | sed 's/v//' | cut -d. -f1)
  [ "$NV" -ge "$NODE_MIN_MAJOR" ] && NODE_OK=1 && log "Node $(node -v) — ок"
fi
if [ "$NODE_OK" -eq 0 ]; then
  info "ставлю Node ${NODE_MIN_MAJOR}.x через NodeSource..."
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 || true
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MIN_MAJOR}.x" | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null 2>&1
  log "Node $(node -v) установлен"
fi

# ── Step 3: expect ──────────────────────────────────────────
info "Step 3/6: expect..."
if ! command -v expect >/dev/null 2>&1; then
  apt-get install -y -qq expect >/dev/null 2>&1
fi
log "expect $(expect -v 2>&1)"

# ── Step 4: установка Claude Code CLI ───────────────────────
info "Step 4/6: установка Claude Code CLI под $CC_USER..."
if USER_RUN 'command -v claude >/dev/null 2>&1'; then
  CC_VER=$(USER_RUN 'claude --version' 2>/dev/null | head -1)
  log "Claude Code уже стоит: $CC_VER"
else
  USER_RUN 'curl -fsSL https://claude.ai/install.sh | bash >/tmp/cc-install.log 2>&1' || {
    err "Установка claude провалилась. См. /tmp/cc-install.log"; exit 1; }
  CC_VER=$(USER_RUN 'claude --version' 2>/dev/null | head -1)
  log "Claude Code установлен: $CC_VER"
fi
CC_BIN=$(USER_RUN 'command -v claude' | head -1)
if [ -n "$CC_BIN" ] && [ "$CC_BIN" != "/usr/local/bin/claude" ]; then
  ln -sf "$CC_BIN" /usr/local/bin/claude
  log "симлинк /usr/local/bin/claude → $CC_BIN"
fi

# ── Step 5: текущий auth-статус ─────────────────────────────
info "Step 5/6: проверка auth-статуса..."
AUTH_JSON=$(USER_RUN 'claude auth status --json' 2>/dev/null || echo '{}')
LOGGED=$(echo "$AUTH_JSON" | awk '/"loggedIn"/{gsub(/[",]/,"",$2); print $2; exit}')
LOGGED="${LOGGED:-false}"
if [ "$LOGGED" = "true" ]; then
  log "$CC_USER уже авторизован — OAuth не требуется"
  mark_onboarding_done
  write_report "already_authed"
  log "Отчёт: $REPORT_FILE"
  exit 0
fi
info "не авторизован — запускаю OAuth flow (mode=$MODE)"

# Чистим прошлые подвисшие сессии
cleanup_oauth_session

# Команда запуска claude от имени юзера (для expect spawn)
if [ "$CC_USER" = "root" ]; then
  CLAUDE_CMD="bash -lc 'export PATH=\$HOME/.local/bin:\$PATH; claude auth login --claudeai'"
else
  CLAUDE_CMD="sudo -iu $CC_USER bash -lc 'export PATH=\$HOME/.local/bin:\$PATH; claude auth login --claudeai'"
fi

# ============================================================
#  Step 6 — Mode TTY (человек в живом терминале)
# ============================================================
if [ "$MODE" = "tty" ]; then
  if [ ! -t 0 ]; then
    err "--tty указан, но stdin не TTY. Запускай через ssh -t."
    write_report "error" "tty requested but no tty"
    exit 1
  fi
  info "Step 6/6: TTY-режим — открываю OAuth-сессию интерактивно..."
  expect <<EXPECT_EOF
log_file -a "$AUTH_LOG"
set timeout 60
spawn -noecho bash -lc {$CLAUDE_CMD}
expect {
  -re {https://claude\.com/cai/oauth/[^\s\r\n]+} {
    set url \$expect_out(0,string)
    send_user "\n────────────────────  OAUTH URL  ────────────────────\n"
    send_user "\$url\n"
    send_user "─────────────────────────────────────────────────────\n\n"
  }
  timeout { send_user "\n[ERR] no URL in 60s\n"; exit 2 }
  eof     { send_user "\n[ERR] claude exited early\n"; exit 3 }
}
expect -re {Paste code here[^\r\n]*}
send_user "Вставь код OAuth и Enter:\n> "
expect_user -re "(.*)\n"
set code [string trim \$expect_out(1,string)]
send -- "\$code\r"
set timeout 30
expect {
  -re {(Login successful|Logged in|Successfully|authenticated)} { send_user "\n[OK]\n" }
  -re {(Error|Invalid|Failed|expired)}                          { send_user "\n[ERR] rejected\n"; exit 6 }
  eof                                                            { }
  timeout                                                        { send_user "\n[WARN] timeout\n" }
}
catch {expect eof}
EXPECT_EOF
  sleep 1
  status_json=$(USER_RUN 'claude auth status --json' 2>/dev/null || echo "{}")
  LOGGED=$(echo "$status_json" | awk '/"loggedIn"/{gsub(/[",]/,"",$2); print $2; exit}')
  if [ "$LOGGED" = "true" ]; then
    log "✅ авторизация подтверждена"
    mark_onboarding_done
    write_report "authed"
    log "Отчёт: $REPORT_FILE"
    exit 0
  fi
  err "auth status loggedIn=false"
  write_report "auth_failed" "tty flow failed"
  exit 1
fi

# ============================================================
#  Step 6 — Mode AGENT (DEFAULT): фоновый expect + FIFO
# ============================================================
info "Step 6/6: AGENT-режим — стартую OAuth в фоне..."

# Генерируем expect-helper (читает код из FIFO)
cat > "$EXPECT_FILE" << EXPECT_EOF
#!/usr/bin/expect -f
log_user 1
set timeout 600
spawn -noecho bash -lc {$CLAUDE_CMD}
expect -re {https://claude\.com/cai/oauth/[^\s\r\n]+}
puts "CC_URL_LINE: \$expect_out(0,string)"
expect -re {Paste code here[^\r\n]*}
puts "CC_PROMPT_READY"
set chan [open "$AUTH_FIFO" r]
set code [string trim [gets \$chan]]
close \$chan
puts "CC_GOT_CODE_LEN: [string length \$code]"
send -- "\$code\r"
set timeout 30
expect {
  -re {(Login successful|Logged in|Successfully|authenticated)} { puts "CC_AUTH_SUCCESS" }
  -re {(Error|Invalid|Failed|expired)}                          { puts "CC_AUTH_FAILED" }
  eof                                                            { puts "CC_PROCESS_EOF" }
  timeout                                                        { puts "CC_TIMEOUT" }
}
catch {expect eof}
puts "CC_EXPECT_DONE"
EXPECT_EOF
chmod +x "$EXPECT_FILE"

mkfifo "$AUTH_FIFO"
: > "$AUTH_LOG"
setsid nohup "$EXPECT_FILE" > "$AUTH_LOG" 2>&1 < /dev/null &
BG_PID=$!
disown 2>/dev/null || true

# Ждём появления URL в логе (до 45 сек)
URL=""
for i in $(seq 1 45); do
  sleep 1
  URL=$(grep -oE 'https://claude\.com/cai/oauth/[^[:space:]]+' "$AUTH_LOG" 2>/dev/null | head -1)
  [ -n "$URL" ] && break
done

if [ -z "$URL" ]; then
  err "не дождался OAuth URL за 45 сек"
  tail -20 "$AUTH_LOG" 2>/dev/null | sed 's/^/    /'
  cleanup_oauth_session
  write_report "error" "no URL in 45s"
  exit 1
fi

# Маркеры для агента (парсимый формат)
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "CC_AUTH_URL=$URL"
echo "CC_AUTH_FIFO=$AUTH_FIFO"
echo "CC_AUTH_LOG=$AUTH_LOG"
echo "CC_AUTH_PID=$BG_PID"
echo "CC_AUTH_USER=$CC_USER"
echo "CC_AUTH_STATUS=awaiting_code"
echo "═══════════════════════════════════════════════════════════════"
echo ""
log "OAuth ждёт кода. Следующий шаг для агента:"
echo ""
echo "  1. Покажи юзеру URL (значение CC_AUTH_URL выше)."
echo "  2. Получи от юзера OAuth-код."
echo "  3. Выполни на этом сервере:"
echo "       $0 $CC_USER --send-code <КОД>"
echo "     Эта команда отправит код в FIFO, дождётся подтверждения,"
echo "     запишет /root/logs/claude-code-${CC_USER}-report.json"
echo ""
exit 0

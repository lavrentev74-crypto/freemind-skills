#!/bin/bash
# ============================================================
#  Upptime — GitHub Actions-based uptime monitor
#  Полностью бесплатный. TG-алерты. Checks на инфраструктуре GitHub.
#  Требует: gh CLI авторизован, TG_BOT_TOKEN, TG_CHAT_ID
#  Использование: setup-upptime.sh DOMAIN TG_TOKEN TG_CHAT_ID [REPO_NAME]
# ============================================================

set -euo pipefail

DOMAIN="${1:?Использование: $0 DOMAIN TG_TOKEN TG_CHAT_ID [REPO_NAME]}"
TG_TOKEN="${2:?TG_TOKEN обязателен}"
TG_CHAT_ID="${3:?TG_CHAT_ID обязателен}"
REPO_NAME="${4:-$(echo "$DOMAIN" | tr '.' '-')-uptime}"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

# ── 1. Checks ──────────────────────────────────────────────
command -v gh >/dev/null 2>&1 || { err "gh CLI не установлен. apt install gh или см. cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { err "gh не авторизован. Запусти: gh auth login --web"; exit 1; }

GH_USER=$(gh api user --jq .login)
log "GitHub user: $GH_USER"

# ── 2. Verify TG bot + chat ────────────────────────────────
info "Проверяю Telegram bot..."
BOT_INFO=$(curl -sS "https://api.telegram.org/bot${TG_TOKEN}/getMe")
echo "$BOT_INFO" | grep -q '"ok":true' || { err "TG bot token невалиден: $BOT_INFO"; exit 1; }
BOT_NAME=$(echo "$BOT_INFO" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['username'])")
log "TG bot: @$BOT_NAME"

info "Шлю тестовое сообщение в чат $TG_CHAT_ID..."
TEST_MSG=$(curl -sS "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -d "chat_id=${TG_CHAT_ID}" -d "text=Upptime setup: test OK ✅")
if ! echo "$TEST_MSG" | grep -q '"ok":true'; then
  err "TG тест failed: $TEST_MSG"
  err "Убедись что: 1) написал боту /start 2) CHAT_ID правильный (через @userinfobot)"
  exit 1
fi
log "TG тест прошёл — сообщение в чат доставлено"

# ── 3. Create repo from template ───────────────────────────
FULL_REPO="$GH_USER/$REPO_NAME"
if gh repo view "$FULL_REPO" >/dev/null 2>&1; then
  info "Репо $FULL_REPO уже существует — использую"
else
  info "Создаю репо $FULL_REPO из upptime template..."
  gh repo create "$FULL_REPO" --private --template=upptime/upptime --description "Uptime monitor for $DOMAIN"
  log "Репо создан: https://github.com/$FULL_REPO"
  # template bootstrap может заниматься 5-10 сек
  sleep 8
fi

# ── 4. Set secrets ─────────────────────────────────────────
info "Пишу GitHub secrets..."
# GH_PAT — для workflow-триггеров. Используем токен от текущей gh auth (он в keyring)
# Upptime рекомендует отдельный PAT, но для приватного репа текущий workflow-токен ок —
# используем `gh auth token` как GH_PAT.
GH_PAT=$(gh auth token)
echo "$GH_PAT"      | gh secret set GH_PAT      --repo "$FULL_REPO" --app actions
echo "$TG_TOKEN"    | gh secret set NOTIFICATION_TELEGRAM_BOT_TOKEN --repo "$FULL_REPO" --app actions
echo "$TG_CHAT_ID"  | gh secret set NOTIFICATION_TELEGRAM_CHAT_ID   --repo "$FULL_REPO" --app actions
log "Secrets: GH_PAT, NOTIFICATION_TELEGRAM_BOT_TOKEN, NOTIFICATION_TELEGRAM_CHAT_ID"

# ── 5. Generate .upptimerc.yml ─────────────────────────────
info "Собираю список субдоменов для мониторинга..."

# Server root check
SITES="  - name: Server root\n    url: https://$DOMAIN"

# Автодетект по compose-файлам (если есть SSH mount /root)
for DIR in /root/portainer /root/n8n /root/supabase/docker /root/lightrag /root/gitea /root/paperclip /root/openclaw /root/projects/*; do
  [ -d "$DIR" ] || continue
  NAME=$(basename "$DIR")
  [ "$NAME" = "docker" ] && NAME="supabase"
  for F in compose.yaml docker-compose.yml docker-compose.override.yml; do
    [ -f "$DIR/$F" ] || continue
    SUB=$(grep -o "caddy: *[a-z0-9-]*\.$DOMAIN" "$DIR/$F" 2>/dev/null | sed "s/caddy: *//" | head -1 || true)
    [ -n "$SUB" ] && SITES="$SITES\n  - name: $NAME\n    url: https://$SUB\n    expectedStatusCodes: [200, 301, 302, 401, 403, 405]"
  done
done

# ── 6. Clone repo locally, update config, push ─────────────
TMP=$(mktemp -d)
cd "$TMP"
git clone "https://x-access-token:${GH_PAT}@github.com/$FULL_REPO.git" repo
cd repo

cat > .upptimerc.yml <<EOF
owner: $GH_USER
repo: $REPO_NAME

sites:
$(echo -e "$SITES")

status-website:
  cname: ""
  baseUrl: /$REPO_NAME
  name: "$DOMAIN uptime"
  introTitle: "Статус сервисов $DOMAIN"
  introMessage: "Публичный статус всех сервисов."
  logoUrl: ""

notifications:
  - type: telegram
    telegramBotToken: \$NOTIFICATION_TELEGRAM_BOT_TOKEN
    telegramChatId: \$NOTIFICATION_TELEGRAM_CHAT_ID

workflowSchedule:
  uptime: "*/15 * * * *"
  responseTime: "0 0 * * *"
  staticSite: "0 0 * * *"
  summary: "0 0 * * *"

assignees:
  - $GH_USER

user-agent: "$REPO_NAME (Upptime; +https://github.com/$FULL_REPO)"

commitMessages:
  readmeContent: ":pencil: Update summary in README [skip ci] [upptime]"
  summaryJson: ":card_file_box: Update status summary [skip ci] [upptime]"
  statusChange: "\$EMOJI \$SITE_NAME is \$STATUS (\$RESPONSE_CODE in \$RESPONSE_TIME ms) [skip ci] [upptime]"
  commitAuthorName: "Upptime Bot"
  commitAuthorEmail: "bot@upptime.js.org"

skipPoweredByReadme: false
skipDescriptionReadme: false
EOF

git add .upptimerc.yml
git -c user.email="bot@upptime.js.org" -c user.name="Upptime Bot" commit -m "chore: configure $DOMAIN monitoring"
git push
cd /
rm -rf "$TMP"

log "Config запушен в репо"

# ── 7. Trigger first workflow ──────────────────────────────
info "Триггерю первый прогон Actions..."
sleep 3
gh workflow run uptime.yml --repo "$FULL_REPO" 2>/dev/null || \
  gh workflow run "Uptime CI" --repo "$FULL_REPO" 2>/dev/null || \
  info "Workflow сам запустится по cron (первый прогон в ближайшие 5 минут)"

# ── 8. Save state ──────────────────────────────────────────
mkdir -p /root/scripts
cat > /root/scripts/upptime-state.json <<EOF
{
  "provider": "upptime",
  "repo": "$FULL_REPO",
  "url": "https://github.com/$FULL_REPO",
  "status_page": "https://$GH_USER.github.io/$REPO_NAME/",
  "domain": "$DOMAIN",
  "tg_bot": "@$BOT_NAME",
  "tg_chat_id": "$TG_CHAT_ID"
}
EOF
chmod 600 /root/scripts/upptime-state.json

# ── Report ──────────────────────────────────────────────────
echo ""
log "================================================"
log "Upptime настроен"
log ""
log "Репо: https://github.com/$FULL_REPO"
log "Actions: https://github.com/$FULL_REPO/actions"
log "Status page (включится ~2 мин): https://$GH_USER.github.io/$REPO_NAME/"
log ""
log "TG-бот: @$BOT_NAME"
log "TG-чат: $TG_CHAT_ID"
log ""
log "Проверки каждые 15 минут (укладывается в 2000 мин/мес free tier для приватных репо)"
log "Хочешь чаще (каждые 5 мин) — нужен GitHub Pro (\$4/мес, 3000 мин) либо сделать репо публичным (Actions безлимитные, но виден список твоих сервисов)"
log "Алерты в TG при падении + GitHub Issue автосоздаётся"
log ""
log "Добавить сервис: edit .upptimerc.yml в репе → commit → push"
log "Или запусти этот скрипт повторно — он пересоберёт config"
log "================================================"

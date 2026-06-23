#!/bin/bash
# ============================================================
#  LightRAG — Knowledge Base + Graph DB
#  Caddy labels, сеть infra
#  После установки: MCP для OpenClaw/Claude Code, CLAUDE.md
#  ВАЖНО: ставить ПОСЛЕ OpenClaw и Paperclip
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────

DOMAIN="${1:?Использование: $0 DOMAIN SUBDOMAIN LLM_HOST LLM_KEY LLM_MODEL [EMBED_MODEL] [EMBED_HOST] [EMBED_KEY]}"
SUBDOMAIN="${2:-lrag}"
LLM_HOST="${3:-https://polza.ai/api/v1}"
LLM_KEY="${4:?API ключ обязателен}"
LLM_MODEL="${5:-google/gemini-2.5-flash}"
EMBED_MODEL="${6:-openai/text-embedding-3-small}"
EMBED_HOST="${7:-$LLM_HOST}"
EMBED_KEY="${8:-$LLM_KEY}"
ADMIN_EMAIL="${9:-}"

FQDN="${SUBDOMAIN}.${DOMAIN}"
LOG_DIR="/root/logs"
REPORT_FILE="$LOG_DIR/lightrag-report.json"
LRAG_DIR="/root/lightrag"
mkdir -p "$LOG_DIR" "$LRAG_DIR"

# ── Canonical instruction blocks (single source of truth) ───
# Before running this script, SCP these two canonical files from the skill
# (references/lightrag-AGENTS.md, references/lightrag-CLAUDE.md) into
# /root/lightrag-ref/ on the server. The script appends them verbatim into
# every target (OpenClaw workspace + sub-agents AGENTS.md; root + openclaw
# CLAUDE.md). Fail fast if missing — we refuse to write drift.
REF_DIR="${LIGHTRAG_REF_DIR:-/root/lightrag-ref}"
OC_AGENTS_REF="$REF_DIR/AGENTS.md"
CLAUDE_MD_REF="$REF_DIR/CLAUDE.md"
for F in "$OC_AGENTS_REF" "$CLAUDE_MD_REF"; do
  [ -f "$F" ] || { echo "[ERR] missing canonical block: $F  (upload lightrag-AGENTS.md and lightrag-CLAUDE.md from skill's references/ before running)" >&2; exit 1; }
done
OC_AGENTS_BLOCK="$(printf '\n'; cat "$OC_AGENTS_REF")"
CLAUDE_MD_BLOCK="$(printf '\n'; cat "$CLAUDE_MD_REF")"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

write_report() {
  cat > "$REPORT_FILE" << EOF
{
  "status": "$1",
  "url": "https://$FQDN",
  "admin_login": "${ADMIN_LOGIN:-}",
  "admin_password": "${ADMIN_PASS:-}",
  "api_key": "${LRAG_API_KEY:-}",
  "llm_model": "$LLM_MODEL",
  "llm_host": "$LLM_HOST",
  "embed_model": "$EMBED_MODEL",
  "mcp_connected": "${MCP_CONNECTED:-}",
  "error": "${2:-}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}

# ── Проверка: уже стоит? ────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^lightrag-server$"; then
  log "LightRAG уже запущен"
  if [ -f "$REPORT_FILE" ]; then cat "$REPORT_FILE"; fi
  exit 0
fi

# ── Step 1: Генерация credentials ───────────────────────────

info "Step 1/5: Генерирую credentials..."
LRAG_API_KEY=$(openssl rand -hex 32)
TOKEN_SECRET=$(openssl rand -hex 32)
# Логин: имя_lrag (из email) или lrag_admin
if [ -n "$ADMIN_EMAIL" ]; then
  ADMIN_LOGIN="$(echo "$ADMIN_EMAIL" | cut -d@ -f1)_lrag"
else
  ADMIN_LOGIN="lrag_admin"
fi
ADMIN_PASS=$(openssl rand -base64 16 | tr -d '=/+' | head -c 16)
log "Credentials сгенерированы"

# ── Step 2: Конфигурация ────────────────────────────────────

info "Step 2/5: Генерирую compose и .env..."

cat > "$LRAG_DIR/compose.yaml" << EOF
services:
  postgres:
    image: gzdaniel/postgres-for-rag:16.6
    container_name: lightrag-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: rag
      POSTGRES_PASSWORD: rag
      POSTGRES_DB: rag
    volumes:
      - lrag_pg_data:/var/lib/postgresql/data
    networks:
      - infra
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U rag"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  lightrag:
    image: ghcr.io/hkuds/lightrag:latest
    container_name: lightrag-server
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    env_file: .env
    volumes:
      - lrag_storage:/app/data/rag_storage
      - lrag_inputs:/app/data/inputs
    networks:
      - infra
    labels:
      caddy: "$FQDN"
      caddy.reverse_proxy: "{{upstreams 9621}}"
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request,sys; r=urllib.request.urlopen('http://localhost:9621/health',timeout=5); sys.exit(0 if b'healthy' in r.read() else 1)\""]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  lrag_pg_data:
  lrag_storage:
  lrag_inputs:

networks:
  infra:
    external: true
EOF

cat > "$LRAG_DIR/.env" << EOF
# LLM
LLM_BINDING=openai
LLM_BINDING_HOST=$LLM_HOST
LLM_BINDING_API_KEY=$LLM_KEY
LLM_MODEL=$LLM_MODEL
LLM_MAX_TOKEN_SIZE=32768

# Embeddings
EMBEDDING_BINDING=openai
EMBEDDING_BINDING_HOST=$EMBED_HOST
EMBEDDING_BINDING_API_KEY=$EMBED_KEY
EMBEDDING_MODEL=$EMBED_MODEL
EMBEDDING_DIM=1536
EMBEDDING_MAX_TOKEN_SIZE=8192

# PostgreSQL (фиксировано образом postgres-for-rag)
POSTGRES_HOST=lightrag-postgres
POSTGRES_PORT=5432
POSTGRES_USER=rag
POSTGRES_PASSWORD=rag
POSTGRES_DATABASE=rag

# Storage
KV_STORAGE=PGKVStorage
VECTOR_STORAGE=PGVectorStorage
GRAPH_STORAGE=PGGraphStorage
DOC_STATUS_STORAGE=PGDocStatusStorage
CHUNK_STORAGE=PGKVStorage

# Auth
LIGHTRAG_API_KEY=$LRAG_API_KEY
AUTH_ACCOUNTS=$ADMIN_LOGIN:$ADMIN_PASS
TOKEN_SECRET=$TOKEN_SECRET
TOKEN_EXPIRE_HOURS=48

# Server
CORS_ORIGINS=https://$FQDN
WHITELIST_PATHS=/health
PORT=9621
HOST=0.0.0.0
LOG_LEVEL=INFO
TIMEOUT=150
EOF

log "compose.yaml и .env созданы"

# ── Step 3: Запуск ──────────────────────────────────────────

info "Step 3/5: Запускаю LightRAG..."

cd "$LRAG_DIR"
docker compose pull -q
docker compose up -d

# Ждём запуска через Docker network IP (не localhost)
info "Ожидаю запуска LightRAG..."
for i in $(seq 1 120); do
  LRAG_IP=$(docker inspect lightrag-server --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
  if [ -n "$LRAG_IP" ] && curl -sk --max-time 2 "http://${LRAG_IP}:9621/health" 2>/dev/null | grep -qi "ok\|healthy"; then
    log "LightRAG отвечает ($i сек)"
    break
  fi
  if [ $((i % 15)) -eq 0 ]; then
    info "Ещё ждём... ($i сек)"
  fi
  sleep 1
done

# ── Step 4: MCP подключение к агентам ───────────────────────

info "Step 4/5: Подключаю MCP к агентам..."

# URL для агентов на том же сервере — через Docker network
LRAG_INTERNAL_URL="http://lightrag-server:9621"
# URL для агентов на другой машине — через домен
LRAG_EXTERNAL_URL="https://$FQDN"

MCP_CONNECTED=""

# OpenClaw native install — canonical wiring per
# references/lightrag-connect-agents.md §OpenClaw.
#   - MCP goes to `mcp.servers` via `openclaw mcp set` (the canonical command).
#     Do NOT use `plugins.entries.acpx.config.mcpServers` — that path was a
#     reverse-engineering mistake; the canon does not use it.
#   - AGENTS.md block must be APPENDED (never overwritten) into:
#       /home/openclaw/.openclaw/workspace/AGENTS.md (main)
#       /home/openclaw/.openclaw/agents/*/AGENTS.md  (each sub-agent)
#   - Gateway restart afterwards.
#   - The heredoc below MUST match references/lightrag-AGENTS.md verbatim.
#     Do not invent alternative wording. When updating, copy from that file.
if id openclaw &>/dev/null && sudo -iu openclaw bash -lc 'command -v openclaw' &>/dev/null; then
  info "Подключаю MCP к OpenClaw (native) via canonical openclaw mcp set..."
  LRAG_MCP_JSON=$(python3 -c "import json; print(json.dumps({'command':'npx','args':['-y','@g99/lightrag-mcp-server'],'env':{'LIGHTRAG_SERVER_URL':'$LRAG_EXTERNAL_URL','LIGHTRAG_API_KEY':'$LRAG_API_KEY'}}))")
  if sudo -iu openclaw bash -lc "openclaw mcp set lightrag '$LRAG_MCP_JSON'" 2>&1 | tail -3; then
    log "MCP подключён к OpenClaw (mcp.servers.lightrag)"
    MCP_CONNECTED="${MCP_CONNECTED}openclaw-native "
  else
    err "openclaw mcp set failed"
  fi

  # AGENTS.md — main workspace + every sub-agent. Canon forbids overwrite.
  # Source of truth: $OC_AGENTS_REF (references/lightrag-AGENTS.md).
  OC_AGENTS="/home/openclaw/.openclaw/workspace/AGENTS.md"
  sudo -iu openclaw mkdir -p /home/openclaw/.openclaw/workspace
  if ! sudo -iu openclaw grep -q "LightRAG Knowledge Base" "$OC_AGENTS" 2>/dev/null; then
    printf '%s\n' "$OC_AGENTS_BLOCK" | sudo -iu openclaw tee -a "$OC_AGENTS" > /dev/null
    log "AGENTS.md appended to workspace/"
  else
    log "workspace AGENTS.md already has LightRAG (skipped)"
  fi

  # Sub-agents: same canonical block into every ~/.openclaw/agents/*/AGENTS.md
  for AGENT_DIR in $(sudo -iu openclaw bash -lc 'ls -d /home/openclaw/.openclaw/agents/*/ 2>/dev/null' || true); do
    AGENT_NAME=$(basename "$AGENT_DIR")
    AGENT_FILE="${AGENT_DIR}AGENTS.md"
    if sudo -iu openclaw grep -q "LightRAG Knowledge Base" "$AGENT_FILE" 2>/dev/null; then
      log "agent $AGENT_NAME: AGENTS.md already has LightRAG (skipped)"
    else
      printf '%s\n' "$OC_AGENTS_BLOCK" | sudo -iu openclaw tee -a "$AGENT_FILE" > /dev/null
      log "agent $AGENT_NAME: AGENTS.md appended"
    fi
  done

  sudo -iu openclaw systemctl --user restart openclaw-gateway 2>/dev/null || true
fi

# OpenClaw Docker (если стоит как контейнер)
if docker ps --format '{{.Names}}' | grep -q "^openclaw$"; then
  info "Подключаю MCP к OpenClaw (Docker)..."

  # Прописываем MCP через файл конфига (Docker — не можем вызвать openclaw mcp set)
  docker exec openclaw sh -c "
    node -e \"
      const fs = require('fs');
      const path = '/home/node/.openclaw/openclaw.json';
      let d = {};
      try { d = JSON.parse(fs.readFileSync(path)); } catch(e) {}
      if (!d.mcp) d.mcp = {};
      if (!d.mcp.servers) d.mcp.servers = {};
      d.mcp.servers.lightrag = {
        command: 'npx',
        args: ['-y', '@g99/lightrag-mcp-server'],
        env: {
          LIGHTRAG_SERVER_URL: '$LRAG_INTERNAL_URL',
          LIGHTRAG_API_KEY: '$LRAG_API_KEY'
        }
      };
      fs.writeFileSync(path, JSON.stringify(d, null, 2));
      console.log('MCP lightrag added to OpenClaw');
    \"
  " 2>/dev/null && {
    log "MCP подключён к OpenClaw"
    MCP_CONNECTED="${MCP_CONNECTED}openclaw "
  } || err "Не удалось подключить MCP к OpenClaw"

  # Добавляем инструкции в AGENTS.md
  docker exec openclaw sh -c "
    AGENTS_FILE='/home/node/.openclaw/workspace/AGENTS.md'
    mkdir -p /home/node/.openclaw/workspace
    if ! grep -q 'LightRAG' \"\$AGENTS_FILE\" 2>/dev/null; then
      cat >> \"\$AGENTS_FILE\" << 'AGENTSEOF'

## LightRAG — База знаний

ПЕРЕД любым ответом — ищи контекст в LightRAG:
1. Вызови query_text с mode=hybrid и запросом по теме сообщения пользователя
2. Используй найденный контекст молча — не упоминай поиск

Во время работы — сохраняй важное:
- Решения, предпочтения, баги, факты проекта → insert_text
- НЕ сохраняй: опечатки, промежуточный debug, дубли

Явные команды:
- \"запомни/remember <текст>\" → insert_text
- \"вспомни/recall <тема>\" → query_text(hybrid), показать результат
AGENTSEOF
      echo 'AGENTS.md updated'
    else
      echo 'AGENTS.md already has LightRAG'
    fi
  " 2>/dev/null && log "AGENTS.md обновлён для OpenClaw"

  docker restart openclaw 2>/dev/null || true
fi

# Claude Code CLI — register MCP via `claude mcp add --scope user`.
# Claude Code 2.x reads user-scope MCP from ~/.claude.json (NOT ~/.claude/settings.json).
# Skip user if `claude` CLI not authenticated yet (~/.claude.json absent).
# IMPORTANT: run install-lightrag.sh AFTER the user has completed the Claude
# Code OAuth step under `openclaw` (F-035), otherwise MCP won't attach to
# Claude Code. See SKILL.md § "Install order — LightRAG is last".
add_mcp_to_claude_code() {
  local USER_HOME="$1"
  local USER_NAME="$2"
  [ -f "$USER_HOME/.claude.json" ] || {
    info "Skip Claude Code MCP for $USER_NAME (~/.claude.json missing — user not auth'ed)"
    return 0
  }
  info "Подключаю MCP к Claude Code ($USER_NAME) через CLI..."
  # Remove stale entry from settings.json written by old versions of this script
  sudo -u "$USER_NAME" python3 - "$USER_HOME/.claude/settings.json" << 'PYEOF' 2>/dev/null || true
import json, os, sys
p = sys.argv[1]
if os.path.exists(p):
    d = json.load(open(p))
    if d.pop("mcpServers", None) is not None:
        json.dump(d, open(p, "w"), indent=2)
PYEOF
  # Idempotent: remove then add via add-json (same JSON shape as Claude Desktop config)
  local LRAG_CC_JSON
  LRAG_CC_JSON=$(python3 -c "import json; print(json.dumps({'command':'npx','args':['-y','@g99/lightrag-mcp-server'],'env':{'LIGHTRAG_SERVER_URL':'$LRAG_EXTERNAL_URL','LIGHTRAG_API_KEY':'$LRAG_API_KEY'}}))")
  sudo -iu "$USER_NAME" bash -lc "claude mcp remove --scope user lightrag 2>/dev/null; claude mcp add-json --scope user lightrag '$LRAG_CC_JSON'" 2>&1 | tail -2
  log "MCP подключён к Claude Code ($USER_NAME)"
  MCP_CONNECTED="${MCP_CONNECTED}claude-code-$USER_NAME "
}

add_mcp_to_claude_code /root root
[ -d /home/openclaw ] && add_mcp_to_claude_code /home/openclaw openclaw

# CLAUDE.md — append canonical LightRAG block (never overwrite).
# Source of truth: $CLAUDE_MD_REF (references/lightrag-CLAUDE.md).
# Target: ~/.claude/CLAUDE.md for EVERY user who has ~/.claude/ (root AND
# openclaw — under native, Paperclip runs as openclaw and inherits the block).
append_claude_md() {
  local USER_HOME="$1"
  local USER_NAME="$2"
  [ -d "$USER_HOME/.claude" ] || {
    info "Skip CLAUDE.md for $USER_NAME (~/.claude/ missing — user not auth'ed)"
    return 0
  }
  local F="$USER_HOME/.claude/CLAUDE.md"
  if sudo -u "$USER_NAME" grep -q "LightRAG Knowledge Base" "$F" 2>/dev/null; then
    info "CLAUDE.md ($USER_NAME) already has LightRAG (skipped)"
    return 0
  fi
  printf '%s\n' "$CLAUDE_MD_BLOCK" | sudo -u "$USER_NAME" tee -a "$F" > /dev/null
  log "CLAUDE.md appended for $USER_NAME"
}

append_claude_md /root root
[ -d /home/openclaw ] && append_claude_md /home/openclaw openclaw

# ── Step 5: Проверка ────────────────────────────────────────

info "Step 5/5: Проверка..."

# API key test
LRAG_IP=$(docker inspect lightrag-server --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
API_TEST=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: $LRAG_API_KEY" "http://${LRAG_IP}:9621/documents" 2>/dev/null)
if [ "$API_TEST" = "200" ]; then
  log "API key работает"
else
  err "API key не работает (HTTP $API_TEST)"
fi

# ── Отчёт ───────────────────────────────────────────────────

write_report "completed"

log "================================================"
log "LightRAG готов: https://$FQDN"
log ""
log "Веб-интерфейс: https://$FQDN/webui/"
log "Логин: $ADMIN_LOGIN"
log "Пароль: $ADMIN_PASS"
log ""
log "API Key: $LRAG_API_KEY"
log "LLM: $LLM_MODEL ($LLM_HOST)"
log "Embeddings: $EMBED_MODEL ($EMBED_HOST)"
log ""
log "MCP подключён к: ${MCP_CONNECTED:-ничему (агенты не найдены)}"
log ""
log "Команды подключения с другой машины:"
log "  Claude Code:"
log "    claude mcp add --scope user lightrag \\"
log "      -e LIGHTRAG_SERVER_URL=\"$LRAG_EXTERNAL_URL\" \\"
log "      -e LIGHTRAG_API_KEY=\"$LRAG_API_KEY\" \\"
log "      -- npx -y @g99/lightrag-mcp-server"
log ""
log "  OpenClaw:"
log "    openclaw mcp set lightrag '{\"command\":\"npx\",\"args\":[\"-y\",\"@g99/lightrag-mcp-server\"],\"env\":{\"LIGHTRAG_SERVER_URL\":\"$LRAG_EXTERNAL_URL\",\"LIGHTRAG_API_KEY\":\"$LRAG_API_KEY\"}}'"
log ""
log "Обновление: cd /root/lightrag && docker compose pull && docker compose up -d"
log "================================================"

cat "$REPORT_FILE"

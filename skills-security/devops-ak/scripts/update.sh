#!/bin/bash
# ============================================================
#  Обновление сервисов: docker compose pull + recreate
#  Использование:
#    update.sh              — обновить всё
#    update.sh n8n          — только n8n
#    update.sh n8n portainer — несколько сервисов
# ============================================================

set -euo pipefail

SERVICES="${@:-all}"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

update_service() {
  local NAME="$1"
  local DIR="$2"

  [ -d "$DIR" ] || return
  COMPOSE=""
  for CAND in "$DIR/compose.yaml" "$DIR/docker-compose.yml"; do
    [ -f "$CAND" ] && COMPOSE="$CAND" && break
  done
  [ -z "$COMPOSE" ] && return

  info "Обновляю $NAME..."
  cd "$DIR"

  # Определяем тип: image (pull) или build (git pull + rebuild)
  HAS_BUILD=$(grep -l "build:" "$COMPOSE" 2>/dev/null || true)

  if [ -n "$HAS_BUILD" ]; then
    # Проект собирается из исходников — git pull + rebuild
    SRC_DIR=$(grep -A1 "build:" "$COMPOSE" | grep "context:" | sed 's/.*context: *//' | tr -d ' ' || echo "./src")
    SRC_DIR="${SRC_DIR#./}"
    [ -d "$DIR/$SRC_DIR/.git" ] && (cd "$DIR/$SRC_DIR" && git pull -q 2>/dev/null)
    docker compose up -d --build 2>/dev/null
    log "$NAME — пересобран из исходников"
  else
    # Готовый image — pull
    OLD_IMAGES=$(docker compose images -q 2>/dev/null | sort)
    docker compose pull -q 2>/dev/null
    NEW_IMAGES=$(docker compose images -q 2>/dev/null | sort)

    if [ "$OLD_IMAGES" = "$NEW_IMAGES" ]; then
      log "$NAME — уже актуален"
    else
      docker compose up -d 2>/dev/null
      log "$NAME — обновлён"
    fi
  fi

  sleep 3
  RUNNING=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | head -3)
  echo "  $RUNNING"
}

# Маппинг сервис → директория
declare -A DIRS=(
  [caddy]="/root/caddy"
  [portainer]="/root/portainer"
  [n8n]="/root/n8n"
  [supabase]="/root/supabase/docker"
  [lightrag]="/root/lightrag"
  [gitea]="/root/gitea"
  [openclaw]="/root/openclaw"
  [paperclip]="/root/paperclip"
)

info "Обновление: $SERVICES"
echo ""

if [ "$SERVICES" = "all" ]; then
  for NAME in caddy portainer n8n supabase lightrag gitea openclaw paperclip; do
    update_service "$NAME" "${DIRS[$NAME]}"
  done
  # Кастомные проекты
  for DIR in /root/projects/*/; do
    [ -d "$DIR" ] || continue
    NAME=$(basename "$DIR")
    update_service "$NAME" "$DIR"
  done
else
  for NAME in $SERVICES; do
    if [ -n "${DIRS[$NAME]:-}" ]; then
      update_service "$NAME" "${DIRS[$NAME]}"
    elif [ -d "/root/projects/$NAME" ]; then
      update_service "$NAME" "/root/projects/$NAME"
    else
      err "$NAME — не найден"
    fi
  done
fi

echo ""
log "Обновление завершено"

#!/bin/bash
# ============================================================
#  Восстановление сервисов из бэкапа
#  Использование:
#    restore.sh n8n              — из последнего бэкапа
#    restore.sh n8n 20260412     — из конкретной даты
#    restore.sh all              — все сервисы из последних бэкапов
# ============================================================

set -euo pipefail

SERVICE="${1:?Использование: $0 СЕРВИС [ДАТА]
  Сервисы: all, portainer, n8n, supabase, lightrag, gitea, openclaw, paperclip, caddy}"
DATE_FILTER="${2:-}"
BACKUP_DIR="/root/backups"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

# ── Функции ─────────────────────────────────────────────────

find_backup() {
  local PATTERN="$1"
  if [ -n "$DATE_FILTER" ]; then
    ls -1t $BACKUP_DIR/${PATTERN}*${DATE_FILTER}* 2>/dev/null | head -1
  else
    ls -1t $BACKUP_DIR/${PATTERN}* 2>/dev/null | head -1
  fi
}

restore_volume() {
  local VOLUME="$1"
  local NAME="$2"
  local FILE=$(find_backup "${NAME}-")
  [ -z "$FILE" ] && { err "Бэкап $NAME не найден"; return 1; }
  info "Восстанавливаю $NAME из $(basename $FILE)..."
  docker run --rm -v "$VOLUME":/data -v "$BACKUP_DIR":/backup alpine \
    sh -c "rm -rf /data/* && tar xzf /backup/$(basename $FILE) -C /" 2>/dev/null
  log "$NAME восстановлен"
}

restore_postgres() {
  local CONTAINER="$1"
  local USER="$2"
  local NAME="$3"
  local PASSWORD="${4:-$USER}"
  local FILE=$(find_backup "${NAME}-db-")
  [ -z "$FILE" ] && { err "Бэкап ${NAME}-db не найден"; return 1; }
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    err "Контейнер $CONTAINER не запущен"
    return 1
  fi
  info "Восстанавливаю ${NAME}-db из $(basename $FILE)..."
  # pipefail-safe: psql может ругаться на дубли/FK, но данные заливаются
  zcat "$FILE" | docker exec -i -e PGPASSWORD="$PASSWORD" "$CONTAINER" psql -U "$USER" -h localhost 2>/dev/null || true
  log "${NAME}-db восстановлен"
}

# ── Восстановление по сервисам ──────────────────────────────

do_portainer() {
  info "Останавливаю Portainer..."
  cd /root/portainer && docker compose stop 2>/dev/null
  restore_volume "portainer_portainer_data" "portainer"
  docker compose start 2>/dev/null
  log "Portainer перезапущен"
}

do_n8n() {
  info "Останавливаю n8n..."
  cd /root/n8n && docker compose stop n8n 2>/dev/null || true
  restore_volume "n8n_n8n_data" "n8n" || true
  N8N_PG_PASS=$(grep "POSTGRES_PASSWORD" /root/n8n/compose.yaml 2>/dev/null | head -1 | sed 's/.*POSTGRES_PASSWORD: //' || echo "postgres")
  restore_postgres "n8n-postgres" "postgres" "n8n" "$N8N_PG_PASS" || true
  docker compose start n8n 2>/dev/null || docker compose up -d n8n 2>/dev/null
  log "n8n перезапущен"
}

do_supabase() {
  info "Останавливаю Supabase (кроме БД)..."
  cd /root/supabase/docker
  # Останавливаем всё кроме БД
  docker compose stop kong studio auth rest realtime storage imgproxy meta vector analytics edge-functions supavisor 2>/dev/null || true
  SUPABASE_PG_USER=$(grep "^POSTGRES_USER=" .env 2>/dev/null | cut -d= -f2 || echo "supabase_admin")
  SUPABASE_PG_PASS=$(grep "^POSTGRES_PASSWORD=" .env 2>/dev/null | cut -d= -f2 || echo "")
  restore_postgres "supabase-db" "${SUPABASE_PG_USER}" "supabase" "${SUPABASE_PG_PASS}"
  docker compose start 2>/dev/null
  log "Supabase перезапущен"
}

do_lightrag() {
  info "Останавливаю LightRAG..."
  cd /root/lightrag && docker compose stop lightrag 2>/dev/null
  restore_volume "lightrag_lrag_storage" "lightrag"
  restore_postgres "lightrag-postgres" "rag" "lightrag" "rag" || true
  docker compose start lightrag 2>/dev/null
  log "LightRAG перезапущен"
}

do_gitea() {
  info "Останавливаю Gitea..."
  cd /root/gitea && docker compose stop server 2>/dev/null
  # Data из tar
  FILE=$(find_backup "gitea-data-")
  if [ -n "$FILE" ]; then
    info "Восстанавливаю gitea-data из $(basename $FILE)..."
    rm -rf /root/gitea/data
    tar xzf "$FILE" -C /root/gitea
    log "gitea-data восстановлен"
  fi
  GITEA_DB_USER=$(grep GITEA_DB_USER /root/gitea/.env 2>/dev/null | cut -d= -f2 || echo "gitea")
  GITEA_DB_PASS=$(grep GITEA_DB_PASS /root/gitea/.env 2>/dev/null | cut -d= -f2 || echo "gitea")
  restore_postgres "gitea-db" "$GITEA_DB_USER" "gitea" "$GITEA_DB_PASS"
  docker compose start server 2>/dev/null
  log "Gitea перезапущен"
}

do_openclaw() {
  FILE=$(find_backup "openclaw-")
  [ -z "$FILE" ] && { err "Бэкап openclaw не найден"; return 1; }
  info "Останавливаю OpenClaw..."
  cd /root/openclaw && docker compose stop 2>/dev/null
  rm -rf /root/openclaw/data
  tar xzf "$FILE" -C /root/openclaw
  docker compose start 2>/dev/null
  log "OpenClaw восстановлен и перезапущен"
}

do_paperclip() {
  FILE=$(find_backup "paperclip-")
  [ -z "$FILE" ] && { err "Бэкап paperclip не найден"; return 1; }
  info "Останавливаю Paperclip..."
  cd /root/paperclip && docker compose stop 2>/dev/null
  rm -rf /root/paperclip/data
  tar xzf "$FILE" -C /root/paperclip
  docker compose start 2>/dev/null
  log "Paperclip восстановлен и перезапущен"
}

do_caddy() {
  restore_volume "caddy_caddy_data" "caddy"
  docker restart caddy 2>/dev/null
  log "Caddy перезапущен"
}

# ── Запуск ──────────────────────────────────────────────────

info "Восстановление: $SERVICE${DATE_FILTER:+ (дата: $DATE_FILTER)}"
echo ""

case "$SERVICE" in
  all)
    # Сначала конфиги — .env, compose, настройки
    FILE=$(find_backup "configs-")
    if [ -n "$FILE" ]; then
      info "Восстанавливаю конфиги из $(basename $FILE)..."
      tar xzf "$FILE" -C / 2>/dev/null
      log "Конфиги восстановлены (.env, compose, настройки)"
    fi
    do_portainer; do_n8n; do_supabase; do_lightrag
    do_gitea; do_openclaw; do_paperclip; do_caddy
    ;;
  portainer) do_portainer ;;
  n8n) do_n8n ;;
  supabase) do_supabase ;;
  lightrag) do_lightrag ;;
  gitea) do_gitea ;;
  openclaw) do_openclaw ;;
  paperclip) do_paperclip ;;
  caddy) do_caddy ;;
  *)
    # Кастомный проект из /root/projects/
    if [ -d "/root/projects/$SERVICE" ]; then
      info "Восстанавливаю кастомный проект: $SERVICE..."
      cd "/root/projects/$SERVICE"
      docker compose stop 2>/dev/null || true

      # Data
      FILE=$(find_backup "custom-${SERVICE}-data-")
      if [ -n "$FILE" ]; then
        rm -rf "/root/projects/$SERVICE/data"
        tar xzf "$FILE" -C "/root/projects/$SERVICE"
        log "${SERVICE} data восстановлен"
      fi

      # Volumes
      for VFILE in $(ls -1t $BACKUP_DIR/custom-${SERVICE}-*${DATE_FILTER}*.tar.gz 2>/dev/null | grep -v "data-"); do
        VOL=$(basename "$VFILE" | sed "s/custom-${SERVICE}-//; s/-${DATE_FILTER}.*//; s/-[0-9]*-[0-9]*.tar.gz//")
        if docker volume inspect "$VOL" &>/dev/null; then
          docker run --rm -v "$VOL":/data -v "$BACKUP_DIR":/backup alpine \
            sh -c "rm -rf /data/* && tar xzf /backup/$(basename $VFILE) -C /" 2>/dev/null
          log "$VOL восстановлен"
        fi
      done

      docker compose start 2>/dev/null || docker compose up -d 2>/dev/null
      log "$SERVICE перезапущен"
    else
      err "Неизвестный сервис: $SERVICE"
      echo "Доступные: all, portainer, n8n, supabase, lightrag, gitea, openclaw, paperclip, caddy"
      echo "Кастомные: $(ls /root/projects/ 2>/dev/null | tr '\n' ' ')"
      exit 1
    fi
    ;;
esac

echo ""
log "Восстановление завершено"

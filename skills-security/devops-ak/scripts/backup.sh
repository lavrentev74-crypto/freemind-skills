#!/bin/bash
# ============================================================
#  Бэкап сервисов: volumes + PostgreSQL dumps
#  Использование:
#    backup.sh              — бэкап всех сервисов (2 копии)
#    backup.sh n8n          — только n8n
#    backup.sh all 3        — все сервисы, хранить 3 копии
#    backup.sh supabase 1   — только Supabase, 1 копия
# ============================================================

set -euo pipefail

SERVICE="${1:-all}"
MAX_COPIES="${2:-2}"
BACKUP_DIR="/root/backups"
DATE=$(date +%Y%m%d-%H%M)
mkdir -p "$BACKUP_DIR" "/root/logs"

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

BACKED_UP=""

# ── Бэкап конфигов (.env, compose, конфиги) ─────────────────

backup_configs() {
  info "Бэкап конфигов..."
  local CONFIGS_FILE="$BACKUP_DIR/configs-${DATE}.tar.gz"
  local FILES=""

  # Собираем все .env и compose файлы
  for DIR in /root/portainer /root/n8n /root/supabase/docker /root/lightrag /root/gitea /root/openclaw /root/paperclip; do
    [ -d "$DIR" ] || continue
    for F in .env compose.yaml docker-compose.yml docker-compose.override.yml; do
      [ -f "$DIR/$F" ] && FILES="$FILES $DIR/$F"
    done
  done

  # Конфиги OpenClaw (openclaw.json, SOUL.md, USER.md)
  for F in /root/openclaw/data/openclaw.json /root/openclaw/data/SOUL.md /root/openclaw/data/USER.md; do
    [ -f "$F" ] && FILES="$FILES $F"
  done

  # Конфиги Paperclip
  [ -f "/root/paperclip/data/instances/default/config.json" ] && FILES="$FILES /root/paperclip/data/instances/default/config.json"

  # Gitea app.ini
  # (внутри контейнера — вытянем через docker cp)
  if docker ps --format '{{.Names}}' | grep -q "^gitea$"; then
    docker cp gitea:/data/gitea/conf/app.ini /tmp/gitea-app.ini 2>/dev/null && FILES="$FILES /tmp/gitea-app.ini"
  fi

  # Кастомные проекты
  for DIR in /root/projects/*/; do
    [ -d "$DIR" ] || continue
    for F in .env compose.yaml docker-compose.yml Dockerfile; do
      [ -f "$DIR/$F" ] && FILES="$FILES $DIR/$F"
    done
  done

  if [ -n "$FILES" ]; then
    tar czf "$CONFIGS_FILE" $FILES 2>/dev/null
    log "configs: $(ls -lh "$CONFIGS_FILE" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP configs"
    rotate "configs-"
  fi
}

# ── Функции ─────────────────────────────────────────────────

backup_volume() {
  local VOLUME="$1"
  local NAME="$2"
  if docker volume inspect "$VOLUME" &>/dev/null; then
    docker run --rm -v "$VOLUME":/data -v "$BACKUP_DIR":/backup alpine \
      tar czf "/backup/${NAME}-${DATE}.tar.gz" -C / data 2>/dev/null
    log "$NAME: $(ls -lh "$BACKUP_DIR/${NAME}-${DATE}.tar.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP $NAME"
  fi
}

backup_postgres() {
  local CONTAINER="$1"
  local USER="$2"
  local NAME="$3"
  local PASSWORD="${4:-$USER}"
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    docker exec -e PGPASSWORD="$PASSWORD" "$CONTAINER" pg_dumpall -U "$USER" -h localhost 2>/dev/null \
      | gzip > "$BACKUP_DIR/${NAME}-db-${DATE}.sql.gz"
    log "${NAME}-db: $(ls -lh "$BACKUP_DIR/${NAME}-db-${DATE}.sql.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP ${NAME}-db"
  fi
}

rotate() {
  local PATTERN="$1"
  local COUNT=$(ls -1t $BACKUP_DIR/${PATTERN}* 2>/dev/null | wc -l)
  if [ "$COUNT" -gt "$MAX_COPIES" ]; then
    ls -1t $BACKUP_DIR/${PATTERN}* | tail -n $((COUNT - MAX_COPIES)) | xargs rm -f
  fi
}

# ── Бэкап по сервисам ───────────────────────────────────────

do_portainer() {
  backup_volume "portainer_portainer_data" "portainer"
  rotate "portainer-"
}

do_n8n() {
  backup_volume "n8n_n8n_data" "n8n"
  N8N_PG_PASS=$(grep "POSTGRES_PASSWORD" /root/n8n/compose.yaml 2>/dev/null | head -1 | sed 's/.*POSTGRES_PASSWORD: //' || echo "postgres")
  backup_postgres "n8n-postgres" "postgres" "n8n" "$N8N_PG_PASS"
  rotate "n8n-2"
  rotate "n8n-db-"
}

do_supabase() {
  SUPABASE_PG_USER=$(grep "^POSTGRES_USER=" /root/supabase/docker/.env 2>/dev/null | cut -d= -f2 || echo "supabase_admin")
  SUPABASE_PG_PASS=$(grep "^POSTGRES_PASSWORD=" /root/supabase/docker/.env 2>/dev/null | cut -d= -f2 || echo "")
  backup_postgres "supabase-db" "${SUPABASE_PG_USER:-supabase_admin}" "supabase" "${SUPABASE_PG_PASS:-supabase_admin}"
  rotate "supabase-db-"
}

do_lightrag() {
  backup_volume "lightrag_lrag_storage" "lightrag"
  if docker ps --format '{{.Names}}' | grep -q "^lightrag-postgres$"; then
    docker exec -e PGPASSWORD=rag lightrag-postgres pg_dumpall -U rag -h localhost 2>/dev/null \
      | gzip > "$BACKUP_DIR/lightrag-db-${DATE}.sql.gz"
    log "lightrag-db: $(ls -lh "$BACKUP_DIR/lightrag-db-${DATE}.sql.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP lightrag-db"
  fi
  rotate "lightrag-2"
  rotate "lightrag-db-"
}

do_gitea() {
  if [ -d "/root/gitea/data" ]; then
    tar czf "$BACKUP_DIR/gitea-data-${DATE}.tar.gz" -C /root/gitea data 2>/dev/null
    log "gitea-data: $(ls -lh "$BACKUP_DIR/gitea-data-${DATE}.tar.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP gitea-data"
  fi
  GITEA_DB_USER=$(grep GITEA_DB_USER /root/gitea/.env 2>/dev/null | cut -d= -f2 || echo "gitea")
  GITEA_DB_PASS=$(grep GITEA_DB_PASS /root/gitea/.env 2>/dev/null | cut -d= -f2 || echo "gitea")
  backup_postgres "gitea-db" "$GITEA_DB_USER" "gitea" "$GITEA_DB_PASS"
  rotate "gitea-data-"
  rotate "gitea-db-"
}

do_openclaw() {
  if [ -d "/root/openclaw/data" ]; then
    tar czf "$BACKUP_DIR/openclaw-${DATE}.tar.gz" -C /root/openclaw data 2>/dev/null
    log "openclaw: $(ls -lh "$BACKUP_DIR/openclaw-${DATE}.tar.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP openclaw"
  fi
  rotate "openclaw-"
}

do_paperclip() {
  if [ -d "/root/paperclip/data" ]; then
    tar czf "$BACKUP_DIR/paperclip-${DATE}.tar.gz" -C /root/paperclip data 2>/dev/null
    log "paperclip: $(ls -lh "$BACKUP_DIR/paperclip-${DATE}.tar.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP paperclip"
  fi
  rotate "paperclip-"
}

do_caddy() {
  backup_volume "caddy_caddy_data" "caddy"
  rotate "caddy-"
}

# Кастомные проекты из /root/projects/
do_custom_single() {
  local NAME="$1"
  local DIR="/root/projects/$NAME"
  [ ! -d "$DIR" ] && return

  # Бэкапим Docker volumes если есть compose
  if [ -f "$DIR/compose.yaml" ] || [ -f "$DIR/docker-compose.yml" ]; then
    COMPOSE_FILE=$(ls "$DIR"/compose.yaml "$DIR"/docker-compose.yml 2>/dev/null | head -1)
    # Находим volumes
    VOLUMES=$(cd "$DIR" && docker compose ps -q 2>/dev/null | xargs -I{} docker inspect {} --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' 2>/dev/null | tr ' ' '\n' | sort -u)
    for VOL in $VOLUMES; do
      [ -z "$VOL" ] && continue
      backup_volume "$VOL" "custom-${NAME}-${VOL}"
      rotate "custom-${NAME}-${VOL}-"
    done
  fi

  # Бэкапим data/ папку если есть
  if [ -d "$DIR/data" ]; then
    tar czf "$BACKUP_DIR/custom-${NAME}-data-${DATE}.tar.gz" -C "$DIR" data 2>/dev/null
    log "custom-${NAME}-data: $(ls -lh "$BACKUP_DIR/custom-${NAME}-data-${DATE}.tar.gz" | awk '{print $5}')"
    BACKED_UP="$BACKED_UP custom-${NAME}-data"
    rotate "custom-${NAME}-data-"
  fi
}

do_custom() {
  [ ! -d "/root/projects" ] && return
  for DIR in /root/projects/*/; do
    [ ! -d "$DIR" ] && continue
    NAME=$(basename "$DIR")
    do_custom_single "$NAME"
  done
}

# ── Запуск ──────────────────────────────────────────────────

info "Бэкап: ${SERVICE} (хранить ${MAX_COPIES} копий)..."

case "$SERVICE" in
  all)
    backup_configs
    do_portainer; do_n8n; do_supabase; do_lightrag
    do_gitea; do_openclaw; do_paperclip; do_caddy
    do_custom
    ;;
  portainer) do_portainer ;;
  n8n) do_n8n ;;
  supabase) do_supabase ;;
  lightrag) do_lightrag ;;
  gitea) do_gitea ;;
  openclaw) do_openclaw ;;
  paperclip) do_paperclip ;;
  caddy) do_caddy ;;
  custom)
    # Бэкап всех кастомных проектов из /root/projects/
    do_custom
    ;;
  *)
    # Может быть кастомный проект по имени
    if [ -d "/root/projects/$SERVICE" ]; then
      do_custom_single "$SERVICE"
    else
      err "Неизвестный сервис: $SERVICE"
      echo "Доступные: all, portainer, n8n, supabase, lightrag, gitea, openclaw, paperclip, caddy, custom"
      echo "Кастомные проекты: $(ls /root/projects/ 2>/dev/null | tr '\n' ' ')"
      exit 1
    fi
    ;;
esac

TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
log "Бэкап завершён. $BACKUP_DIR ($TOTAL_SIZE)"

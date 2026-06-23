#!/bin/bash
# ============================================================
#  Cloudflare DNS — полное управление DNS записями и зонами
#  Действия: create, update, delete, list, add-zone, check-zone
# ============================================================

set -euo pipefail

# ── Параметры ───────────────────────────────────────────────

ACTION="${1:?Использование: $0 ACTION CF_TOKEN ...
  create  CF_TOKEN ZONE_ID DOMAIN SERVER_IP SUBDOMAIN [TYPE]  — создать/обновить запись
  delete  CF_TOKEN ZONE_ID DOMAIN SUBDOMAIN [TYPE]            — удалить запись
  list    CF_TOKEN ZONE_ID                                    — показать все записи
  add-zone CF_TOKEN DOMAIN                                    — добавить домен в CF
  check-zone CF_TOKEN DOMAIN                                  — проверить статус зоны
}"
CF_TOKEN="${2:?CF_TOKEN обязателен}"

LOG_DIR="/root/logs"
mkdir -p "$LOG_DIR"

# ── Helpers ─────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] [OK] $1"; }
info() { echo "[$(date '+%H:%M:%S')] [..] $1"; }
err()  { echo "[$(date '+%H:%M:%S')] [ERR] $1" >&2; }

cf_api() {
  local METHOD="$1"
  local ENDPOINT="$2"
  local DATA="${3:-}"
  local RESPONSE

  for attempt in 1 2 3; do
    if [ -n "$DATA" ]; then
      RESPONSE=$(curl -s -X "$METHOD" \
        "https://api.cloudflare.com/client/v4$ENDPOINT" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$DATA" 2>/dev/null)
    else
      RESPONSE=$(curl -s -X "$METHOD" \
        "https://api.cloudflare.com/client/v4$ENDPOINT" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" 2>/dev/null)
    fi

    if echo "$RESPONSE" | grep -q '"success":true'; then
      echo "$RESPONSE"
      return 0
    fi

    if [ "$attempt" -lt 3 ]; then
      sleep $((attempt * 2))
    fi
  done

  echo "$RESPONSE"
  return 1
}

# ── ACTION: create (создать или обновить запись) ─────────────

if [ "$ACTION" = "create" ]; then
  ZONE_ID="${3:?ZONE_ID обязателен}"
  DOMAIN="${4:?DOMAIN обязателен}"
  SERVER_IP="${5:?SERVER_IP обязателен}"
  SUBDOMAIN="${6:?SUBDOMAIN обязателен}"
  RECORD_TYPE="${7:-A}"
  FQDN="${SUBDOMAIN}.${DOMAIN}"

  info "Проверяю DNS запись для $FQDN..."

  EXISTING=$(cf_api GET "/zones/$ZONE_ID/dns_records?name=$FQDN&type=$RECORD_TYPE" || echo '{"success":false}')
  RECORD_ID=""

  if echo "$EXISTING" | grep -q "\"name\":\"$FQDN\""; then
    RECORD_ID=$(echo "$EXISTING" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    EXISTING_IP=$(echo "$EXISTING" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ "$EXISTING_IP" = "$SERVER_IP" ]; then
      log "$FQDN уже указывает на $SERVER_IP"
      exit 0
    fi

    info "Обновляю $FQDN: $EXISTING_IP → $SERVER_IP..."
    RESP=$(cf_api PUT "/zones/$ZONE_ID/dns_records/$RECORD_ID" \
      "{\"type\":\"$RECORD_TYPE\",\"name\":\"$FQDN\",\"content\":\"$SERVER_IP\",\"ttl\":1,\"proxied\":false}" || echo "")

    if echo "$RESP" | grep -q '"success":true'; then
      log "DNS обновлена: $FQDN → $SERVER_IP"
    else
      err "Не удалось обновить: $RESP"
      exit 1
    fi
  else
    info "Создаю DNS запись: $FQDN → $SERVER_IP..."
    RESP=$(cf_api POST "/zones/$ZONE_ID/dns_records" \
      "{\"type\":\"$RECORD_TYPE\",\"name\":\"$FQDN\",\"content\":\"$SERVER_IP\",\"ttl\":1,\"proxied\":false}" || echo "")

    if echo "$RESP" | grep -q '"success":true'; then
      log "DNS создана: $FQDN → $SERVER_IP"
    else
      err "Не удалось создать: $RESP"
      exit 1
    fi
  fi

# ── ACTION: delete (удалить запись) ──────────────────────────

elif [ "$ACTION" = "delete" ]; then
  ZONE_ID="${3:?ZONE_ID обязателен}"
  DOMAIN="${4:?DOMAIN обязателен}"
  SUBDOMAIN="${5:?SUBDOMAIN обязателен}"
  RECORD_TYPE="${6:-A}"
  FQDN="${SUBDOMAIN}.${DOMAIN}"

  info "Ищу DNS запись $FQDN..."

  EXISTING=$(cf_api GET "/zones/$ZONE_ID/dns_records?name=$FQDN&type=$RECORD_TYPE" || echo '{"success":false}')
  RECORD_ID=$(echo "$EXISTING" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ -z "$RECORD_ID" ]; then
    log "$FQDN не найдена — нечего удалять"
    exit 0
  fi

  info "Удаляю DNS запись $FQDN (ID: $RECORD_ID)..."
  RESP=$(cf_api DELETE "/zones/$ZONE_ID/dns_records/$RECORD_ID" || echo "")

  if echo "$RESP" | grep -q '"success":true'; then
    log "DNS удалена: $FQDN"
  else
    err "Не удалось удалить: $RESP"
    exit 1
  fi

# ── ACTION: list (показать все записи зоны) ──────────────────

elif [ "$ACTION" = "list" ]; then
  ZONE_ID="${3:?ZONE_ID обязателен}"

  info "Получаю все DNS записи..."

  RESP=$(cf_api GET "/zones/$ZONE_ID/dns_records?per_page=100" || echo '{"success":false}')

  if echo "$RESP" | grep -q '"success":true'; then
    echo "$RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('result', [])
print(f'Записей: {len(records)}')
print(f'{\"Тип\":<6} {\"Имя\":<40} {\"Значение\":<20} {\"Proxied\":<8} {\"TTL\"}')
print('-' * 90)
for r in sorted(records, key=lambda x: (x['type'], x['name'])):
    print(f'{r[\"type\"]:<6} {r[\"name\"]:<40} {r[\"content\"]:<20} {str(r.get(\"proxied\",\"\")):<8} {r.get(\"ttl\",\"\")}')
" 2>/dev/null || echo "$RESP"
  else
    err "Не удалось получить записи"
    exit 1
  fi

# ── ACTION: add-zone (добавить домен в Cloudflare) ───────────

elif [ "$ACTION" = "add-zone" ]; then
  DOMAIN="${3:?DOMAIN обязателен}"

  info "Добавляю домен $DOMAIN в Cloudflare..."

  # Проверяю — может уже есть
  CHECK=$(cf_api GET "/zones?name=$DOMAIN" || echo '{"success":false}')
  if echo "$CHECK" | grep -q "\"name\":\"$DOMAIN\""; then
    STATUS=$(echo "$CHECK" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    ZONE_ID=$(echo "$CHECK" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    log "Домен $DOMAIN уже в CF (status: $STATUS, zone_id: $ZONE_ID)"

    # Показываем NS серверы
    NS=$(echo "$CHECK" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ns = data['result'][0].get('name_servers', [])
print(', '.join(ns))
" 2>/dev/null)
    echo "NS серверы: $NS"
    echo "Zone ID: $ZONE_ID"
    exit 0
  fi

  # Создаём зону
  RESP=$(cf_api POST "/zones" "{\"name\":\"$DOMAIN\",\"jump_start\":true}" || echo "")

  if echo "$RESP" | grep -q '"success":true'; then
    ZONE_ID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    NS=$(echo "$RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ns = data['result'].get('name_servers', [])
print(', '.join(ns))
" 2>/dev/null)
    log "Домен $DOMAIN добавлен в Cloudflare"
    echo "Zone ID: $ZONE_ID"
    echo "NS серверы: $NS"
    echo ""
    echo "ВАЖНО: пропиши эти NS у регистратора домена!"
    echo "Привязка может занять от 15 мин до 24 часов."
  else
    err "Не удалось добавить домен: $RESP"
    exit 1
  fi

# ── ACTION: check-zone (проверить статус зоны) ───────────────

elif [ "$ACTION" = "check-zone" ]; then
  DOMAIN="${3:?DOMAIN обязателен}"

  info "Проверяю статус зоны $DOMAIN..."

  RESP=$(cf_api GET "/zones?name=$DOMAIN" || echo '{"success":false}')

  if echo "$RESP" | grep -q "\"name\":\"$DOMAIN\""; then
    echo "$RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
z = data['result'][0]
print(f'Домен: {z[\"name\"]}')
print(f'Статус: {z[\"status\"]}')
print(f'Zone ID: {z[\"id\"]}')
print(f'NS: {\", \".join(z.get(\"name_servers\", []))}')
print(f'Plan: {z.get(\"plan\", {}).get(\"name\", \"?\")}')
" 2>/dev/null
  else
    err "Домен $DOMAIN не найден в Cloudflare"
    exit 1
  fi

# ── Неизвестное действие ─────────────────────────────────────

else
  err "Неизвестное действие: $ACTION"
  echo "Доступные: create, delete, list, add-zone, check-zone"
  exit 1
fi

# Troubleshooting

## Caddy won't get SSL certificate
- DNS not resolving → `dig subdomain.domain.com`
- CF zone not active → `cloudflare-dns.sh check-zone`
- Port 80 blocked → `ss -tlnp | grep :80`
- Restart: `docker restart caddy && docker logs caddy --tail 20`

## Container won't start
- `docker logs CONTAINER --tail 30` → read the error
- `docker inspect CONTAINER --format '{{.State.ExitCode}}'` → check exit code:
  - 137 = OOM (out of memory) → `free -m`, remove unused services or upgrade tariff
  - 1 = application error → read logs for details
- Low RAM (< 200MB free) → `free -m` → stop unused: `cd /root/SERVICE && docker compose down`
- Low disk → `df -h /` → `docker system prune -af` (CAUTION: deletes unused images)
- Port conflict → `ss -tlnp | grep :PORT`
- Restart: `docker restart CONTAINER` or `cd /root/SERVICE && docker compose up -d`

## Disk full
1. `docker system df` → how much Docker uses
2. `docker system prune -af` → remove unused (ASK FIRST)
3. `du -sh /root/*` → what uses space
4. Check backup rotation: `ls -lh /root/backups/`

## RAM full
- `docker stats --no-stream` → who uses most
- Typical consumption: Supabase ~1.5 GB, n8n ~300 MB, LightRAG ~250 MB, Portainer ~20 MB, Caddy ~25 MB
- If swap 100%: `docker compose down` for unused service

## SSL certificate expiring
- Caddy auto-renews — normally no action needed
- If not renewed: `docker restart caddy && docker logs caddy --tail 20`

## n8n admin not created
- Password needs uppercase + number (script handles this)
- API not ready → wait 30s, retry via Docker IP

## Supabase issues
- `.env` variable missing → script warns and adds manually
- Low RAM (needs 2+ GB) → `free -m`
- PostgreSQL → `docker logs supabase-db --tail 20`

## Gitea shows 405
- INSTALL_LOCK = false → script sets true automatically
- Admin: `docker exec --user git gitea gitea admin user create --config /data/gitea/conf/app.ini ...`

## OpenClaw Gateway unreachable
- Port 18789 localhost only → need SSH tunnel
- Permission denied → `chown -R 1000:1000 /root/openclaw/data`

## Paperclip 403 Forbidden
- Normal — `PAPERCLIP_DEPLOYMENT_MODE=authenticated`
- Need invite: `docker exec paperclip pnpm paperclipai auth bootstrap-ceo --force`

## Backup PostgreSQL fails
- LightRAG: needs `PGPASSWORD=rag`
- Supabase: user from `.env` (`POSTGRES_USER`)
- Container not running → `docker ps | grep postgres`

## Backup not working
- PostgreSQL password mismatch → check script password vs `.env`
- Volume not found → `docker volume ls | grep SERVICE`
- Cron not running → `crontab -l` (should have `0 3 * * * bash /root/backup.sh`)

## DNS record not created
- CF token wrong permissions → need custom: Account Edit + Zone Read + DNS Edit
- Zone not found → `cloudflare-dns.sh check-zone`
- Record already exists → script auto-updates (not an error)

## Script failed midway
- Safe to re-run — all scripts are idempotent
- If container exists but broken → `docker logs CONTAINER`
- Clean restart: `cd /root/SERVICE && docker compose down -v && bash install-SERVICE.sh ...`

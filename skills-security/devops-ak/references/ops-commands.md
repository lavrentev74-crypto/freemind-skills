# Ops Commands

## "check server" / "status"

Run these commands via SSH:
```
uname -a && uptime
free -m
df -h /
nproc
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker ps -a --filter "status=exited" --format '{{.Names}} — {{.Status}}'
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
ufw status
```

## "backup"

```bash
backup.sh              # all services
backup.sh n8n          # specific service
```

Rotation: 2 copies. Restore:
```bash
restore.sh n8n              # latest backup
restore.sh n8n 20260412     # specific date
restore.sh all              # everything
```

Download to local: `scp root@IP:/root/backups/* ~/my-backups/`
Cron on server: `0 3 * * *` (daily 3:00 AM).
Explain to user: backups on server = protection from mistakes, AdminVPS weekly snapshots = protection from failure, download locally = full protection.

## "update"

```bash
update.sh              # all
update.sh n8n          # specific
```

Auto-detects: image pull vs git pull + rebuild. **Do NOT set up auto-updates** — new versions may break configs.

## "optimize" / "clean up"

1. `docker system prune -af` — **ASK CONFIRMATION FIRST** (caution: deletes unused images)
2. `journalctl --vacuum-size=50M`
3. If no swap and RAM < 4GB → create 2GB swap

## "fix [service]"

1. `docker ps -a` → find crashed containers
2. `docker logs CONTAINER --tail 30` → read error
3. Suggest fix: restart / recreate / config change
4. **ASK CONFIRMATION** before any action

## "set up SSH keys"

See `references/ssh-security.md`

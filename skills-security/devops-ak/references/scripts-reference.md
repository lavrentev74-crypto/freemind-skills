# Scripts Reference

All scripts in `devops-ak/scripts/`:

## Installation
| Script | Parameters | Purpose |
|--------|-----------|---------|
| `setup-server.sh` | — | Docker, UFW (22/80/443), dockeruser |
| `install-caddy.sh` | — | caddy-docker-proxy, `infra` network |
| `install-portainer.sh` | DOMAIN SUBDOMAIN [EMAIL] | Portainer CE + admin |
| `install-n8n.sh` | DOMAIN SUBDOMAIN EMAIL FIRST LAST | n8n + PostgreSQL + admin |
| `install-supabase.sh` | DOMAIN SUBDOMAIN [ORG] [PROJECT] [EMAIL] | Supabase (13 services) |
| `install-lightrag.sh` | DOMAIN SUBDOMAIN LLM_HOST LLM_KEY MODEL [EMBED_MODEL] [EMBED_HOST] [EMBED_KEY] [EMAIL] | LightRAG + PostgreSQL + MCP config |
| `install-gitea.sh` | DOMAIN SUBDOMAIN [EMAIL] | Gitea + PostgreSQL + admin |
| `install-openclaw.sh` | DOMAIN [TG_BOT_TOKEN] | OpenClaw **native** (Homebrew + systemd user-unit), Gateway 127.0.0.1:18789 — loopback only, публичного домена НЕТ |
| `install-paperclip.sh` | DOMAIN [SUBDOMAIN] | Paperclip **native** (pnpm build + systemd), HTTPS через Caddy |
| `install-claude-code.sh` | `<user>` [`--send-code CODE` \| `--tty` \| `--check`] | Claude Code CLI + OAuth по подписке (claude.ai) под `<user>`. Agent-режим без TTY: фаза 1 печатает `CC_AUTH_URL=`, фаза 2 `--send-code` шлёт код. Авто-обход first-run wizard и trust dialog |

## DNS & Domains
| Script | Usage |
|--------|-------|
| `cloudflare-dns.sh create` | CF_TOKEN ZONE_ID DOMAIN IP SUBDOMAIN |
| `cloudflare-dns.sh delete` | CF_TOKEN ZONE_ID DOMAIN SUBDOMAIN |
| `cloudflare-dns.sh list` | CF_TOKEN ZONE_ID |
| `cloudflare-dns.sh add-zone` | CF_TOKEN DOMAIN |
| `cloudflare-dns.sh check-zone` | CF_TOKEN DOMAIN |

Pointing the registrar's NS at Cloudflare is a **user action** (no script).
Walk the user through it — see `cloudflare-setup.md`.

## Monitoring
| Script | Parameters |
|--------|-----------|
| `setup-upptime.sh` | DOMAIN TG_BOT_TOKEN TG_CHAT_ID [REPO_NAME] [--private] |

## Maintenance
| Script | Parameters |
|--------|-----------|
| `backup.sh` | [SERVICE] [MAX_COPIES=2] |
| `restore.sh` | SERVICE [DATE] |
| `update.sh` | [SERVICE ...] |

## Reporting
| Script | Parameters |
|--------|-----------|
| `generate-report.py` | `data.json [output.pdf]` — генерация PDF-отчёта заказчику (см. `references/report-template.md`) |

## Common Properties
- Idempotent (safe to re-run)
- Generate credentials via `openssl rand`
- Write JSON reports to `/root/logs/`
- Exit code 0 = success

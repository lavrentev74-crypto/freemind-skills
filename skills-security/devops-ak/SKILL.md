---
name: devops-ak
description: "Full-cycle server and infrastructure management. Deploy, monitor, backup, update any software on VPS servers. EN triggers: server, deploy, install, VPS, Docker, domain, DNS, SSL, backup, restore, update, monitor, SSH, Cloudflare, hosting, container, reverse proxy, Caddy, n8n, Supabase, LightRAG, Gitea, OpenClaw, Paperclip, Portainer, GitHub deploy, devops, infrastructure. RU triggers: сервер, поставь, подними, установи, задеплой, разверни, запусти на сервере, настрой сервер, какой сервер взять, какой сервер выбрать, купить сервер, купить VPS, арендовать сервер, выбрать тариф, выбрать хостинг, AdminVPS, проверь сервер, что с сервером, статус сервера, бэкап, сделай бэкап, восстанови, обнови, обнови контейнеры, домен, привяжи домен, купить домен, DNS, Cloudflare, SSL, сертификат, SSH, SSH ключи, как подключиться к серверу, подключиться по SSH, порты, файрвол, UFW, безопасность сервера, мониторинг, Docker, контейнер, nginx, Caddy, деплой, деплой проекта, поставь с GitHub, развернуть проект, поднять сайт, запустить приложение, n8n, Supabase, LightRAG, Gitea, OpenClaw, Paperclip, Portainer, HetrixTools."
---

# devops-ak — Full-Cycle Server Management

Respond in the user's language.

## Route by request type

1. **Deploy / install** → Deploy Workflow below
2. **Server status / check** → `references/ops-commands.md`
3. **Backup / restore** → `references/ops-commands.md`
4. **Update services** → `references/ops-commands.md`
5. **Fix / troubleshoot** → `references/troubleshooting.md`
6. **VPS purchase / SSH / domain** → `references/vps-guide.md`
7. **Cloudflare setup** → `references/cloudflare-setup.md`
8. **SSH keys** → `references/ssh-security.md`
9. **GitHub project deploy** → `references/github-deploy.md`
10. **Claude Code standalone install** → `scripts/install-claude-code.sh <user>`
11. **Existing server with software** → scan → show to user → ask how to proceed. NEVER delete without confirmation.

## Deploy Workflow

**CRITICAL: Use TodoWrite to track ALL phases.** Create a todo list with all 6 phases before starting. Mark `in_progress` when starting, `completed` when done. Applies to partial installs too (adding one service) — create todos for relevant phases only.

### Phase 1: Collect Data
Step-by-step, one question at a time — `references/onboarding-guide.md`.

### Phase 2: Verify
1. SSH: `whoami && uname -a` — must work.
2. CF token: verify endpoint → success.
3. Domain zone active? If not → `cloudflare-dns.sh add-zone` → give NS → 3 options (tell me when done / scheduled recheck every 10 min / user checks himself). **Do NOT install until the zone is active** — Caddy needs DNS for SSL.
4. Resources: `free -m`, `df -h`, `nproc` — warn if low.

### Phase 3: Confirm
Show plan → ask "Correct? Starting?".

### Phase 4: Install — fixed order

1. `setup-server.sh` → Docker, UFW, users.
2. `install-caddy.sh` → reverse proxy + `infra` network.
3. `cloudflare-dns.sh create` → A-records for public subdomains (NO `oc` — OpenClaw is loopback-only).
4. Docker services (any order): portainer, n8n, supabase, gitea.
5. OpenClaw (BEFORE Paperclip — Paperclip runs as `openclaw`).
6. Paperclip.
7. **Interactive stops — WAIT for user.** All four (OpenClaw onboard, TG pairing, Claude Code OAuth under `openclaw`, Paperclip CEO signup) — commands + rules in `references/post-install.md`. Claude Code OAuth is a hard prerequisite for LightRAG MCP wiring.
8. LightRAG (LAST). Before running `install-lightrag.sh`, **read `references/lightrag-connect-agents.md`** — it has the upload + wiring procedure. The script fails fast if canonical refs aren't at `/root/lightrag-ref/`.
9. `setup-upptime.sh` — optional monitoring (see `references/post-install.md`).

Scripts parameters: `references/scripts-reference.md`.

### Phase 5: Verify
1. `docker ps` — all running.
2. Check each service URL:
   - LightRAG: `curl -sI https://lrag.DOMAIN/webui/#/login` (root returns 405; login page is the correct check).
   - Others: `curl -sI https://SUBDOMAIN.DOMAIN` → HTTP 200/301/302.
3. `ufw status` — only 22, 80, 443.

### Phase 6: Report + local LightRAG wiring

Two parts. Do NOT skip Part B — it's the only step that touches the user's local machine.

**Part A — server report (on the skill host):**

Output location: create a folder named after the server IP inside cwd (e.g. `./89.125.51.217/`) and put ALL artifacts there. Never dump into bare cwd, never invent names like `test-workspace/`. Reuse the folder on re-runs.

1. `mkdir -p <SERVER_IP>/ && cd <SERVER_IP>/`.
2. Collect real data from server (SSH) — `references/report-template.md`.
3. Build `data.json`, run `python3 <skill-path>/scripts/generate-report.py data.json server-report-<slug>.pdf`.
4. Tell user the full path in the final summary.
5. Save `server-config.json` in the same folder (`chmod 600`, add to `.gitignore`).

**Part B — LightRAG MCP on the user's LOCAL machine** (REQUIRED if LightRAG was installed):
Follow the canonical procedure in `references/lightrag-connect-agents.md` — it covers Claude Code CLI + Claude Desktop, OS-specific paths, the append-don't-overwrite rule.

**Hard rules (no improvisation):**
- Keep Claude Code / Claude Desktop / OpenClaw **separate** — don't cross-wire.
- MCP key is always `lightrag` (canon). No `lightrag-<slug>` variants.
- **Never overwrite** an existing `mcpServers.lightrag` or an existing LightRAG block in `~/.claude/CLAUDE.md` — stop and ask the user.
- **Read fresh** every time — URL + API key come from THIS server's `/root/logs/lightrag-report.json`, never from memory or another server.
- Canonical instruction blocks live ONLY in `references/lightrag-AGENTS.md` and `references/lightrag-CLAUDE.md`. Never paste alternative wording.

**Final summary must confirm three artifacts**: PDF path, Claude Desktop updated, Claude Code CLI updated.

## Rules (ALWAYS follow)
- NEVER delete data without user confirmation.
- Suggest backup BEFORE updates.
- Do NOT restart services during backup.
- SSH keys are OPTIONAL — do not push on the user.

## Security
- UFW: only 22, 80, 443 (+ 222 if Gitea SSH).
- Service ports NEVER exposed externally (only through Caddy).
- Credentials: `openssl rand -hex 16` minimum, store in `.env`.
- Compose: `restart: unless-stopped`, healthcheck on every service.
- `server-config.json`: `chmod 600`, add to `.gitignore`.

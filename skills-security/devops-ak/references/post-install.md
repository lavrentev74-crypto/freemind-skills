# Post-Installation Steps

Agent-facing doc. Commands are as-is; quoted blocks marked `> К юзеру:` are what you say to the user in Russian.

---

## SSH client — always recommend Termius

Beginners get lost with SSH. Before any manual command on the server, tell the user:

> К юзеру: **Скачай [Termius](https://www.termius.com/)** — бесплатного аккаунта
> достаточно. Есть под Windows / macOS / Linux / iOS / Android. Создай хост
> из IP + root + пароль (из отчёта / credentials) — будешь подключаться
> в одно касание. Termius ещё умеет встроенный SFTP (удобно заливать файлы)
> и Port Forwarding (понадобится для OpenClaw Gateway UI — см. ниже).

The Termius hint is auto-rendered in the final PDF inside the «SSH-доступ
к серверу» section, so no extra PDF work required.

---

## System user `openclaw` — critical note

After native installs a **second Linux user `openclaw`** appears on the box. It hosts:
- OpenClaw (systemd **user**-unit + lingering)
- Paperclip (systemd **system**-unit, but process runs as openclaw)
- Shared Node.js / Homebrew / pnpm

**How to jump from root to openclaw:** `sudo -iu openclaw`

Always mention this to the user — every post-install command for OpenClaw /
Paperclip runs **as openclaw**, not as root.

---

## OpenClaw — native (post-install)

### 1. Connect an LLM provider (mandatory, first user action)

The installer already wrote TG token and started gateway. The remaining bit is
letting OpenClaw reach an LLM.

Tell the user (Termius commands):
```bash
ssh root@<IP>                                  # connect
sudo -iu openclaw                              # switch user
openclaw onboard --flow quickstart             # interactive wizard
```

Wizard choices:
- **Claude Pro/Max** — OAuth via `claude.ai` (paid Claude.ai subscription)
- **Anthropic API** — paste `sk-ant-...`
- **OpenAI** — paste `sk-...`
- **OpenRouter** — paste `sk-or-...`
- **Polza.ai / custom** — host + key

Wizard writes config and restarts gateway on its own.

Non-interactive alternative:
```bash
openclaw auth set anthropic sk-ant-XXX
openclaw gateway restart
```

### 2. Telegram pairing (mandatory)

**Agent runs `approve` itself — user only sends `/start` and pastes the code.** Do NOT tell the user to SSH in and run `openclaw pairing approve` by hand.

Script:
1. Tell user: «Открой Telegram → найди бота **@<tg_bot_username>** → отправь `/start`. Бот пришлёт код. Скинь мне код.»
2. User pastes the code (typically 6–8 chars like `TU8HUDQ8`).
3. Agent runs on server:
   ```bash
   sudo -iu openclaw openclaw pairing approve telegram <CODE>
   sudo -iu openclaw openclaw pairing list   # expect: "No pending telegram pairing requests"
   ```
4. Confirm "Привязка сделана" — move on.

Never ask the user to run the approve command themselves. Never auto-poll / auto-approve without the user-supplied code — the code is the user's consent.

### 3. Gateway UI access (optional)

Gateway binds `127.0.0.1:18789` only — not exposed (holds tokens, don't
publish). To reach the UI from a browser:

**Option A (Termius):** Port Forwarding → local `18789` → remote `127.0.0.1:18789`.
**Option B (terminal):** `ssh -N -L 18789:127.0.0.1:18789 root@<IP>`

Then open `http://localhost:18789` in a browser. Token: `sudo -iu openclaw openclaw gateway token`.

### 4. Do NOT try to automate interactive steps

`openclaw onboard` and the first-run `claude` wizard both need a real TTY.
Wrappers via `expect` / PTY break in subtle ways. Just instruct the user.

---

## Paperclip — native (post-install)

### 1. Claude Code auth (required, needs Claude Pro/Max)

Paperclip uses the Claude Code CLI as `openclaw`. Auth via `install-claude-code.sh` — two phases, no TTY needed.

```bash
# Phase 1: install + start OAuth, get URL
ssh root@<IP> '/root/install-claude-code.sh openclaw'
# Prints CC_AUTH_URL=https://... — pass that URL to the user.
```

> К юзеру: Открой ссылку в браузере, залогинься своим Claude Pro/Max
> аккаунтом, скопируй код с финальной страницы и пришли мне.

```bash
# Phase 2: send code, verify, write report, restart Paperclip
ssh root@<IP> '/root/install-claude-code.sh openclaw --send-code <CODE>'
sudo systemctl restart paperclip
```

Идемпотентный: если `openclaw` уже залогинен — фаза 1 пропускает OAuth и сразу пишет `already_authed`. Также пред-заполняет first-run wizard и trust dialog — `claude` стартует без интерактива.

**API-key alternative (no subscription):** манульно `sudo -iu openclaw claude auth login --console`, вставить ключ из https://console.anthropic.com/settings/keys.

**Verify:** `sudo -iu openclaw claude auth status --json` → `"loggedIn": true`, `"authMethod": "claude.ai"` (или `"console"`).

### 2. CEO account via bootstrap-ceo (auto)

`install-paperclip.sh` runs `pnpm paperclipai auth bootstrap-ceo --force` as
its final step and writes the invite URL to
`/root/logs/paperclip-report.json` (`invite_url`) and installer stdout. The
skill MUST:

1. Hand that URL to the user and wait for confirmation ("registered").
2. Only AFTER confirmation — run the `disableSignUp` step below
   automatically. Do not leave it to the user.

`install-paperclip.sh` also sets `auth.baseUrlMode=explicit` +
`auth.publicBaseUrl=https://FQDN`. If CEO bootstrap still returns
`localhost` — the script rewrites the host to FQDN before handing the URL
to the skill.

Manual re-generate:
```bash
sudo -iu openclaw bash -lc 'cd /home/openclaw/paperclip && pnpm paperclipai auth bootstrap-ceo --force'
```

### 3. Close public signup (skill runs this automatically)

Run as soon as the user confirms they've registered CEO:
```bash
sudo -iu openclaw python3 -c "
import json
p='/home/openclaw/.paperclip/instances/default/config.json'
d=json.load(open(p))
d['auth']['disableSignUp']=True
json.dump(d, open(p,'w'), indent=2)
"
sudo systemctl restart paperclip
```

### 4. Pair OpenClaw ↔ Paperclip via invite snippet

Paperclip doesn't need manual URL/token plumbing. Flow:

1. User opens Paperclip → **Settings → Invites**
2. Click **Generate an OpenClaw agent invite snippet**
3. Copy the snippet
4. Send it to the OpenClaw agent (via chat or as a task)
5. Agent self-registers in Paperclip

If the agent hits `pairing required. Approve the pending device in OpenClaw
(openclaw_gateway_pairing_required)` — Paperclip connected to the OpenClaw
gateway but the device isn't approved yet. Tell user: reply to the agent
in Telegram, it sees the pending pairing and can approve, then click
**Retry** on the failed task in Paperclip.

Smoke test: ask the Telegram agent to assign a task to CEO in Paperclip,
and let CEO assign one back. Round-trip success means the pair works.

### 5. Workdir for agent commands (no-approval mode)

Without a workdir the CEO agent asks for approval on every command. Setup:

1. User runs `mkdir ~/paperclip_projects` (as openclaw).
2. Paperclip UI → **Projects** → New Project → path:
   `/home/openclaw/paperclip_projects`
3. Agent → Configuration → **Project** field → pick the project.

`~/.claude/settings.json` with a `permissions` block does NOT work for
Paperclip agents — Paperclip spawns `claude` via `spawn()` bypassing
interactive permissions.

### 6. Optional: separate TG bot for Paperclip

By user's choice — create a separate bot via **@BotFather**, put the token
into Paperclip config via UI (Settings → Telegram). Skip if user is happy
sharing OpenClaw's bot.

---

## LightRAG — post-install

**Canonical source:** `references/lightrag-connect-agents.md` (verbatim
copy of the LightRAG project's docs). When in doubt, read that file — do
not invent alternative wording. The AGENTS.md and CLAUDE.md blocks this
skill appends must match `references/lightrag-AGENTS.md` and
`references/lightrag-CLAUDE.md` character-for-character (incl. the
"LightRAG Auto-Capture" section).

**Core rules (same on every server, never hardcode values):**
- Read URL (`https://lrag.<DOMAIN>`) and API key from the CURRENT server's
  `/root/logs/lightrag-report.json` — never from memory or another server.
- MCP server key is always `lightrag`. If an entry with that key already
  exists in any target config, STOP and ask the user.
- All instruction blocks (AGENTS.md, CLAUDE.md) are APPENDED. If a
  "LightRAG Knowledge Base" marker already exists in the target file,
  skip — don't duplicate.

MCP must be wired in FOUR places. Paperclip inherits from Claude Code on
the server — do NOT configure Paperclip separately.

**On the server (done by `install-lightrag.sh`):**

1. **OpenClaw (native)** —
   `sudo -iu openclaw openclaw mcp set lightrag '<JSON>'` and append the
   AGENTS.md block (see install-lightrag.sh) into
   `/home/openclaw/.openclaw/workspace/AGENTS.md`. Script then runs
   `systemctl --user restart openclaw-gateway`.

2. **Claude Code CLI as openclaw (server-side — Paperclip reads from here)** —
   requires `~/.claude.json` for openclaw, i.e. user must have completed
   Claude Code OAuth already (Phase 4 interactive stop). If missing, the
   script skips silently. Command form:
   ```bash
   sudo -iu openclaw bash -lc "claude mcp remove --scope user lightrag 2>/dev/null; \
     claude mcp add-json --scope user lightrag '<JSON>'"
   ```

**On the user's LOCAL machine (Phase 6 Part B — manual):**

3. **Claude Desktop** — edit config (paths per OS):
   - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Windows: `%APPDATA%\Claude\claude_desktop_config.json`
   - Linux: `~/.config/Claude/claude_desktop_config.json`

   Add the server under key `mcpServers.lightrag`. If the `lightrag` key is
   already occupied by another server (user may have their own prod
   LightRAG) — STOP and ask the user. Do NOT overwrite and do NOT invent
   slug variants. Fully quit Claude Desktop and reopen to reload MCP.

4. **Claude Code CLI (local terminal)** — `claude mcp add-json --scope user lightrag '<JSON>'`
   with the same key as step 3.

**Canonical JSON payload** (use the same shape for all four steps):
```json
{
  "command": "npx",
  "args": ["-y", "@g99/lightrag-mcp-server"],
  "env": {
    "LIGHTRAG_SERVER_URL": "https://lrag.DOMAIN",
    "LIGHTRAG_API_KEY": "<API_KEY>"
  }
}
```

**Command templates** (copy-paste for manual/fallback):

Server — OpenClaw:
```bash
sudo -iu openclaw openclaw mcp set lightrag '<JSON>'
sudo -iu openclaw systemctl --user restart openclaw-gateway
```

Server — Claude Code (as openclaw):
```bash
sudo -iu openclaw bash -lc "claude mcp remove --scope user lightrag 2>/dev/null; \
  claude mcp add-json --scope user lightrag '<JSON>'"
```

Local — Claude Code CLI:
```bash
claude mcp remove --scope user lightrag 2>/dev/null
claude mcp add-json --scope user lightrag '<JSON>'
```

**Verification:**
- `openclaw mcp list` — contains `lightrag`.
- `claude mcp list` (both server-as-openclaw and user's local) — shows
  `lightrag: ... ✓ Connected`.
- In Claude Desktop — 🔧 icon in chat lists the server.

**Smoke test:** in OpenClaw or Claude Code — "запомни Hello World" then
"вспомни Hello" should return the saved text.

---

## Upptime Monitoring (GitHub Actions — free forever, external)

Ask the user: «Ставим мониторинг? Бесплатный навсегда, алерты в Telegram,
проверки идут с инфры GitHub — даже если VPS упадёт, алерты всё равно сработают.»

Collect three things from the user, one at a time (beginners find lists
overwhelming):

### 1. GitHub CLI auth on the VPS

- Run on server: `gh auth login --hostname github.com --web --scopes "repo,workflow,admin:public_key,delete_repo"`
- `gh` prints `First copy your one-time code: XXXX-YYYY`
- Show the code to user and say:
  > К юзеру: «Открой https://github.com/login/device, введи `XXXX-YYYY`,
  > залогинься, жми Authorize → Continue. Когда закончишь — скажи "готово".»
- After «готово» → `gh auth status` must show `Logged in to github.com`.
  If not — code expired (15 min TTL), rerun `gh auth login`.

### 2. Telegram bot via @BotFather

Ask the user to:
- Open Telegram → **@BotFather** → `/newbot`
- Pick a name ending in `_bot` (e.g. `acme_uptime_bot`)
- Copy the token (`123456:AAH...`) and send to you
- **CRITICAL:** find their new bot in Telegram search by name and send it
  `/start`. Otherwise it can't message the user (`chat not found` error).

Verify: `curl -s "https://api.telegram.org/bot<TOKEN>/getMe"` must return `"ok":true`.

### 3. Telegram chat_id via @userinfobot

Ask user to:
- Open Telegram → **@userinfobot** → `/start`
- Bot answers with `Id: <number>` — send that number to you.

Verify the bot from step 2 can actually message user:
```bash
curl -s "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" -d "text=test from setup-upptime"
```
If `"ok":true` — fine. If `"Forbidden: bot can't initiate conversation"` —
user forgot `/start` in step 2 last bullet. Fix and retry.

### 4. Run the installer

```bash
setup-upptime.sh DOMAIN TG_BOT_TOKEN TG_CHAT_ID
```
Script:
- verifies `gh auth status` and both TG tokens
- creates a repo from template `upptime/upptime`
- writes secrets (`GH_PAT`, `NOTIFICATION_TELEGRAM_BOT_TOKEN`, `NOTIFICATION_TELEGRAM_CHAT_ID`)
- auto-detects subdomains from `/root/*/compose.yaml` + `/root/caddy/extra.caddyfile` → `.upptimerc.yml`
- pushes → Actions start firing on `*/15` cron

### 5. Verify

- ~2 min later: `https://<user>.github.io/<repo>/` → status page
- Take one domain offline on purpose → TG alert in 15-30 min
- Issues auto-open in the repo on outages

### Cron cadence & GitHub Actions limits (MUST tell the user)

Default: **private repo + cron `*/15`** (fits into 2000 min/mo free tier
for private repos).

If user wants **more frequent (every 5 min)**:
- **Option A — GitHub Pro ($4/mo)** — 3000 min/mo for private repos.
- **Option B — make repo public** — Actions for public repos are
  unlimited. Risks: URL list visible, downtime history visible. Secrets
  still live in encrypted Secrets.

Switch to public:
```bash
gh repo edit <user>/<repo> --visibility public --accept-visibility-change-consequences
```
Then change cron to `*/5` in `.upptimerc.yml`, commit + push.

---

## CLI reference

OpenClaw — official docs: https://docs.openclaw.ai/cli. The skill has no
built-in cheatsheet (the old 1077-line copy was removed). If needed, fetch
via WebFetch on demand.

Paperclip — install/commands: see `scripts/install-paperclip.sh` header and
the post-install block for Paperclip above.

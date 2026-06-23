# PDF Report — contract + generation

One JSON-file → PDF via `scripts/generate-report.py`. No magic, no hardcoded
logic per service: whatever is in JSON is what lands in the PDF. Only
`date`, `domain`, `server_ip` are required; everything else is optional
(missing → not rendered).

## Run

```bash
pip3 install reportlab   # once
python3 scripts/generate-report.py data.json server-report-<slug>.pdf
```

`<slug>` — first label of the domain (`acme` for `acme.com`). Save the PDF
into the cwd the user launched the agent from; name it
`server-report-<slug>.pdf`.

## JSON schema

```jsonc
{
  // ── REQUIRED ────────────────────────────────────────────────
  "date": "DD.MM.YYYY",
  "domain": "example.com",
  "server_ip": "1.2.3.4",

  // ── optional meta ──────────────────────────────────────────
  "email": "admin@example.com",
  "ssh_port": "22",

  // ── «Конфигурация сервера» ─────────────────────────────────
  // Canonical keys (os / cpu / ram / disk / docker_version /
  // docker_compose_version) translated to Russian headers automatically.
  // Other keys are rendered as-is.
  "server_info": {
    "os": "Ubuntu 22.04.5 LTS",
    "cpu": "4 vCPU",
    "ram": "8 GB",
    "disk": "60 GB",
    "docker_version": "29.4.0",
    "docker_compose_version": "v5.1.3"
  },

  // ── SSH users ──────────────────────────────────────────────
  // Any count. Order preserved, «1., 2., …» numbering automatic.
  "ssh_users": [
    {
      "title": "root — полный доступ к серверу",
      "user": "root",
      "password": "..."
    },
    {
      "title": "openclaw — под ним работают OpenClaw и Paperclip",
      "user": "openclaw",
      "password": "...",
      "ip": "1.2.3.4",   // optional, defaults to server_ip
      "port": "22"       // optional, defaults to ssh_port
    }
  ],

  // ── Services ───────────────────────────────────────────────
  // Rendered verbatim:
  //  - No url/login/password/extra → title + description only (no table).
  //  - url/login/password → separate rows.
  //  - extra{} — any extra fields, order preserved.
  //  - note — italic paragraph under the table.
  //  - All http(s):// in values auto-linkify.
  "services": {
    "caddy": {
      "label": "Caddy",
      "description": "Reverse-proxy с автоматическим HTTPS (Let's Encrypt)...",
      "note": "Отдельного URL нет — Caddy работает под всеми субдоменами."
    },
    "openclaw": {
      "label": "OpenClaw",
      "description": "Автономный AI-агент, работает на сервере — сам планирует, пишет код, запускает задачи...",
      "extra": {
        "Gateway token": "<TOKEN>",
        "SSH tunnel": "ssh -N -L 18789:127.0.0.1:18789 openclaw@IP",
        "Пароль openclaw (для SSH tunnel)": "<ACTUAL_OPENCLAW_PASSWORD>",
        "Dashboard (после туннеля)": "http://localhost:18789/#token=<SAME TOKEN>",
        "Telegram-бот": "@bot_name"
      },
      "note": "Как открыть Dashboard: скопируй SSH tunnel из таблицы → вставь в терминал → при запросе пароля вставь значение поля «Пароль openclaw» (из строки выше). Пока туннель открыт — работает ссылка Dashboard."
    },
    "paperclip": {
      "label": "Paperclip AI",
      "description": "Платформа для создания автономных AI-компаний — команды агентов с ролями, задачами и общим контекстом.",
      "url": "https://pc.example.com",
      "note": "Публичная регистрация закрыта. CEO-аккаунт создан при установке."
    },
    "supabase": {
      "label": "Supabase",
      "description": "Self-hosted backend: PostgreSQL + Auth + Storage + Realtime + REST API.",
      "url": "https://sb.example.com",
      "login": "admin_sup",
      "password": "...",
      "extra": {
        "Postgres password": "...",
        "anon key": "eyJhbGciOi...",          // ALWAYS include both JWTs —
        "service_role key": "eyJhbGciOi..."   // needed by FE and BE
      }
    }
  },

  // ── Optional sections ──────────────────────────────────────

  // Security. Default adds port 222 if gitea is present.
  "security_items": ["Файрвол UFW: открыты только порты 22, 80, 443", "..."],

  // Backups — three prompts for the user's Claude agent. If omitted,
  // a default set ships (nightly cron, download to laptop, restore check).
  // IP and domain-slug are substituted automatically into default prompts.
  "backup_prompts": [
    {
      "title": "1. Чтобы бэкапы делались сами каждую ночь",
      "why":   "Защита от «случайно удалил что-то важное».",
      "prompt": "/devops-ak настрой ..."
    }
  ]
}
```

## Rules for the agent filling the JSON

1. **No hardcoding.** Every value comes from `/root/logs/*-report.json`,
   `server-config.json`, or something you personally generated during
   install. Never invent passwords / tokens / keys. Never copy from the
   schema example above.

2. **OpenClaw block — password lives in `extra`, not as `password` field.** The openclaw system password is ALSO in `ssh_users`, but duplicate it into the service `extra` block so the user doesn't have to hunt across sections when opening the Dashboard. Inside the service block:
   - `extra` — Gateway token (from `/home/openclaw/.openclaw/openclaw.json` field `gateway.auth.token`), SSH tunnel, **«Пароль openclaw (для SSH tunnel)»** (the actual openclaw user password), Dashboard URL with token inlined, Telegram-бот.
   - `note` — Russian instructions: «скопируй SSH tunnel → вставь в терминал → введи пароль из поля «Пароль openclaw» в таблице выше». Refer the user to the field, don't inline the password in prose (it's redundant with the table row).
   - Do NOT use the top-level `login` / `password` fields for OpenClaw — it doesn't have a login/password service UI. The table shows a numbered extra block only.

3. **Caddy** — only `label`, `description`, `note`. No URL, no table.
   Caddy works as invisible infrastructure.

4. **Paperclip** — `url`, `description`, `note`. No `login`/`password`
   (CEO is created by the user via invite URL during install; the skill
   never sees those credentials).

5. **Supabase** — ALWAYS include `anon key` + `service_role key` + `Postgres
   password` in `extra` (all three from `supabase-report.json`).

6. **Descriptions** (`description`) — 1-2 sentences in plain Russian for a
   non-technical reader. Explain **why** this service exists, not what's
   inside. Bad: «PostgreSQL + Auth + Storage + Realtime». Good: «Готовый
   backend с базой, авторизацией и API — используй когда нужно быстро
   запустить приложение без сервера».

7. **OpenClaw Dashboard URL** — in
   `extra["Dashboard (после туннеля)"]` inline the token directly into the
   URL (`http://localhost:18789/#token=<TOKEN>`, not `<placeholder>`), so
   the user can copy-paste from the PDF and open it after the tunnel.

## Mapping from install reports to JSON fields

Each `install-*.sh` writes `/root/logs/<service>-report.json`. Final
`data.json` mapping:

| PDF field | Source |
|---|---|
| `server_ip`, `domain`, `email`, `ssh_port` | install args / `server-config.json` |
| `server_info.os` | `lsb_release -ds` or `/etc/os-release` PRETTY_NAME |
| `server_info.cpu` | `nproc` |
| `server_info.ram` | `free -m` |
| `server_info.disk` | `df -h /` |
| `server_info.docker_version` | `setup-server-report.json` → `docker_version` |
| `server_info.docker_compose_version` | `setup-server-report.json` → `compose_version` |
| `ssh_users[0]` (root) | original password given by user |
| `ssh_users[1]` (openclaw) | `setup-server-report.json` → `dockeruser_password` OR `openclaw-report.json` → `password` |
| `services.openclaw.extra["Gateway token"]` | `/home/openclaw/.openclaw/openclaw.json` → `gateway.auth.token` |
| `services.openclaw.extra["Telegram-бот"]` | `openclaw-report.json` → `tg_bot_username` |
| `services.paperclip.url` | `paperclip-report.json` → `url` |
| `services.lightrag.*` | `lightrag-report.json` → `url` / `admin_login` / `admin_password` / `api_key` |
| `services.gitea.*` | `gitea-report.json` → `url` / `admin_user` / `admin_password` |
| `services.n8n.*` | `n8n-report.json` → `url` / `email` / `password` |
| `services.portainer.*` | `portainer-report.json` → `url` / `login` / `password` |
| `services.supabase.*` | `supabase-report.json` → `url` / `dashboard_user` / `dashboard_password` / `postgres_password` / `anon_key` / `service_role_key` |
| `services.<custom>` | arbitrary — e.g. a project deployed from GitHub → `url`, optional description/note |

## What is **not** rendered anymore

Intentionally removed on user feedback:
- «Проверка работоспособности» — `build_health` function deleted.
- «DNS-записи в Cloudflare» — `build_dns` function deleted.
- «Настроенные сервисы и их обновление», «Массовое обновление» — update
  commands go stale fast; live versions stay in `update.sh`.
- Page headers and footers.

If you need any of this back — check `git log -- scripts/generate-report.py`.

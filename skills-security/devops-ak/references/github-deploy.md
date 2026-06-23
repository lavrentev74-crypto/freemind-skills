# Deploy Any Project From GitHub

The skill does NOT ship a per-framework deploy script. Instead the agent
inspects the repo and performs the generic steps below. Goal: drop-in any
public/private GitHub repo onto the same VPS, wire it through Caddy on a
new subdomain, without writing a dedicated shell script per framework.

## Decision order: Dockerfile → Buildpack-style per-stack

1. **If repo already has a `Dockerfile` / `Containerfile`** — use it as-is.
   This is the default and the preferred path. Do NOT regenerate.
2. **If repo has `docker-compose.yml` / `compose.yaml`** — inspect services
   and reuse. Likely you only need to add Caddy labels + join the `infra`
   network.
3. **Only if neither exists** — generate a Dockerfile based on detected
   stack (see mapping below).

## Stack detection

Read these files from repo root (via `git clone --depth 1` into
`/root/deploys/<slug>/` first):

| Signal | Stack |
|---|---|
| `next.config.*` + `package.json`    | Next.js |
| `package.json` (scripts.build) without next | Node.js (Express, Fastify, Nest, SvelteKit, Nuxt, Remix, Vite) |
| `requirements.txt` / `pyproject.toml` | Python (FastAPI / Django / Flask) |
| `go.mod`          | Go |
| `Cargo.toml`      | Rust |
| `pom.xml` / `build.gradle*` | Java |
| `composer.json`   | PHP |
| static `index.html` no build | nginx static |

Pick image base: `node:<lts>-bookworm-slim`, `python:3.12-slim`,
`golang:1.23-alpine` + `alpine` for runtime, `rust:slim` + `debian:slim`,
etc. Prefer multi-stage: separate `builder` and `runner` layers. Non-root
user in runner. `.dockerignore` with `node_modules`, `.git`, `.env*`.

## Stack-specific gotchas

**Next.js** — needs `output: 'standalone'` in `next.config.*`. Formats vary:
- `const nextConfig = {}` → add `output: 'standalone'` inside.
- `withBundleAnalyzer({...})` / `withPWA(...)` → add inside the inner config.
- `output: process.env.BUILD_STANDALONE` → pass `ENV BUILD_STANDALONE=true`
  in Dockerfile.
- Always `cat` the existing config before modifying — don't overwrite
  unrelated options.
- `COPY public ./public` — only if that dir exists.
- Foreign repos often have desynced `package-lock.json` — use
  `npm install` not `npm ci`.
- `ENV NEXT_TELEMETRY_DISABLED=1`.
- Transitive dep trap: `recharts` imports `react-is` without declaring it.
  If you see `Module not found: Can't resolve 'react-is'` in build output,
  `npm install react-is --save` (or pnpm/yarn equivalent) and rebuild.

**Node.js generic** — respect `engines.node` from package.json. Use
corepack so the right package manager version gets pulled (`corepack enable`).

**Python** — use `uv` or `pip install --no-cache-dir -r requirements.txt`.
For FastAPI/ASGI expose `uvicorn app:app --host 0.0.0.0 --port 8000`. For
Django add `gunicorn wsgi:application`.

**Static sites** — use `nginx:alpine`, copy `dist/` or `build/` into
`/usr/share/nginx/html`.

## Caddy integration (always the same)

Give the container these labels so `caddy-docker-proxy` auto-generates a
virtual host:
```yaml
labels:
  caddy: ${FQDN}
  caddy.reverse_proxy: "{{upstreams <port>}}"
```
and put it on the external network:
```yaml
networks:
  - infra
networks:
  infra:
    external: true
```
`<port>` is whatever the app binds inside its container. Port is NOT
published to host — Caddy joins the network and proxies by container DNS.

## Subdomain + DNS

Pick a subdomain — either user suggests, or derive from repo name
(`awesome-app` → `app`, `admin-dashboard` → `dash`). Then:
```bash
cloudflare-dns.sh create "$CF_TOKEN" "$ZONE_ID" "$DOMAIN" "$SERVER_IP" "$SUBDOMAIN"
```
After A-record exists, first HTTPS request triggers Let's Encrypt issuance
via Caddy (30-90 seconds).

## ENV variables

Read `.env.example` / `.env.sample`. Two buckets:
- **In-repo secrets** (JWT_SECRET, SESSION_KEY) — generate via
  `openssl rand -hex 32` and put into a new `.env` in the deploy dir.
- **External service keys** (Clerk, Sentry, Stripe, Supabase, OpenAI) —
  the skill does NOT invent these. Ask user:
  > К юзеру: проект использует `<SERVICE>` — нужен ключ. Где брать:
  > `<link to service dashboard>`. Пришли сюда.

Never commit `.env` to any repo. Put it in the deploy dir, reference it
from compose via `env_file: .env`.

## Post-deploy verification

```bash
docker compose up -d
docker ps --filter name=<slug>-app
curl -skI https://<subdomain>.<domain>/ | head -3
```
Expect 200 / 301 / 302 / 307. If 502 — container not ready yet or binding
wrong port. If 500 — likely missing ENV, check `docker logs <slug>-app`.

## Update flow (once deployed)

```bash
cd /root/deploys/<slug>
git pull
docker compose build
docker compose up -d
```
Record this in the PDF report under the service's `note`.

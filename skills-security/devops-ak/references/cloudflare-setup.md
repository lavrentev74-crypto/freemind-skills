# Cloudflare Setup

Used by agent to guide the user through Cloudflare onboarding + collecting
API token / Zone ID. User does everything in the browser; skill just
instructs.

## 1. Register

Send user:
> К юзеру: Зайди на https://cloudflare.com → Sign Up (free). Подтверди email.

## 2. Add domain

> К юзеру: В Cloudflare нажми **Add a site** → введи свой домен → выбери
> **Free plan**. Cloudflare покажет 2 DNS-сервера (NS) вида `xxx.ns.cloudflare.com`.
> Скопируй их и пришли мне.

## 3. Point registrar NS records at Cloudflare

This is a **user-side** step — skill does NOT automate. Tell user how to
find the NS settings at their specific registrar:

**REG.ru:**
> К юзеру: https://www.reg.ru → «Мои домены» → выбери домен → «DNS-серверы
> и управление зоной» → «Изменить» → «Свои DNS-серверы» → вставь 2 NS
> которые прислал Cloudflare → Сохранить.

**Namecheap / GoDaddy / Beget / etc.:**
> К юзеру: В панели регистратора ищи раздел **DNS servers / Name Servers
> / NS-записи**. Переключи на «Custom» и вставь 2 NS из Cloudflare. Сохрани.

Propagation takes 15 min – 24 hours. Verify status:
```bash
cloudflare-dns.sh check-zone CF_TOKEN DOMAIN
```
Output `status: active` means Cloudflare has picked up the domain.

## 4. API token (for the skill)

> К юзеру: В Cloudflare справа вверху кликни профиль → **API Tokens** →
> **Create Token** → **Create custom token** (не шаблон) → настрой
> разрешения:
> - Account — Account Settings — **Edit**
> - Zone — Zone — **Read**
> - Zone — Zone — **Edit**
> - Zone — DNS — **Edit**
>
> Account Resources → **All Accounts**.
> Zone Resources → **All Zones**.
> Жми **Create Token** → скопируй и пришли (токен показывается один раз).

## 5. Zone ID

> К юзеру: Открой свой домен в Cloudflare — справа в сайдбаре найди
> **Zone ID**, скопируй и пришли.

## Scripts used by skill

- `cloudflare-dns.sh check-zone CF_TOKEN DOMAIN` — verify zone is active
- `cloudflare-dns.sh add-zone CF_TOKEN DOMAIN` — add domain via API (only
  if user hasn't done it via UI)
- `cloudflare-dns.sh create CF_TOKEN ZONE_ID DOMAIN IP SUBDOMAIN` — create
  A-record. Skill creates one per subdomain in Phase 4 step 3.

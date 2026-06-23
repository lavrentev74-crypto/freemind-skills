# Onboarding Guide — Step-by-Step Data Collection

**IMPORTANT:** Do NOT ask for everything at once. Guide the user step by step. Each step uses `AskUserQuestion` or asks one thing at a time. If the user doesn't have something — explain where and how to get it BEFORE moving on.

## Step 1 — SSH Access

Ask: "Есть VPS-сервер? Скинь IP, пароль root и порт (обычно 22)."

- If NO server → guide to buy, see `references/vps-guide.md` for link, tariffs, promo code, purchase instructions. Explain: buy → Ubuntu 22.04/24.04, no control panel → IP + root password in dashboard/email. Wait for user to buy and come back.
- If user doesn't know where to find credentials → "IP и пароль root приходят на почту после активации + в личном кабинете в разделе 'Мои серверы'."

## Step 2 — Email

Ask: "Какой email использовать для логинов сервисов?"

Explain: email creates usernames for all services (e.g. `alexey@mail.com` → logins: `alexey_port`, `alexey_git`, `alexey_sup`, `alexey_lrag`). n8n uses full email as login.

## Step 3 — Domain

Use `AskUserQuestion`:
- "Есть домен?" → Yes / No / Don't know what that is
- If NO → "Купи домен: Reg.ru (~200 R/год за .ru), Namecheap (~$8/год за .com). Домен — это адрес типа mysite.ru, по которому ты будешь заходить на сервисы." Wait for user.
- If YES → "Какой домен?"
- If "Don't know what that is" → explain: "Домен — это имя сайта (например mysite.ru). Вместо того чтобы заходить по IP (185.123.45.67), ты заходишь на n8n.mysite.ru. Нужен для SSL-сертификатов (безопасное соединение)."

## Step 4 — Cloudflare

Use `AskUserQuestion`:
- "Есть аккаунт на Cloudflare?" → Yes / No / What is Cloudflare?
- If "What is Cloudflare?" → "Cloudflare — бесплатный сервис, который управляет DNS твоего домена (направляет domain.com на IP сервера) и даёт SSL-сертификаты. Без него не обойтись."
- If NO → see `references/cloudflare-setup.md` for full setup guide. Give steps one at a time, wait for user after each.
- If YES → "Скинь API-токен."
  - If user doesn't know how → guide: "Profile (top right) → API Tokens → Create Token → **Create custom token** → Permissions: Account Settings Edit + Zone Read + Zone Edit + DNS Edit → Account Resources: All Accounts → Zone Resources: All Zones → Create → copy token (shown once!)."

## Step 5 — What to install

Use `AskUserQuestion` with multiSelect:
- "Что ставим на сервер?" Options:
  - Portainer — управление контейнерами в браузере
  - n8n — автоматизации и воркфлоу
  - OpenClaw — автономный AI-агент, работает в фоне, управление через Telegram
  - Paperclip — платформа для создания AI-компаний (команда агентов)
  - LightRAG — база знаний для AI
  - Supabase — база данных + API (нужен тариф Start, на Micro не влезет)
  - Gitea — свой Git-сервер
Note: Caddy (reverse proxy + SSL) ставится автоматически.

## Step 6 — Service-specific data

Ask ONLY for services selected in Step 5, one at a time:

**n8n:** "Имя и фамилия для аккаунта n8n?"

**OpenClaw:** "Нужен токен Telegram-бота. Если нет — открой @BotFather в Telegram → /newbot → придумай имя → получишь токен. Скинь его."

**Paperclip:** Explain: "Для Paperclip нужна подписка Claude Pro+ ($20/мес). Есть?"

**LightRAG:** Use `AskUserQuestion`:
- "Через какой LLM-провайдер работать LightRAG?"
  - Polza.ai (рекомендую, русский, дешёвый)
  - OpenRouter (много моделей)
  - OpenAI
- Then: "Скинь API-ключ провайдера." If user doesn't have → send to register. Get referral links from `references/vps-guide.md` → "Referral Links". Render naturally: "Зарегистрируйся на [Polza.ai](url)" — never show raw URL.
- Then: "Какую модель использовать?" LightRAG uses TWO models: LLM (generation) + Embedding. Suggest defaults per provider:

  | Provider | Host (OpenAI-compatible base URL) | LLM model | Embed model |
  |----------|-----------------------------------|-----------|-------------|
  | Polza.ai | `https://polza.ai/api/v1` | `google/gemini-2.5-flash-lite` | `openai/text-embedding-3-small` |
  | OpenRouter | `https://openrouter.ai/api/v1` | `google/gemini-2.5-flash-lite` | `openai/text-embedding-3-small` |
  | OpenAI | `https://api.openai.com/v1` | `gpt-4.1-nano` | `text-embedding-3-small` |

  Embed host/key = same as LLM unless user says otherwise.

  **⚠️ Host rule — do NOT invent URLs.** Use the exact host from the table or omit the arg and let the script's default fire. Past bug: agent passed `https://api.polza.ai` (by analogy to `api.*` convention) — returns 404 on `/embeddings` and `/chat/completions`, silently breaks LightRAG indexing. If the user names a provider not in the table, verify the base URL from the provider's docs before passing it.

  Ask user: "Модели по умолчанию подойдут, или хочешь другие?" Most users accept defaults.

**Supabase:** "Название организации и проекта для Supabase?" (defaults: org = domain name, project = "main")

**Gitea:** no extra data needed.

**After all steps collected → move to Phase 2 (Verify).**

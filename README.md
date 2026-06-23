# FreeMind Skills Pack

**Скиллы для Claude Code, Codex, OpenClaw и ChatGPT** — установка одной командой.

Два пакета на выбор:

| Пакет | Скиллов | Для кого |
|-------|---------|---------|
| **Базовый** | 32 | Все: автоматизация, контент, исследования |
| **Полный** | ~1032 | Разработчики и security-инженеры |

---

## Установка

### Базовый пакет (рекомендуется для старта)

```bash
git clone https://github.com/lavrentev74-crypto/freemind-skills
cd freemind-skills
bash install.sh
```

### Полный пакет (базовый + 1000 security/devops скиллов)

```bash
git clone https://github.com/lavrentev74-crypto/freemind-skills
cd freemind-skills
bash install-full.sh
```

Скрипт автоматически определяет что установлено (Claude Code, Codex, OpenClaw) и ставит в нужные места. Для ChatGPT создаёт файл на рабочем столе с инструкцией.

---

## Что ставится куда

| Инструмент | Папка | Активация |
|-----------|-------|-----------|
| Claude Code | `~/.claude/skills/` | Перезапустить приложение |
| Codex | `~/.codex/skills/` | Перезапустить приложение |
| OpenClaw/Hermes | `~/.openclaw/agents/main/agent/CLAUDE.md` | Автоматически |
| ChatGPT | Файл на рабочем столе | Скопировать в Settings → Custom Instructions |

---

## Базовые скиллы (32 шт)

| Скилл | Описание |
|-------|---------|
| `n8n-automation` | Воркфлоу и REST API n8n |
| `prompt-engeneering` | Промпты для AI-агентов |
| `claude-to-im` | Claude Code ↔ Telegram |
| `tg-notify` | Уведомления в Telegram |
| `slack` | Slack сообщения |
| `last30days` | Тренды за 30 дней (Reddit, X, HN, YouTube) |
| `youtube-summary` | Саммари YouTube с таймкодами |
| `openai-image-gen` | Генерация изображений |
| `Deep-web-search` | Глубокий поиск методом Slice |
| `brand-analysis` | Анализ бренда и позиционирования |
| `research-design` | Исследования по SPICE |
| `qual-research-design` | Качественные исследования |
| `segmentation-hypotheses` | Сегментация аудитории (28 методов) |
| `coding-agent` | Делегирование кода агенту |
| `agent-team-orchestration` | Мультиагентные команды |
| `agent-browser` | Браузерная автоматизация |
| `playwright-cli` | Playwright через CLI |
| `docx` | Word документы |
| `xlsx` | Excel/CSV |
| `nano-pdf` | PDF |
| `github` | GitHub: issues, PR, CI |
| `skill-creator` | Создание скиллов |
| `skill-conductor` | Управление скиллами |
| `mem0` | Персистентная память |
| `obsidian` | Obsidian vault |
| `openai-whisper-api` | Транскрипция аудио |
| `context-lifecycle` | Управление контекстным окном |
| `self-improvement` | Самоулучшение агента |
| `tg-audit` | Аудит постов (anti-AI) |
| `code-god` | Экспертный код-ревью |
| `violin` | Перевод и дубляж видео |
| `carousel-generator` | Генерация каруселей |

## Security/DevOps скиллы (+1000 шт, только в полном пакете)

Пентест, форензика, SOC, облачная безопасность, анализ малваря, threat hunting, OSINT, CTF.

---

Клуб [@free_mind_rus](https://t.me/free_mind_rus) — автоматизация и AI-агенты

# Шаблоны ботов (Python)

Готовый код — скопировал, добавил токен, запустил.

## Боты

| Папка | Описание | Сложность |
|-------|---------|-----------|
| `echo-bot/` | Простой эхо-бот — основа для старта | ⭐ |
| `gpt-bot/` | Бот с GPT/Claude — отвечает на любые вопросы | ⭐⭐ |
| `qualification-bot/` | Квалифицирует лидов, записывает в БД | ⭐⭐⭐ |

## Быстрый старт

```bash
cd gpt-bot
pip install -r requirements.txt
cp .env.example .env
# Добавь токены в .env
python bot.py
```

## Требования

- Python 3.10+
- Telegram Bot Token (получить у @BotFather)
- OpenAI / Anthropic API ключ (для GPT/Claude ботов)

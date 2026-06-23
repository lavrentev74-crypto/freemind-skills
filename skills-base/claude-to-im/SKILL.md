---
name: claude-to-im
description: Telegram ↔ Claude integration via n8n workflow. Use when setting up or managing @ClaudeCode_freemind_bot — the bot connecting Telegram to Claude API for Oleg. Triggers: "настроить бота", "Claude в Telegram", "ClaudeCode bot", "telegram claude workflow", "бот не отвечает". Do NOT use for general Telegram notifications (use tg-notify instead).
---

# Скилл: claude-to-im — Telegram ↔ Claude интеграция

## Назначение
Настройка и управление n8n воркфлоу, который соединяет Telegram с Claude API.
Олег управляет проектами голосом/текстом через @ClaudeCode_freemind_bot.

## Архитектура воркфлоу

```
Telegram Trigger (@ClaudeCode_freemind_bot)
  → IF: только chat_id = 154329871 (Олег)
  → HTTP Request: RAG API (http://localhost:8001/search?q=...)  [контекст из базы знаний]
  → HTTP Request: OpenRouter / Anthropic API  [Claude claude-sonnet-4-6]
  → Telegram: отправить ответ
```

## Параметры

- **Бот**: @ClaudeCode_freemind_bot
- **Разрешённый chat_id**: 154329871
- **RAG API**: http://localhost:8001/search
- **Модель**: claude-sonnet-4-6 (через OpenRouter или Anthropic API напрямую)
- **Credential Telegram**: искать в n8n по имени "ClaudeCode" или создать новый

## Команды бота

| Команда | Действие |
|---------|----------|
| /status | Показать статус всех систем |
| /rag [запрос] | Поиск по базе знаний |
| /workflows | Список активных воркфлоу |
| любой текст | Ответ Claude с контекстом из RAG |

## Системный промпт для Claude в боте

```
Ты — персональный AI-ассистент Олега Лаврентьева.
Работаешь через Telegram. Отвечаешь кратко и по делу.
Контекст из RAG: {{ragContext}}
История: {{chatHistory}}
```

## Workflow ID в n8n
После деплоя записать ID сюда: [заполнить после создания]

## Связанные файлы
- `/opt/rag/query.py` — RAG API
- `04_claude/CREDENTIALS.md` — токены
- `01_bots/` — другие боты

## Инструкция по активации
1. Проверить credential @ClaudeCode_freemind_bot в n8n
2. Если нет — добавить через n8n Credentials → Telegram API → вставить токен бота
3. Задеплоить воркфлоу через MCP
4. Активировать воркфлоу
5. Проверить: написать боту @ClaudeCode_freemind_bot в Telegram

# Code God — Примеры использования

## Быстрый вызов одной роли

### Кодер — написать функцию
```bash
bash /root/.claude/skills/code-god/scripts/call_omniroute.sh coder \
  "Напиши Python функцию для парсинга RSS-фида. Возвращает список dict с полями: title, link, pubDate, description. Используй feedparser."
```

### Фиксер — починить баг
```bash
bash /root/.claude/skills/code-god/scripts/call_omniroute.sh fixer \
  "Баг: KeyError 'choices' при пустом ответе API. Код: $(cat my_script.py)"
```

### Ревьюер — проверить код
```bash
bash /root/.claude/skills/code-god/scripts/call_omniroute.sh reviewer \
  "$(cat my_module.py)"
```

### Архитектор — спроектировать систему
```bash
bash /root/.claude/skills/code-god/scripts/call_omniroute.sh architect \
  "Спроектируй Telegram-бота для отправки ежедневных отчётов. Стек: Python, python-telegram-bot, n8n webhook."
```

## Полный pipeline

```bash
bash /root/.claude/skills/code-god/scripts/code_pipeline.sh \
  "REST API для управления VPN-клиентами (список, добавить, удалить, получить конфиг)" \
  "Python 3.11, FastAPI, 3x-ui API"
```

Результаты сохраняются в `/tmp/code_pipeline_<timestamp>/`:
- `1_architecture.md` — план от Архитектора
- `2_implementation.md` — код от Кодера
- `3_review.md` — ревью от Ревьюера

## Inline curl (для быстрых задач без скриптов)

```bash
# Кодер inline
curl -s http://localhost:20128/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-864f3a169c7f362a-842421-02901aea" \
  -d '{"model":"qwen/qwen3-coder-plus","stream":false,"messages":[{"role":"user","content":"Напиши bash скрипт для бэкапа папки /data в /backup с датой"}]}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
```

## Выбор роли по задаче

| Задача | Роль | Модель |
|--------|------|--------|
| Новый сервис с нуля | architect → coder → reviewer | sonnet → qwen-plus → sonnet |
| Добавить endpoint в API | coder | qwen-plus |
| Баг в существующем коде | fixer | qwen-flash |
| Оптимизация алгоритма | architect → coder | sonnet → qwen-plus |
| Проверить чужой код | reviewer → fixer | sonnet → qwen-flash |
| Написать тесты | coder | qwen-plus |
| Рефакторинг модуля | architect → coder → reviewer | sonnet → qwen-plus → sonnet |
| Однострочник / утилита | coder | qwen-plus |

## Модели напрямую (минуя алиасы)

```bash
# Прямое указание модели вместо роли
bash /root/.claude/skills/code-god/scripts/call_omniroute.sh \
  "qwen/qwen3-coder-plus" "твой промпт"

bash /root/.claude/skills/code-god/scripts/call_omniroute.sh \
  "kiro/claude-sonnet-4.5" "твой промпт"
```

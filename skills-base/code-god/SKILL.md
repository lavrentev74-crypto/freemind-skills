---
name: code-god
description: >
  Multi-agent coding system with 4 specialized roles: Architect (design), Coder (implementation),
  Reviewer (quality), Fixer (debug/patch). Use when writing, refactoring, debugging, or reviewing
  code of any complexity. Triggers on: "напиши код", "реализуй", "отладь", "отрефактори",
  "сделай code review", "почини баг", "архитектура сервиса", or any coding task that benefits
  from a structured multi-step approach. All models run through OmniRoute (localhost:20128).
---

# Code God — Multi-Agent Coding System

4 роли, один pipeline. Каждая задача проходит нужные этапы.

## Роли и модели

| Роль | Модель | Когда |
|------|--------|-------|
| **Архитектор** | `kiro/claude-sonnet-4.5` | Проектирование, декомпозиция, tech decisions |
| **Кодер** | `qwen/qwen3-coder-plus` | Основная реализация кода |
| **Ревьюер** | `kiro/claude-sonnet-4.5` | Code review, качество, безопасность |
| **Фиксер** | `qwen/qwen3-coder-flash` | Быстрые правки, дебаг, патчи |

Все через один endpoint: `http://localhost:20128/v1/chat/completions`
Auth: `Bearer sk-864f3a169c7f362a-842421-02901aea`

## Базовый вызов

```bash
curl -s http://localhost:20128/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-864f3a169c7f362a-842421-02901aea" \
  -d '{"model":"MODEL_NAME","stream":false,"messages":[{"role":"user","content":"ПРОМПТ"}]}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
```

## Pipeline по типу задачи

### Новая фича / сервис
```
Архитектор → Кодер → Ревьюер
```
1. Архитектор: декомпозиция, структура, интерфейсы
2. Кодер: реализация по архитектуре
3. Ревьюер: проверка качества, баги, безопасность

### Баг / патч
```
Фиксер (если простой) → Ревьюер (если критичный)
```

### Рефакторинг
```
Архитектор → Кодер → Ревьюер
```

### Code review запрос
```
Ревьюер → (Фиксер если нашёл проблемы)
```

### Быстрый snippet / утилита
```
Кодер → (Ревьюер опционально)
```

## Промпты по ролям

### Архитектор (kiro/claude-sonnet-4.5)
```
Ты senior software architect. Задача: [ЗАДАЧА].

Контекст проекта: [СТЕК/ЯЗЫК/СРЕДА]

Выдай:
1. Декомпозицию на модули/функции
2. Интерфейсы и типы данных
3. Зависимости и порядок реализации
4. Потенциальные риски

Без кода — только архитектура и план.
```

### Кодер (qwen/qwen3-coder-plus)
```
Ты опытный разработчик. Реализуй следующее:

Архитектура: [ВЫВОД АРХИТЕКТОРА]
Задача: [КОНКРЕТНАЯ ЧАСТЬ]
Стек: [ЯЗЫК/ФРЕЙМВОРК/ВЕРСИЯ]

Требования:
- Рабочий, production-ready код
- Комментарии на сложных местах
- Обработка ошибок
- Без заглушек и TODO (если не оговорено)

Верни только код с минимальными пояснениями.
```

### Ревьюер (kiro/claude-sonnet-4.5)
```
Ты senior код-ревьюер. Проверь код:

[КОД]

Найди:
1. Баги и логические ошибки
2. Проблемы безопасности
3. Проблемы производительности
4. Нарушения best practices

Для каждой проблемы: severity (critical/major/minor), строка, описание, fix.
Если всё ок — скажи "LGTM" с кратким обоснованием.
```

### Фиксер (qwen/qwen3-coder-flash)
```
Быстро исправь проблему в коде:

Проблема: [ОПИСАНИЕ БАГА / ВЫВОД РЕВЬЮЕРА]
Код: [КОД]

Верни исправленный код с комментарием что изменил.
```

## Скрипты

- `scripts/call_omniroute.sh` — универсальный вызов любой роли
- `scripts/code_pipeline.sh` — полный pipeline Архитектор→Кодер→Ревьюер

Подробнее: [references/examples.md](references/examples.md)

## Правила

- Qwen3-coder-plus — основной кодер, быстрый и точный
- Qwen3-coder-flash — только для быстрых правок и дебага
- Claude-sonnet (kiro) — архитектура и ревью, требует больше времени
- Если OmniRoute недоступен — проверить `curl http://localhost:20128/health`
- Большие задачи (>500 строк) — разбивать на части через Архитектора

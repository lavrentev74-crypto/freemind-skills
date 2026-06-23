---
name: wf-audit
description: Аудит n8n воркфлоу и Python кода. Находит staticData, Google Drive зависимости, архитектурные проблемы. Даёт вердикт и план исправления.
triggers:
  - /wf-audit
  - аудит воркфлоу
  - проверь воркфлоу
  - что не так с кодом
  - проанализируй json
---

# wf-audit — Аудит воркфлоу и кода

## Как использовать
/wf-audit /путь/к/файлу.json

## Алгоритм (Claude выполняет)

1. Взять путь к файлу из аргументов
2. Запустить Agent() с задачей:
   - Прочитать файл
   - Запустить анализ через OmniRoute (curl ниже)
   - Сохранить результат в /tmp/wf_audit_result.md
3. Прочитать /tmp/wf_audit_result.md
4. Показать пользователю вердикт + список проблем
5. Если есть проблемы — предложить: "Исправить через /code-god?"

## curl для анализа (OmniRoute)

```bash
curl -s http://localhost:20128/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-864f3a169c7f362a-842421-02901aea" \
  -d "{\"model\":\"kiro/claude-sonnet-4.5\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Проанализируй этот n8n воркфлоу или код. Найди: 1) getWorkflowStaticData/staticData — КРИТИЧНО, 2) Google Drive/Sheets ноды — нужна замена на DataTable, 3) логические ошибки в маршрутизации, 4) неиспользуемые ноды. Дай: вердикт ГОДЕН/НУЖНА ПРАВКА/ПЕРЕПИСАТЬ, список проблем с уровнем критичности, краткую схему логики. Воркфлоу:\\n\\nКОНТЕНТ_ФАЙЛА\"}]}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
```

## Таблица критичности проблем n8n

| Проблема | Критичность | Решение |
|----------|-------------|---------|
| staticData/$getWorkflowStaticData | 🔴 КРИТИЧНО | Заменить на DataTable |
| Google Drive/Sheets ноды | 🟠 ВЫСОКАЯ | Заменить на DataTable |
| Неиспользуемые ноды | 🟡 СРЕДНЯЯ | Удалить |
| Отсутствует executionOrder v1 | 🟡 СРЕДНЯЯ | Добавить в settings |
| Нет обработки ошибок | 🟡 СРЕДНЯЯ | Добавить IF-ветку |
| Жёстко прописанные ID | 🟢 НИЗКАЯ | Вынести в переменные |

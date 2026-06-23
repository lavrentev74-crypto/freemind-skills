---
name: youtube-summary
description: Get YouTube video transcript and summarize — key ideas, theses, conclusions. Use when user shares a youtube.com or youtu.be link and asks for a summary, recap, or key points. Triggers: "саммари видео", "выжимка", "кратко о видео", "что там говорят", "summarize this video". Do NOT use for downloading video files or extracting audio.
---

# YouTube Summary

## Workflow

1. Запусти скрипт для получения транскрипта:
```bash
python3 ~/.claude/skills/youtube-summary/scripts/get_transcript.py <URL>
```

2. Получишь JSON с полем `transcript`. Если `error` — субтитры недоступны, сообщи пользователю.

3. Из JSON получишь:
   - `transcript` — полный текст
   - `timed_chunks` — массив `[{timecode: "1:23", text: "..."}]` блоками по ~60 сек

4. Делегируй саммари Groq (не трать токены Claude). Передай timed_chunks для извлечения таймкодов:
```bash
curl -s https://api.groq.com/openai/v1/chat/completions \
  -H "Authorization: Bearer $GROQ_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"llama-3.3-70b-versatile\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": \"Сделай структурированную выжимку на русском языке. Формат:\n## О чём видео (2-3 предложения)\n## Ключевые идеи (5-7 тезисов)\n## Таймкоды важных моментов\nСписок: [MM:SS] — что происходит. Выбери 5-10 самых важных моментов из timed_chunks.\n## Главный вывод\n\nТранскрипт по блокам с таймкодами:\n<TIMED_CHUNKS>\"
    }],
    \"temperature\": 0.3
  }"
```

5. Выдай результат пользователю в структурированном виде.

## Если субтитры недоступны

Используй yt-dlp для получения метаданных и описания:
```bash
yt-dlp --dump-json --no-download <URL> | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f'Название: {d[\"title\"]}')
print(f'Канал: {d[\"uploader\"]}')
print(f'Описание: {d[\"description\"][:1000]}')
"
```

## Формат ответа пользователю

```
🎬 **[Название видео]**
📺 Канал | ⏱ Длительность | 🌐 Язык субтитров

## О чём видео
...

## Ключевые идеи
- ...
- ...

## Главный вывод
...
```

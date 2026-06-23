#!/usr/bin/env python3
"""
Получает транскрипт YouTube видео с таймкодами.
Приоритет: русский → английский → любой доступный.
Использование: python3 get_transcript.py <youtube_url_or_id>
"""
import sys
import re
import json

def extract_video_id(url_or_id):
    patterns = [
        r'(?:v=|youtu\.be/|/embed/|/v/)([a-zA-Z0-9_-]{11})',
        r'^([a-zA-Z0-9_-]{11})$'
    ]
    for p in patterns:
        m = re.search(p, url_or_id)
        if m:
            return m.group(1)
    return None

def fmt_time(seconds):
    """Конвертирует секунды в MM:SS или HH:MM:SS"""
    s = int(seconds)
    h, m = divmod(s, 3600)
    m, s = divmod(m, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"

def parse_entry(e):
    if isinstance(e, dict):
        return e.get('text', ''), e.get('start', 0)
    return getattr(e, 'text', ''), getattr(e, 'start', 0)

def get_transcript(video_id):
    from youtube_transcript_api import YouTubeTranscriptApi
    from youtube_transcript_api._errors import NoTranscriptFound, TranscriptsDisabled

    api = YouTubeTranscriptApi()

    try:
        transcript_list = api.list(video_id)
    except TranscriptsDisabled:
        return None, None, "Субтитры отключены для этого видео"
    except Exception as e:
        return None, None, f"Ошибка: {e}"

    entries = None
    lang = None

    for l in ['ru', 'en', 'uk', 'de', 'fr']:
        try:
            t = transcript_list.find_transcript([l])
            entries = t.fetch()
            lang = l
            break
        except NoTranscriptFound:
            continue
        except Exception:
            continue

    if entries is None:
        try:
            t = next(iter(transcript_list))
            entries = t.fetch()
            lang = t.language_code
        except Exception as e:
            return None, None, f"Нет доступных субтитров: {e}"

    # Строим полный текст и тайм-чанки (каждые ~60 сек)
    full_text = []
    timed_chunks = []  # [{time, timecode, text}] — блоки для Groq
    chunk_buf = []
    chunk_start = None
    CHUNK_SEC = 60

    for e in entries:
        text, start = parse_entry(e)
        if not text.strip():
            continue
        full_text.append(text)

        if chunk_start is None:
            chunk_start = start

        chunk_buf.append(text)

        if start - chunk_start >= CHUNK_SEC:
            timed_chunks.append({
                "time": round(chunk_start),
                "timecode": fmt_time(chunk_start),
                "text": ' '.join(chunk_buf)
            })
            chunk_buf = []
            chunk_start = None

    if chunk_buf and chunk_start is not None:
        timed_chunks.append({
            "time": round(chunk_start),
            "timecode": fmt_time(chunk_start),
            "text": ' '.join(chunk_buf)
        })

    plain = ' '.join(full_text)
    return plain, timed_chunks, lang

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Укажи URL или ID видео"}))
        sys.exit(1)

    video_id = extract_video_id(sys.argv[1])
    if not video_id:
        print(json.dumps({"error": "Не удалось извлечь ID видео"}))
        sys.exit(1)

    plain, chunks, lang_or_error = get_transcript(video_id)

    if plain:
        truncated = len(plain) > 15000
        print(json.dumps({
            "video_id": video_id,
            "language": lang_or_error,
            "transcript": plain[:15000],
            "timed_chunks": chunks[:150],  # макс 150 чанков
            "truncated": truncated,
            "length": len(plain)
        }, ensure_ascii=False))
    else:
        print(json.dumps({"error": lang_or_error, "video_id": video_id}))
        sys.exit(1)

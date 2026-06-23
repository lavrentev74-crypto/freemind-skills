#!/bin/bash
# FreeMind Skills — Базовый пакет (32 скилла)

SKILLS_DIR="$(cd "$(dirname "$0")/skills-base" && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
OPENCLAW_DIR="$HOME/.openclaw/agents/main/agent"
CHATGPT_FILE="$HOME/Desktop/chatgpt_custom_instructions.md"

echo ""
echo "🧠 FreeMind Skills — Базовый пакет"
echo "=================================="
echo ""

# ── 1. Claude Code ──────────────────────────────────────────────
mkdir -p "$CLAUDE_SKILLS"
count=0
for skill in "$SKILLS_DIR"/*/; do
  name=$(basename "$skill")
  cp -r "$skill" "$CLAUDE_SKILLS/$name"
  count=$((count+1))
done
echo "✅ Claude Code: $count скиллов → $CLAUDE_SKILLS"

# ── 2. Codex ────────────────────────────────────────────────────
if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
  mkdir -p "$CODEX_SKILLS"
  for skill in "$SKILLS_DIR"/*/; do
    cp -r "$skill" "$CODEX_SKILLS/"
  done
  echo "✅ Codex: $count скиллов → $CODEX_SKILLS"
else
  echo "⏭  Codex: не установлен, пропускаем"
fi

# ── 3. OpenClaw / Hermes ────────────────────────────────────────
if [ -f "$OPENCLAW_DIR/CLAUDE.md" ]; then
  echo "" >> "$OPENCLAW_DIR/CLAUDE.md"
  echo "## Available Skills (FreeMind Base Pack)" >> "$OPENCLAW_DIR/CLAUDE.md"
  for skill in "$SKILLS_DIR"/*/; do
    name=$(basename "$skill")
    desc=$(grep "^description:" "$skill/SKILL.md" 2>/dev/null | head -1 | sed 's/description: //')
    echo "- **$name**: $desc" >> "$OPENCLAW_DIR/CLAUDE.md"
  done
  echo "✅ OpenClaw: список скиллов добавлен в CLAUDE.md"
else
  echo "⏭  OpenClaw: не установлен, пропускаем"
fi

# ── 4. ChatGPT ──────────────────────────────────────────────────
cp "$(dirname "$0")/FOR_AI.md" "$CHATGPT_FILE" 2>/dev/null
echo "✅ ChatGPT: инструкция → $CHATGPT_FILE"
echo "   Открой Settings → Personalization → Custom Instructions → вставь содержимое"

# ── Вывод установленных скиллов ─────────────────────────────────
echo ""
echo "=================================="
echo "📦 Установлены скиллы и их польза:"
echo "=================================="
echo ""

declare -A SKILLS_HELP
SKILLS_HELP["n8n-automation"]="Автоматизирует рутину: заявка → уведомление → таблица → ответ клиенту"
SKILLS_HELP["prompt-engeneering"]="Делает промпты точными: бот отвечает как нужно и держит роль"
SKILLS_HELP["claude-to-im"]="Подключает Claude прямо в Telegram или другой мессенджер"
SKILLS_HELP["tg-notify"]="Алерты и дайджесты в Telegram — всегда знаешь что происходит"
SKILLS_HELP["slack"]="Интеграции и уведомления в Slack"
SKILLS_HELP["tg-audit"]="Убирает AI-клише из постов — читают до конца"
SKILLS_HELP["carousel-generator"]="Превращает текст в карусель для соцсетей"
SKILLS_HELP["youtube-summary"]="Конспект любого YouTube видео с таймкодами"
SKILLS_HELP["openai-image-gen"]="Генерирует изображения по описанию"
SKILLS_HELP["Deep-web-search"]="Глубокое исследование: 10+ источников параллельно"
SKILLS_HELP["last30days"]="Тренды за 30 дней по твоей теме (Reddit, X, HN, YouTube)"
SKILLS_HELP["brand-analysis"]="Разбирает бренд: аудитория, тон, позиционирование"
SKILLS_HELP["research-design"]="Планирует исследование по SPICE — реальные инсайты, не вода"
SKILLS_HELP["qual-research-design"]="Сценарии интервью и фокус-групп под ключ"
SKILLS_HELP["segmentation-hypotheses"]="Нарезает аудиторию на сегменты — находит самых платёжеспособных"
SKILLS_HELP["coding-agent"]="Пишет, отлаживает и объясняет код: Python, JS, SQL"
SKILLS_HELP["agent-team-orchestration"]="Разбивает большую задачу на агентов и координирует их"
SKILLS_HELP["agent-browser"]="Автоматизирует браузер: парсинг, формы, тестирование"
SKILLS_HELP["playwright-cli"]="Playwright тесты и автоматизация через CLI"
SKILLS_HELP["github"]="PR, issues, CI/CD, code review в GitHub"
SKILLS_HELP["code-god"]="Экспертный разбор кода: баги, безопасность, улучшения"
SKILLS_HELP["docx"]="Создаёт и разбирает Word-документы"
SKILLS_HELP["xlsx"]="Работает с Excel и CSV: анализ, формулы, преобразования"
SKILLS_HELP["nano-pdf"]="Извлекает текст и данные из PDF"
SKILLS_HELP["mem0"]="Запоминает важное между сессиями — контекст не теряется"
SKILLS_HELP["obsidian"]="Работает с базой знаний Obsidian"
SKILLS_HELP["openai-whisper-api"]="Переводит аудио и видео в текст"
SKILLS_HELP["violin"]="Переводит видео на другой язык с дубляжом"
SKILLS_HELP["context-lifecycle"]="Следит за контекстом, делает handoff вовремя"
SKILLS_HELP["self-improvement"]="Анализирует ошибки и улучшает работу через паттерны"
SKILLS_HELP["skill-creator"]="Создаёт новые скиллы под твои задачи"
SKILLS_HELP["skill-conductor"]="Управляет набором скиллов"

for skill in "$SKILLS_DIR"/*/; do
  name=$(basename "$skill")
  help="${SKILLS_HELP[$name]:-Специализированный скилл}"
  printf "  %-30s %s\n" "/$name" "$help"
done

echo ""
echo "=================================="
echo "🎉 Готово! Перезапусти Claude Code."
echo ""
echo "📄 Файл для ChatGPT: $CHATGPT_FILE"
echo "📄 Инструкция для нейросети: FOR_AI.md"
echo ""
echo "Для полного пакета (+1000 security скиллов):"
echo "  bash install-full.sh"
echo ""

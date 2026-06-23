#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  FreeMind Skills Installer
#  github.com/lavrentev74-crypto/freemind-skills
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
OPENCLAW_DIR="$HOME/.openclaw/agents/main/agent"
CHATGPT_FILE="$HOME/Desktop/chatgpt_custom_instructions.md"

# ── Приветствие ─────────────────────────────────────────────────
clear
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          🧠 FreeMind Skills Installer                ║"
echo "║     github.com/lavrentev74-crypto/freemind-skills    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Выбор пакета ────────────────────────────────────────────────
echo "  Выбери пакет установки:"
echo ""
echo "  [1] БАЗОВЫЙ — 32 скилла"
echo "      Автоматизация, контент, исследования, разработка."
echo "      Для всех: маркетологов, предпринимателей, авторов."
echo "      Размер: ~5 МБ | Время: ~10 сек"
echo ""
echo "  [2] ПОЛНЫЙ — 32 + 1000 скиллов"
echo "      Базовый пакет + security, DevOps, пентест, форензика."
echo "      Для разработчиков и IT-специалистов."
echo "      Размер: ~60 МБ | Время: ~30 сек"
echo ""
read -p "  Введи 1 или 2 и нажми Enter: " CHOICE
echo ""

case "$CHOICE" in
  1) INSTALL_SECURITY=false ;;
  2) INSTALL_SECURITY=true ;;
  *)
    echo "  ❌ Неверный выбор. Устанавливаем базовый пакет."
    INSTALL_SECURITY=false ;;
esac

# ── Определяем что установлено ──────────────────────────────────
echo "  🔍 Определяю установленные инструменты..."
echo ""

HAS_CLAUDE=false
HAS_CODEX=false
HAS_OPENCLAW=false

command -v claude &>/dev/null && HAS_CLAUDE=true
[ -d "$HOME/.claude" ] && HAS_CLAUDE=true
command -v codex &>/dev/null && HAS_CODEX=true
[ -d "$HOME/.codex" ] && HAS_CODEX=true
[ -d "$HOME/.openclaw" ] && HAS_OPENCLAW=true

$HAS_CLAUDE    && echo "  ✅ Claude Code — найден" || echo "  ⬜ Claude Code — не найден"
$HAS_CODEX     && echo "  ✅ Codex — найден"       || echo "  ⬜ Codex — не найден"
$HAS_OPENCLAW  && echo "  ✅ OpenClaw — найден"     || echo "  ⬜ OpenClaw — не найден"
echo "  ✅ ChatGPT — файл будет создан на рабочем столе"
echo ""

# ── Установка базовых скиллов ───────────────────────────────────
BASE_DIR="$SCRIPT_DIR/skills-base"
count_base=0

install_skills() {
  local src_dir="$1"
  local dst_dir="$2"
  local label="$3"
  local count=0
  mkdir -p "$dst_dir"
  for skill in "$src_dir"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    cp -r "$skill" "$dst_dir/$name"
    count=$((count+1))
  done
  echo "  ✅ $label: +$count скиллов → $dst_dir"
  echo $count
}

echo "  📦 Устанавливаю базовый пакет..."

if $HAS_CLAUDE; then
  count_base=$(install_skills "$BASE_DIR" "$CLAUDE_SKILLS" "Claude Code")
fi
if $HAS_CODEX; then
  install_skills "$BASE_DIR" "$CODEX_SKILLS" "Codex" > /dev/null
fi
if $HAS_OPENCLAW && [ -f "$OPENCLAW_DIR/CLAUDE.md" ]; then
  echo "" >> "$OPENCLAW_DIR/CLAUDE.md"
  echo "## FreeMind Skills (Base Pack)" >> "$OPENCLAW_DIR/CLAUDE.md"
  for skill in "$BASE_DIR"/*/; do
    name=$(basename "$skill")
    desc=$(grep "^description:" "$skill/SKILL.md" 2>/dev/null | head -1 | sed 's/description: //')
    echo "- **$name**: $desc" >> "$OPENCLAW_DIR/CLAUDE.md"
  done
  echo "  ✅ OpenClaw: список добавлен в CLAUDE.md"
fi

# ── Установка security скиллов ──────────────────────────────────
count_sec=0
if $INSTALL_SECURITY; then
  echo ""
  echo "  🔐 Устанавливаю security/devops пакет..."
  SEC_DIR="$SCRIPT_DIR/skills-security"
  if $HAS_CLAUDE; then
    count_sec=$(install_skills "$SEC_DIR" "$CLAUDE_SKILLS" "Claude Code (security)")
  fi
  if $HAS_CODEX; then
    install_skills "$SEC_DIR" "$CODEX_SKILLS" "Codex (security)" > /dev/null
  fi
fi

# ── ChatGPT ─────────────────────────────────────────────────────
cp "$SCRIPT_DIR/FOR_AI.md" "$CHATGPT_FILE" 2>/dev/null
echo "  ✅ ChatGPT: инструкция → $CHATGPT_FILE"

# ── Список установленных скиллов ────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║            📦 Установленные скиллы                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  🤖 АВТОМАТИЗАЦИЯ И БОТЫ"
echo "  ├─ /n8n-automation         Строит автоматизации без кода: заявка→Telegram→таблица"
echo "  ├─ /prompt-engeneering     Делает промпты точными — бот держит роль и не галлюцинирует"
echo "  ├─ /claude-to-im           Подключает Claude прямо в Telegram"
echo "  ├─ /tg-notify              Алерты и дайджесты в Telegram"
echo "  └─ /slack                  Уведомления и интеграции в Slack"
echo ""
echo "  ✍️  КОНТЕНТ И СОЦСЕТИ"
echo "  ├─ /tg-audit               Убирает AI-клише из постов — читают до конца"
echo "  ├─ /carousel-generator     Превращает текст в карусель для соцсетей"
echo "  ├─ /youtube-summary        Конспект YouTube видео с таймкодами"
echo "  └─ /openai-image-gen       Генерирует изображения по описанию"
echo ""
echo "  🔍 ИССЛЕДОВАНИЯ И СТРАТЕГИЯ"
echo "  ├─ /Deep-web-search        Глубокое исследование: 10+ источников параллельно"
echo "  ├─ /last30days             Тренды за 30 дней (Reddit, X, HN, YouTube)"
echo "  ├─ /brand-analysis         Аудитория, тон, позиционирование бренда"
echo "  ├─ /research-design        Исследование по SPICE — реальные инсайты"
echo "  ├─ /qual-research-design   Интервью и фокус-группы под ключ"
echo "  └─ /segmentation-hypotheses  Сегментация аудитории по 28 методам"
echo ""
echo "  💻 РАЗРАБОТКА"
echo "  ├─ /coding-agent           Пишет и отлаживает код: Python, JS, SQL"
echo "  ├─ /agent-team-orchestration  Мультиагентные команды для сложных задач"
echo "  ├─ /agent-browser          Автоматизация браузера: парсинг, формы"
echo "  ├─ /github                 PR, issues, CI/CD, code review"
echo "  └─ /code-god               Экспертный разбор кода: баги и безопасность"
echo ""
echo "  📁 ФАЙЛЫ"
echo "  ├─ /docx                   Word документы"
echo "  ├─ /xlsx                   Excel и CSV: анализ и преобразования"
echo "  └─ /nano-pdf               Извлечение данных из PDF"
echo ""
echo "  🧠 ПАМЯТЬ И РАЗВИТИЕ"
echo "  ├─ /mem0                   Запоминает контекст между сессиями"
echo "  ├─ /obsidian               Работа с базой знаний Obsidian"
echo "  ├─ /openai-whisper-api     Транскрипция аудио и видео в текст"
echo "  ├─ /violin                 Перевод и дубляж видео"
echo "  ├─ /context-lifecycle      Управление контекстом — ничего не теряется"
echo "  └─ /self-improvement       Улучшение работы через паттерны"
echo ""
echo "  🛠️  СКИЛЛЫ"
echo "  ├─ /skill-creator          Создаёт новые скиллы под твои задачи"
echo "  └─ /skill-conductor        Управление набором скиллов"

if $INSTALL_SECURITY; then
  echo ""
  echo "  🔐 SECURITY / DEVOPS (+$count_sec скиллов)"
  echo "  └─ Пентест, форензика, SOC, облачная безопасность,"
  echo "     анализ малваря, threat hunting, OSINT, CTF"
fi

total=$((32 + count_sec))
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  🎉 Готово! Установлено скиллов: $total"
echo "║"
echo "║  Перезапусти Claude Code / Codex для активации."
echo "║"
echo "║  ChatGPT: открой файл на рабочем столе →"
echo "║  Settings → Personalization → Custom Instructions"
echo "║"
echo "║  Клуб: t.me/free_mind_rus"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

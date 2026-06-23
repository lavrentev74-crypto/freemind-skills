#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  FreeMind Installer
#  github.com/lavrentev74-crypto/freemind-skills
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
OPENCLAW_DIR="$HOME/.openclaw/agents/main/agent"
N8N_DIR="$HOME/n8n-imports"
BOTS_DIR="$HOME/freemind-bots"
MCP_TARGET="$HOME"

# ── Приветствие ─────────────────────────────────────────────────
clear
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            🧠 FreeMind Installer                         ║"
echo "║   github.com/lavrentev74-crypto/freemind-skills          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Выбери что установить (можно несколько через пробел):"
echo "  Пример: 1 2 3"
echo ""
echo "  ┌─ СКИЛЛЫ ────────────────────────────────────────────┐"
echo "  │ 1  Базовые скиллы (32)                               │"
echo "  │    Автоматизация, контент, исследования, разработка  │"
echo "  │    Для всех: маркетологов, авторов, предпринимателей │"
echo "  │                                                       │"
echo "  │ 2  Полный пакет скиллов (32 + 1000)                  │"
echo "  │    Базовые + security, DevOps, пентест, форензика    │"
echo "  │    Для разработчиков и IT-специалистов               │"
echo "  └───────────────────────────────────────────────────────┘"
echo "  ┌─ ПРОМПТЫ ───────────────────────────────────────────┐"
echo "  │ 3  Промпты                                           │"
echo "  │    Контент, исследования, ЦА, системные промпты     │"
echo "  │    для ботов — копируй и используй сразу            │"
echo "  └───────────────────────────────────────────────────────┘"
echo "  ┌─ АВТОМАТИЗАЦИЯ ─────────────────────────────────────┐"
echo "  │ 4  n8n воркфлоу                                      │"
echo "  │    Готовые воркфлоу для импорта в n8n одной кнопкой │"
echo "  │    Telegram-боты, рассылки, CRM-интеграции           │"
echo "  └───────────────────────────────────────────────────────┘"
echo "  ┌─ КОД ───────────────────────────────────────────────┐"
echo "  │ 5  Шаблоны ботов (Python)                            │"
echo "  │    Готовый код: эхо-бот, GPT-бот, бот-квалификатор  │"
echo "  │    Скопировал → добавил токен → запустил             │"
echo "  └───────────────────────────────────────────────────────┘"
echo "  ┌─ НАСТРОЙКИ ─────────────────────────────────────────┐"
echo "  │ 6  MCP конфиги                                       │"
echo "  │    Готовые .mcp.json для подключения серверов:       │"
echo "  │    PostgreSQL, LightRAG, GitHub, Playwright и др.    │"
echo "  └───────────────────────────────────────────────────────┘"
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ 7  Всё сразу (рекомендуется)                         │"
echo "  └───────────────────────────────────────────────────────┘"
echo ""
read -p "  Твой выбор: " CHOICES
echo ""

# Если выбрано 7 — ставим всё
if echo "$CHOICES" | grep -q "7"; then
  CHOICES="1 3 4 5 6"
fi
# Если выбрано 2 — включает и базовые
if echo "$CHOICES" | grep -q "2"; then
  CHOICES="$CHOICES 1"
fi

# ── Вспомогательная функция установки скиллов ──────────────────
install_skills_to() {
  local src="$1" dst="$2" label="$3"
  local count=0
  mkdir -p "$dst"
  for skill in "$src"/*/; do
    [ -d "$skill" ] || continue
    cp -r "$skill" "$dst/"
    count=$((count+1))
  done
  echo "  ✅ $label: $count скиллов → $dst"
}

# ── Определяем инструменты ──────────────────────────────────────
HAS_CLAUDE=false; HAS_CODEX=false; HAS_OPENCLAW=false
{ command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; } && HAS_CLAUDE=true
{ command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; }   && HAS_CODEX=true
[ -d "$HOME/.openclaw" ] && HAS_OPENCLAW=true

# ── [1/2] Базовые скиллы ───────────────────────────────────────
if echo "$CHOICES" | grep -qE "1|2"; then
  echo "  📦 Устанавливаю базовые скиллы..."
  BASE="$SCRIPT_DIR/skills-base"
  $HAS_CLAUDE   && install_skills_to "$BASE" "$CLAUDE_SKILLS" "Claude Code"
  $HAS_CODEX    && install_skills_to "$BASE" "$CODEX_SKILLS"  "Codex"
  if $HAS_OPENCLAW && [ -f "$OPENCLAW_DIR/CLAUDE.md" ]; then
    printf "\n## FreeMind Skills\n" >> "$OPENCLAW_DIR/CLAUDE.md"
    for skill in "$BASE"/*/; do
      name=$(basename "$skill")
      desc=$(grep "^description:" "$skill/SKILL.md" 2>/dev/null | head -1 | sed 's/description: //')
      echo "- **$name**: $desc" >> "$OPENCLAW_DIR/CLAUDE.md"
    done
    echo "  ✅ OpenClaw: скиллы добавлены"
  fi
  # ChatGPT файл
  cp "$SCRIPT_DIR/FOR_AI.md" "$HOME/Desktop/chatgpt_instructions.md" 2>/dev/null
  echo "  ✅ ChatGPT: файл → ~/Desktop/chatgpt_instructions.md"
fi

# ── [2] Security скиллы (+1000) ─────────────────────────────────
if echo "$CHOICES" | grep -q "2"; then
  echo ""
  echo "  🔐 Устанавливаю security/devops пакет..."
  SEC="$SCRIPT_DIR/skills-security"
  $HAS_CLAUDE && install_skills_to "$SEC" "$CLAUDE_SKILLS" "Claude Code (security)"
  $HAS_CODEX  && install_skills_to "$SEC" "$CODEX_SKILLS"  "Codex (security)"
fi

# ── [3] Промпты ─────────────────────────────────────────────────
if echo "$CHOICES" | grep -q "3"; then
  echo ""
  echo "  📝 Устанавливаю промпты..."
  PROMPTS_DST="$HOME/freemind-prompts"
  mkdir -p "$PROMPTS_DST"
  cp -r "$SCRIPT_DIR/prompts/." "$PROMPTS_DST/"
  echo "  ✅ Промпты → $PROMPTS_DST"
  echo "  ℹ️  Открой папку и копируй нужные промпты в свою нейросеть"
fi

# ── [4] n8n воркфлоу ────────────────────────────────────────────
if echo "$CHOICES" | grep -q "4"; then
  echo ""
  echo "  ⚙️  Подготавливаю n8n воркфлоу..."
  mkdir -p "$N8N_DIR"
  cp -r "$SCRIPT_DIR/workflows/." "$N8N_DIR/"
  count=$(find "$N8N_DIR" -name "*.json" | wc -l)
  echo "  ✅ n8n воркфлоу ($count шт) → $N8N_DIR"
  echo "  ℹ️  Как импортировать:"
  echo "      n8n → Workflows → Import from file → выбери JSON"
fi

# ── [5] Шаблоны ботов ───────────────────────────────────────────
if echo "$CHOICES" | grep -q "5"; then
  echo ""
  echo "  🤖 Устанавливаю шаблоны ботов..."
  mkdir -p "$BOTS_DIR"
  cp -r "$SCRIPT_DIR/bots/." "$BOTS_DIR/"
  echo "  ✅ Шаблоны ботов → $BOTS_DIR"
  echo "  ℹ️  В каждой папке README с инструкцией запуска"
fi

# ── [6] MCP конфиги ─────────────────────────────────────────────
if echo "$CHOICES" | grep -q "6"; then
  echo ""
  echo "  🔌 Устанавливаю MCP конфиги..."
  if [ -f "$SCRIPT_DIR/mcp/.mcp.json.example" ]; then
    if [ -f "$MCP_TARGET/.mcp.json" ]; then
      cp "$MCP_TARGET/.mcp.json" "$MCP_TARGET/.mcp.json.backup.$(date +%Y%m%d)"
      echo "  ℹ️  Старый .mcp.json сохранён как .mcp.json.backup"
    fi
    cp "$SCRIPT_DIR/mcp/.mcp.json.example" "$MCP_TARGET/.mcp.json.freemind"
    echo "  ✅ MCP конфиг → $MCP_TARGET/.mcp.json.freemind"
    echo "  ℹ️  Переименуй в .mcp.json или скопируй нужные секции"
  fi
fi

# ── Итог ────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    🎉 Готово!                            ║"
echo "╠══════════════════════════════════════════════════════════╣"

if echo "$CHOICES" | grep -qE "1|2"; then
echo "║  Скиллы:                                                 ║"
echo "║  • Claude Code / Codex — перезапусти приложение         ║"
echo "║  • ChatGPT — ~/Desktop/chatgpt_instructions.md          ║"
echo "║    → Settings → Personalization → Custom Instructions   ║"
fi
if echo "$CHOICES" | grep -q "3"; then
echo "║  Промпты: ~/freemind-prompts/                            ║"
fi
if echo "$CHOICES" | grep -q "4"; then
echo "║  n8n воркфлоу: ~/n8n-imports/ (импорт через UI n8n)     ║"
fi
if echo "$CHOICES" | grep -q "5"; then
echo "║  Боты: ~/freemind-bots/ (см. README в каждой папке)     ║"
fi
if echo "$CHOICES" | grep -q "6"; then
echo "║  MCP: ~/.mcp.json.freemind → переименуй в .mcp.json     ║"
fi

echo "║                                                          ║"
echo "║  📦 Установленные скиллы (базовый пакет):               ║"
echo "║                                                          ║"
echo "║  Автоматизация:  n8n-automation, prompt-engeneering,    ║"
echo "║                  claude-to-im, tg-notify, slack          ║"
echo "║  Контент:        tg-audit, carousel-generator,           ║"
echo "║                  youtube-summary, openai-image-gen        ║"
echo "║  Исследования:   Deep-web-search, last30days,            ║"
echo "║                  brand-analysis, research-design,        ║"
echo "║                  qual-research-design, segmentation       ║"
echo "║  Разработка:     coding-agent, agent-team-orchestration, ║"
echo "║                  agent-browser, github, code-god         ║"
echo "║  Файлы:          docx, xlsx, nano-pdf                    ║"
echo "║  Память:         mem0, obsidian, whisper, violin,        ║"
echo "║                  context-lifecycle, self-improvement      ║"
echo "║  Скиллы:         skill-creator, skill-conductor          ║"
echo "║                                                          ║"
echo "║  Клуб: t.me/free_mind_rus                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

#!/bin/bash
# FreeMind Skills — Полный пакет (базовый + 1000 security/devops скиллов)
# Для разработчиков, DevOps, security-инженеров

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"

echo ""
echo "🔐 FreeMind Skills — Полный пакет"
echo "=================================="
echo ""

# Сначала ставим базовый пакет
echo "→ Устанавливаем базовый пакет..."
bash "$SCRIPT_DIR/install.sh"

# Добавляем security скиллы
echo ""
echo "→ Устанавливаем security/devops скиллы..."

SECURITY_DIR="$SCRIPT_DIR/skills-security"
count=0

# Claude Code
for skill in "$SECURITY_DIR"/*/; do
  name=$(basename "$skill")
  cp -r "$skill" "$CLAUDE_SKILLS/$name"
  count=$((count+1))
done
echo "✅ Claude Code: +$count security скиллов"

# Codex
if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
  mkdir -p "$CODEX_SKILLS"
  for skill in "$SECURITY_DIR"/*/; do
    cp -r "$skill" "$CODEX_SKILLS/"
  done
  echo "✅ Codex: +$count security скиллов"
fi

total=$((32 + count))
echo ""
echo "=================================="
echo "🎉 Полный пакет установлен! Всего: ~$total скиллов"
echo ""
echo "Перезапусти Claude Code для активации."
echo ""

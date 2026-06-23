#!/bin/bash
# Универсальный вызов OmniRoute для code-god
# Использование: ./call_omniroute.sh <role> <prompt_file_or_string>
#
# Роли:
#   architect  → kiro/claude-sonnet-4.5
#   coder      → qwen/qwen3-coder-plus
#   reviewer   → kiro/claude-sonnet-4.5
#   fixer      → qwen/qwen3-coder-flash

OMNIROUTE_URL="http://localhost:20128/v1/chat/completions"
OMNIROUTE_KEY="sk-864f3a169c7f362a-842421-02901aea"

ROLE="${1:-coder}"
PROMPT="$2"

case "$ROLE" in
  architect|reviewer)
    MODEL="kiro/claude-sonnet-4.5"
    ;;
  coder)
    MODEL="qwen/qwen3-coder-plus"
    ;;
  fixer)
    MODEL="qwen/qwen3-coder-flash"
    ;;
  *)
    # Если передана модель напрямую
    MODEL="$ROLE"
    ;;
esac

# Если второй аргумент — файл, читаем его
if [ -f "$PROMPT" ]; then
  PROMPT=$(cat "$PROMPT")
fi

if [ -z "$PROMPT" ]; then
  echo "Usage: $0 <role|model> <prompt_or_file>"
  echo "Roles: architect, coder, reviewer, fixer"
  exit 1
fi

echo ">>> Model: $MODEL" >&2
echo "" >&2

# Экранируем промпт для JSON
PROMPT_ESCAPED=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$PROMPT")

curl -s "$OMNIROUTE_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OMNIROUTE_KEY" \
  -d "{\"model\":\"$MODEL\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":$PROMPT_ESCAPED}]}" \
  | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"

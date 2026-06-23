#!/bin/bash
# Full pipeline: Архитектор → Кодер → Ревьюер
# Использование: ./code_pipeline.sh "описание задачи" "стек (например: Python 3.11, FastAPI)"
#
# Результаты сохраняются в /tmp/code_pipeline_<timestamp>/

OMNIROUTE_URL="http://localhost:20128/v1/chat/completions"
OMNIROUTE_KEY="sk-864f3a169c7f362a-842421-02901aea"

TASK="${1}"
STACK="${2:-Python}"
OUT_DIR="/tmp/code_pipeline_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUT_DIR"

if [ -z "$TASK" ]; then
  echo "Usage: $0 \"описание задачи\" \"стек\""
  exit 1
fi

# --- Вспомогательная функция ---
call_model() {
  local model="$1"
  local prompt="$2"
  local prompt_escaped
  prompt_escaped=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$prompt")

  curl -s "$OMNIROUTE_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OMNIROUTE_KEY" \
    -d "{\"model\":\"$model\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":$prompt_escaped}]}" \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
}

echo "======================================"
echo " Code God Pipeline"
echo " Task: $TASK"
echo " Stack: $STACK"
echo " Output: $OUT_DIR"
echo "======================================"

# --- Шаг 1: Архитектор ---
echo ""
echo "[1/3] Архитектор (kiro/claude-sonnet-4.5)..."

ARCH_PROMPT="Ты senior software architect. Задача: $TASK

Контекст проекта: $STACK

Выдай:
1. Декомпозицию на модули/функции
2. Интерфейсы и типы данных
3. Зависимости и порядок реализации
4. Потенциальные риски

Без кода — только архитектура и план."

ARCH_RESULT=$(call_model "kiro/claude-sonnet-4.5" "$ARCH_PROMPT")
echo "$ARCH_RESULT" | tee "$OUT_DIR/1_architecture.md"

# --- Шаг 2: Кодер ---
echo ""
echo "[2/3] Кодер (qwen/qwen3-coder-plus)..."

CODER_PROMPT="Ты опытный разработчик. Реализуй следующее:

Задача: $TASK
Стек: $STACK

Архитектура от архитектора:
$ARCH_RESULT

Требования:
- Рабочий, production-ready код
- Комментарии на сложных местах
- Обработка ошибок
- Без заглушек и TODO (если не оговорено)

Верни только код с минимальными пояснениями."

CODE_RESULT=$(call_model "qwen/qwen3-coder-plus" "$CODER_PROMPT")
echo "$CODE_RESULT" | tee "$OUT_DIR/2_implementation.md"

# --- Шаг 3: Ревьюер ---
echo ""
echo "[3/3] Ревьюер (kiro/claude-sonnet-4.5)..."

REVIEW_PROMPT="Ты senior код-ревьюер. Проверь код:

$CODE_RESULT

Найди:
1. Баги и логические ошибки
2. Проблемы безопасности
3. Проблемы производительности
4. Нарушения best practices

Для каждой проблемы: severity (critical/major/minor), строка, описание, fix.
Если всё ок — скажи 'LGTM' с кратким обоснованием."

REVIEW_RESULT=$(call_model "kiro/claude-sonnet-4.5" "$REVIEW_PROMPT")
echo "$REVIEW_RESULT" | tee "$OUT_DIR/3_review.md"

echo ""
echo "======================================"
echo " Pipeline завершён. Файлы в: $OUT_DIR"
echo "======================================"

#!/bin/bash
# Офлайн-транскрибация Whisper.
# Просто дважды кликните по этому файлу в Finder.

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR" || exit 1
ROOT="$(cd "$APP_DIR/.." && pwd)"

# --- ищем Python из виртуального окружения проекта ---
PY=""
for cand in \
  "$APP_DIR/.venv/bin/python" \
  "$ROOT/_venv/bin/python" \
  "$ROOT/.venv/bin/python" \
  "$ROOT/venv/bin/python" \
  "$APP_DIR/venv/bin/python"
do
  if [ -x "$cand" ]; then PY="$cand"; break; fi
done

if [ -z "$PY" ]; then
  PY="$(command -v python3 2>/dev/null || true)"
fi

if [ -z "$PY" ]; then
  echo "Не найден Python 3."
  echo "Восстановите виртуальное окружение _venv или установите Python 3."
  read -n 1 -s -r -p "Нажмите любую клавишу, чтобы закрыть…"
  exit 1
fi

# --- полностью офлайн: не обращаемся к HuggingFace ---
export HF_HUB_OFFLINE=1

# --- проверяем, что окружение готово ---
if ! "$PY" -c "import mlx_whisper" >/dev/null 2>&1; then
  echo "Выбранный Python: $PY"
  echo "В нём нет библиотеки mlx_whisper."
  echo
  echo "Установите её так:"
  echo "  \"$PY\" -m pip install mlx-whisper"
  read -n 1 -s -r -p "Нажмите любую клавишу, чтобы закрыть…"
  exit 1
fi

exec "$PY" "$APP_DIR/server.py"

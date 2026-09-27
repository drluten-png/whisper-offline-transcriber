#!/bin/bash
# Подготовка окружения. Запускается один раз после скачивания репозитория.
set -u
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR" || exit 1

echo "=================================================="
echo "  Подготовка: Whisper — офлайн-транскрибация"
echo "=================================================="

ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
  echo
  echo "  ВНИМАНИЕ: приложение использует MLX и работает только на Mac"
  echo "  с процессором Apple Silicon (M1/M2/M3/M4). На «$ARCH» оно не запустится."
  echo
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Не найден ffmpeg. Установите его и запустите снова:"
  echo "    brew install ffmpeg"
  exit 1
fi

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "Не найден python3. Установите: brew install python@3.12"
  exit 1
fi
echo "Python: $PY"

echo
echo "1/3  Создаю окружение .venv…"
"$PY" -m venv .venv || { echo "Не удалось создать окружение"; exit 1; }

echo "2/3  Ставлю библиотеки (mlx-whisper, onnxruntime)…"
.venv/bin/python -m pip install --upgrade pip >/dev/null
.venv/bin/python -m pip install mlx-whisper onnxruntime || {
  echo "Не удалось установить библиотеки"; exit 1; }

echo "3/3  Скачиваю модель распознавания (~450 МБ, разово, нужен интернет)…"
.venv/bin/python - <<'PY' || echo "! Модель скачать не удалось — приложение попробует ещё раз при первом запуске"
from huggingface_hub import snapshot_download
snapshot_download("mlx-community/whisper-large-v3-turbo-q4")
print("     модель загружена")
PY

echo
echo "Проверка:"
.venv/bin/python - <<'PY' || true
import mlx_whisper, onnxruntime
print("     mlx-whisper и onnxruntime на месте")
PY

echo
echo "Готово. Дальше просто запускайте «Запустить Whisper.command»."

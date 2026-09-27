# AGENTS.md

Файл для ИИ-агентов и разработчиков. Коротко: что это за проект, что **нельзя
ломать**, как запускать и что именно нужно заменить, чтобы работало на Windows.

## Что это

Локальное приложение для расшифровки аудио и видео в текст. Один процесс на Python
поднимает HTTP-сервер на `127.0.0.1`, раздаёт веб-интерфейс и обрабатывает очередь
задач: `ffmpeg` вырезает звук → определение речи (VAD) → распознавание → запись `.txt`.

Сейчас распознавание работает на **MLX** (Apple Silicon). Всё остальное —
кроссплатформенное.

## Жёсткие правила

1. **Офлайн.** Единственный сетевой вызов — скачивание модели по явному действию
   пользователя. Не добавляйте телеметрию, CDN, внешние шрифты и запросы «на всякий случай».
2. **Только локальная привязка.** Сервер слушает `127.0.0.1` и проверяет `Host`/`Origin`.
   Не меняйте это без явного запроса — приложение без пароля.
3. **Конфиденциальность.** Записи и расшифровки не должны попадать в репозиторий.
   Папки `data/` и `output/` уже в `.gitignore` — не убирайте их оттуда.
4. **Модели в репозиторий не коммитить.** `setup.sh` скачивает их отдельно.

## Карта кода (server.py)

| Что | Где искать |
|---|---|
| Настройки и переменные окружения | начало файла, `_int_env` / `_float_env` |
| Извлечение звука из файла | `_run_ffmpeg_extract`, `extract_chunk`, `audio_track_indices` |
| Определение речи (Silero VAD) | `vad_probs`, `speech_intervals`, `chunk_has_speech`, `snap_to_silence` |
| Границы кусков по паузам | `find_chunk_boundaries` |
| Распознавание | `transcribe_chunk` ← **единственное место, привязанное к MLX** |
| Чистка текста | `is_hallucination`, `dedup_segments`, `apply_glossary` |
| Запись результата | `write_txt` (пишет через `.part` и `os.replace`) |
| Очередь и надёжность | `worker`, `watchdog`, `_run_job_safe`, `persist_jobs` |
| HTTP | класс `Handler` (эндпоинты `/api/...`) |

## Контракты, которые нельзя менять

**Формат сегмента.** Между распознаванием и записью сегмент — словарь ровно с такими
ключами (остальной код рассчитывает на них):

```python
{"start": float, "end": float, "text": str,
 "avg_logprob": float | None, "compression_ratio": float | None}
```

`start`/`end` — секунды **от начала всего файла** (смещение куска прибавляется при
склейке). `avg_logprob` и `compression_ratio` нужны фильтру галлюцинаций.

**Файлы в `data/`** (формат важен для совместимости): `glossary.json`, `jobs.json`,
`settings.json`, `renames.json`, `port.txt`, `backup/`.

**Веб-API:** `/api/info`, `/api/jobs`, `/api/upload`, `/api/download`, `/api/retry`,
`/api/reveal`, `/api/rename`, `/api/glossary`, `/api/apply-glossary`, `/api/models`,
`/api/models/select`, `/api/models/download`, `/api/open-output`. Интерфейс в
`app.js` зависит от их полей — при изменениях правьте обе стороны.

## Запуск на macOS (текущая версия)

```bash
brew install ffmpeg
bash setup.sh          # создаст .venv, поставит mlx-whisper и onnxruntime, скачает модель
./"Запустить Whisper.command"
```

## Запуск на Windows

### Почему «просто запустить» не получится

1. **MLX существует только для Apple Silicon.** На Windows пакет `mlx-whisper`
   не устанавливается, поэтому импорт на строке `import mlx_whisper` падает —
   сервер поднимется, но каждая задача завершится ошибкой.
2. **Лаунчер `Запустить Whisper.command` — это shell-скрипт** macOS; Windows его не выполнит.
3. **Защита от двойного запуска** использует `fcntl` (только macOS/Linux).
4. **`os.sysconf`** (показатель свободной памяти) в Windows отсутствует — вернётся `None`,
   индикатор памяти просто скроется. Не критично, но лучше заменить.

Всё остальное — `ffmpeg`, `onnxruntime` + `models/silero_vad.onnx`, `wave`, `numpy`,
HTTP-сервер, интерфейс, словарь, журнал задач — работает на Windows без изменений.

### Что заменить (по шагам)

**1. Бэкенд распознавания.** Поставить `faster-whisper` (CTranslate2, работает на CPU):

```bash
pip install faster-whisper
```

В `server.py` заменить импорт (`import mlx_whisper`) и тело `transcribe_chunk`:

```python
from faster_whisper import WhisperModel

def _load_model(model_id: str):
    return WhisperModel(model_id, device="cpu", compute_type="int8")

# внутри transcribe_chunk:
segments, info = model.transcribe(
    chunk_path, language=LANGUAGE, task="transcribe",
    condition_on_previous_text=False,
    initial_prompt=prompt or None,
    temperature=[0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    vad_filter=False,           # VAD у нас свой, см. ниже
    beam_size=5,
)
out = [{"start": s.start, "end": s.end, "text": (s.text or "").strip(),
        "avg_logprob": getattr(s, "avg_logprob", None),
        "compression_ratio": getattr(s, "compression_ratio", None)}
       for s in segments]         # segments — генератор, нужен list()
```

Проверить, что `faster_whisper.Segment` отдаёт `avg_logprob` и `compression_ratio`;
если нет — подставить `None` (фильтр галлюцинаций продолжит работать по фразам).

**2. Каталог моделей.** В `MODEL_CATALOG` заменить идентификаторы MLX на модели
CTranslate2 (например `deepdml/faster-whisper-large-v3-turbo-ct2`), а `MODEL` по
умолчанию — на нужную. Функция `model_installed()` проверяет кеш HuggingFace и
работает с любым репозиторием, менять её не нужно.

**3. Сброс модели при переключении.** `set_current_model()` чистит
`mlx_whisper.transcribe.ModelHolder` — заменить на сброс своего кешированного
объекта `WhisperModel`, иначе при смене модели останется старая.

**4. Лаунчер.** Добавить `start.bat` (имя латиницей — с кириллицей в `.bat` бывают
проблемы с кодовой страницей):

```bat
@echo off
chcp 65001 >nul
cd /d "%~dp0"
set PYTHONUTF8=1
set HF_HUB_OFFLINE=1
if exist ".venv\Scripts\python.exe" (set PY=.venv\Scripts\python.exe) else (set PY=python)
"%PY%" server.py
```

**5. Установщик.** Добавить `setup.ps1` по образцу `setup.sh`:
проверка `python`, `python -m venv .venv`, `pip install faster-whisper onnxruntime`,
скачивание модели, подсказка про `winget install Gyan.FFmpeg`.

**6. Защита от двойного запуска.** `fcntl` заменить на кроссплатформенный приём:
попытка занять локальный порт (`socket.bind`) — если занят, значит приложение уже
запущено. Это заодно убирает гонку в `find_port`.

**7. Показатель памяти.** Вместо `os.sysconf` использовать `ctypes` →
`GlobalMemoryStatusEx`, либо `psutil.virtual_memory()`.

### Чего НЕ нужно переписывать

Извлечение звука и работа с дорожками, Silero VAD, границы кусков по паузам,
склейка с перекрытием, дедупликация, фильтр галлюцинаций, словарь терминов,
атомарная запись результата, журнал задач, все HTTP-эндпоинты и весь фронтенд.

## Как проверять

1. **Без GPU и без модели.** Подменить бэкенд заглушкой: положить свой модуль
   `mlx_whisper.py` рядом и запускать сервер с `PYTHONPATH`, где `transcribe()`
   возвращает фиктивные сегменты. Так проверяется весь конвейер (нарезка, фильтры,
   склейка, запись, API) за секунды:

   ```python
   # stub/mlx_whisper.py
   def transcribe(audio, **kwargs):
       return {"segments": [
           {"start": 0.0, "end": 2.0, "text": " Проверка связи.",
            "avg_logprob": -0.2, "compression_ratio": 1.5}]}
   ```
   ```bash
   PYTHONPATH=stub WHISPER_NO_BROWSER=1 python server.py
   ```

2. **Один короткий настоящий прогон** (5–15 секунд аудио) — что модель грузится,
   сегменты пишутся, шапка файла корректна.

3. **Проверка VAD.** Сделать файл «речь — 8 секунд тишины — речь» и убедиться, что
   пауза не уходит в распознавание, а граница куска попадает в тишину.

4. **Проверка стыков.** Взять запись длиннее двух кусков и убедиться, что нет
   повторов слов на границе и таймкоды идут по возрастанию.

## Стиль

- Интерфейс и сообщения — по-русски, понятным языком, без технического жаргона.
- Ошибки пользователю — человеческие («в файле нет звуковой дорожки»), технические
  подробности — отдельным полем `error_detail`.
- Ограничивайте ресурсы: приложение рассчитано на 8 ГБ памяти. Не держите в памяти
  больше одного куска аудио и удаляйте временные файлы сразу.
- Перед изменениями в конвейере прогоняйте тесты из «Как проверять».

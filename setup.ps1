# Подготовка окружения на Windows. Запускается один раз.
# Правый клик по файлу -> «Выполнить с помощью PowerShell».
# Если PowerShell ругается на политику запуска, выполните в терминале:
#   powershell -ExecutionPolicy Bypass -File setup.ps1

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

Write-Host "=================================================="
Write-Host "  Подготовка: Whisper - офлайн-транскрибация"
Write-Host "=================================================="
Write-Host ""

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "Не найден ffmpeg. Установите его и запустите снова:" -ForegroundColor Yellow
    Write-Host "    winget install Gyan.FFmpeg"
    Write-Host "(после установки перезапустите терминал)"
    exit 1
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Не найден python. Установите его и запустите снова:" -ForegroundColor Yellow
    Write-Host "    winget install Python.Python.3.12"
    exit 1
}

Write-Host "1/3  Создаю окружение .venv…"
python -m venv .venv

Write-Host "2/3  Ставлю библиотеки (faster-whisper, onnxruntime)…"
& .\.venv\Scripts\python.exe -m pip install --upgrade pip | Out-Null
& .\.venv\Scripts\python.exe -m pip install faster-whisper onnxruntime

Write-Host "3/3  Скачиваю модель распознавания (около 1.5 ГБ, разово, нужен интернет)…"
$env:HF_HUB_OFFLINE = "0"
& .\.venv\Scripts\python.exe -c "from huggingface_hub import snapshot_download; snapshot_download('deepdml/faster-whisper-large-v3-turbo-ct2')"

Write-Host ""
Write-Host "Проверка:" -ForegroundColor Cyan
& .\.venv\Scripts\python.exe -c "import faster_whisper, onnxruntime; print('     faster-whisper и onnxruntime на месте')"

Write-Host ""
Write-Host "Готово. Дальше запускайте start.bat (двойной клик)." -ForegroundColor Green
Write-Host ""
pause

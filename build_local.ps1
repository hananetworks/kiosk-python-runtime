# build_local.ps1
$ErrorActionPreference = "Stop"

# ★★★ [핵심] 목표 경로 설정 ★★★
$TargetBase = "C:\Users\hana_us04\AppData\Local\MyKiosk"
$EnvName = "$TargetBase\python-env"
$ZipName = "$TargetBase\python-env-full.zip"

Write-Host " [Local Build] Target: $TargetBase" -ForegroundColor Cyan

# =========================================================
# 0. 프로세스 강제 종료
# =========================================================
Write-Host " Killing existing processes..." -ForegroundColor Magenta
Get-Process "stt_server", "kiosk_python", "python", "api_server" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 1. 폴더 정리
if (Test-Path $EnvName) {
    Write-Host "⚠ Cleaning up old python-env..." -ForegroundColor Yellow
    Remove-Item $EnvName -Recurse -Force
}
New-Item -ItemType Directory -Path $EnvName -Force | Out-Null

# 2. 파이썬 다운로드
Write-Host " Downloading Python 3.11.9..."
$Url = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
$TempZip = "$TargetBase\python_temp.zip"
Invoke-WebRequest -Uri $Url -OutFile $TempZip
Expand-Archive -Path $TempZip -DestinationPath $EnvName -Force
Remove-Item $TempZip -Force

# 실행 파일 이름 변경
Rename-Item -Path "$EnvName\python.exe" -NewName "kiosk_python.exe"
$PythonExe = "$EnvName\kiosk_python.exe"
$PthFile = "$EnvName\python311._pth"
(Get-Content $PthFile) -replace '#import site', 'import site' | Set-Content $PthFile

# 3. 라이브러리 설치
Write-Host "📦 Installing PIP..."
$GetPip = "$TargetBase\get-pip.py"
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $GetPip
& $PythonExe $GetPip --no-warn-script-location
Remove-Item $GetPip -Force

Write-Host "📦 Installing libraries (requirements.txt)..."
& $PythonExe -m pip install -r requirements.txt --no-warn-script-location --extra-index-url https://download.pytorch.org/whl/cpu

Write-Host "📦 Installing critical runtime dependencies..."
& $PythonExe -m pip install `
    torch==2.4.1+cpu `
    torchaudio==2.4.1+cpu `
    fastapi `
    "uvicorn[standard]" `
    google-cloud-speech `
    numpy `
    psutil `
    websockets `
    openvino `
    openvino-genai `
    sherpa-onnx==1.12.26 `
    --no-warn-script-location `
    --extra-index-url https://download.pytorch.org/whl/cpu

# 4. MeCab 폴더 보정
Write-Host "🔧 Fixing MeCab folders..."
$SitePackages = "$EnvName\Lib\site-packages"
$UnidicLite = "$SitePackages\unidic_lite"
$Unidic = "$SitePackages\unidic"
if (Test-Path $UnidicLite) {
    if (-not (Test-Path $Unidic)) {
        Copy-Item -Path $UnidicLite -Destination $Unidic -Recurse -Force
    }
}

# =========================================================
# 5. [TTS] 모델 다운로드 (Piper & Sherpa)
# =========================================================
Write-Host "️ Downloading TTS models..."
$TTSModelDir = "$EnvName\tts_models"
New-Item -ItemType Directory -Path "$TTSModelDir\piper_models" -Force | Out-Null
New-Item -ItemType Directory -Path "$TTSModelDir\sherpa_models\vits-mms-tgl" -Force | Out-Null

# [영어 로그로 변경됨]
$TTSDownloadCode = @"
import os, shutil, sys
try:
    from huggingface_hub import hf_hub_download
except ImportError:
    sys.exit(1)

# Piper Models
piper_dir = r'$TTSModelDir\piper_models'
piper_files = [
    ('vi/vi_VN/vivos/x_low/vi_VN-vivos-x_low.onnx', 'vi_VN-vivos-x_low.onnx'),
    ('vi/vi_VN/vivos/x_low/vi_VN-vivos-x_low.onnx.json', 'vi_VN-vivos-x_low.onnx.json'),
    ('es/es_ES/davefx/medium/es_ES-davefx-medium.onnx', 'es_ES-davefx-medium.onnx'),
    ('es/es_ES/davefx/medium/es_ES-davefx-medium.onnx.json', 'es_ES-davefx-medium.onnx.json'),
    ('fr/fr_FR/upmc/medium/fr_FR-upmc-medium.onnx', 'fr_FR-upmc-medium.onnx'),
    ('fr/fr_FR/upmc/medium/fr_FR-upmc-medium.onnx.json', 'fr_FR-upmc-medium.onnx.json')
]
for repo, fname in piper_files:
    try:
        p = hf_hub_download(repo_id='rhasspy/piper-voices', filename=repo)
        shutil.copy(p, os.path.join(piper_dir, fname))
        print(f'   [TTS] Downloaded: {fname}')
    except Exception as e:
        print(f'   [TTS] Fail: {fname} {e}')

# Sherpa TTS (Tagalog)
sherpa_dir = r'$TTSModelDir\sherpa_models\vits-mms-tgl'
for f in ['tgl/tokens.txt', 'tgl/model.onnx']:
    try:
        p = hf_hub_download(repo_id='willwade/mms-tts-multilingual-models-onnx', filename=f)
        shutil.copy(p, os.path.join(sherpa_dir, f.split('/')[-1]))
    except Exception:
        pass
"@
& $PythonExe -c $TTSDownloadCode

# =========================================================
# 6. [STT] 모델 다운로드 (Sherpa + Vosk)
# =========================================================
Write-Host "⬇️ Downloading STT models..."

# [영어 로그로 변경됨 - 인코딩 에러 방지]
$STTDownloadCode = @"
import os
import sys
import urllib.request
import tarfile
import zipfile
import shutil
import time

# Force UTF-8 for output
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

MODELS_DIR = "models"
if not os.path.exists(MODELS_DIR):
    os.makedirs(MODELS_DIR)

print(f"[STT] Models Path: {os.path.abspath(MODELS_DIR)}")

# 1. Sherpa Models
SHERPA_MODELS = {
    "sherpa-korean": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-korean-2024-06-16.tar.bz2",
    "sherpa-bilingual": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2",
}

for name, url in SHERPA_MODELS.items():
    filename = url.split('/')[-1]
    filepath = os.path.join(MODELS_DIR, filename)
    folder_name = filename.replace('.tar.bz2', '')

    if os.path.exists(os.path.join(MODELS_DIR, folder_name)):
        print(f"   [SKIP] {name} already exists.")
        continue

    print(f"   [Download] {name}...")
    try:
        urllib.request.urlretrieve(url, filepath)
        print(f"   [Extract] Extracting {name}...")
        with tarfile.open(filepath, 'r:bz2') as tar:
            tar.extractall(MODELS_DIR)
        os.remove(filepath)
        print("   -> Done")
    except Exception as e:
        print(f"   [ERROR] {name} failed: {e}")

# 2. Vosk Model
VOSK_URL = "https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip"
VOSK_ZIP = os.path.join(MODELS_DIR, "vosk-model-small-ja-0.22.zip")
VOSK_DIR_NAME = "vosk-model-small-ja-0.22"

if not os.path.exists(os.path.join(MODELS_DIR, VOSK_DIR_NAME)):
    print(f"   [Download] Vosk Japanese...")
    try:
        urllib.request.urlretrieve(VOSK_URL, VOSK_ZIP)
        print(f"   [Extract] Extracting Vosk...")
        with zipfile.ZipFile(VOSK_ZIP, 'r') as zip_ref:
            zip_ref.extractall(MODELS_DIR)
        os.remove(VOSK_ZIP)
        print("   -> Done")
    except Exception as e:
        print(f"   [ERROR] Vosk failed: {e}")
else:
    print(f"   [SKIP] Vosk Japanese already exists.")

print("[STT] All models ready.")
time.sleep(1) # Wait for file handles to release
"@

$TempSTTInstaller = "$EnvName\install_stt_models.py"
# [중요] UTF8 인코딩 명시
Set-Content -Path $TempSTTInstaller -Value $STTDownloadCode -Encoding UTF8

Write-Host "   -> Running model downloader..."
Push-Location $EnvName
& .\kiosk_python.exe install_stt_models.py
Pop-Location

Remove-Item $TempSTTInstaller -Force

# 6.5 [OpenVINO STT] 엔진/모델 복사
Write-Host "🎤 Copying OpenVINO STT engine..."
Copy-Item -Path ".\kiosk_stt.py" -Destination "$EnvName\kiosk_stt.py" -Force
New-Item -ItemType Directory -Path "$EnvName\models\whisper-small-int8-ov" -Force | Out-Null
Copy-Item -Path ".\models\whisper-small-int8-ov\*" -Destination "$EnvName\models\whisper-small-int8-ov" -Recurse -Force

# 7. 정리 및 압축
Write-Host "🧹 Cleaning cache..."
Get-ChildItem -Path "$EnvName" -Include "__pycache__" -Recurse -Directory | Remove-Item -Recurse -Force

Write-Host "🤐 Zipping ($ZipName)..."
if (Test-Path $ZipName) { Remove-Item $ZipName -Force }
# 압축 전 잠시 대기
Start-Sleep -Seconds 2
Compress-Archive -Path $EnvName -DestinationPath $ZipName -Force

Write-Host "✅ [BUILD COMPLETE] TTS & STT Environment Ready!" -ForegroundColor Green

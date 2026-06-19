param(
    [string]$ReuseSttAssetZip = "",
    [string]$ReuseTtsCoreAssetZip = ""
)

$ErrorActionPreference = "Stop"

$EnvName = "python-env"
if (Test-Path $EnvName) { Remove-Item $EnvName -Recurse -Force }
New-Item -ItemType Directory -Path $EnvName -Force | Out-Null

$PythonZipUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
Invoke-WebRequest -Uri $PythonZipUrl -OutFile "python.zip"
Expand-Archive -Path "python.zip" -DestinationPath $EnvName -Force
Remove-Item "python.zip" -Force

Rename-Item -Path "$EnvName\python.exe" -NewName "kiosk_python.exe"
$PythonExe = "$EnvName\kiosk_python.exe"

$PthFile = "$EnvName\python311._pth"
(Get-Content $PthFile) -replace '#import site', 'import site' | Set-Content $PthFile

Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "get-pip.py"
& $PythonExe get-pip.py --no-warn-script-location
Remove-Item "get-pip.py" -Force

Write-Host "Installing libraries from requirements.txt..."
& $PythonExe -m pip install -r requirements.txt --no-warn-script-location --extra-index-url https://download.pytorch.org/whl/cpu

Write-Host "Installing HailoRT local wheel..."
$HailoWheel = Get-ChildItem -Path "libs" -Filter "hailort-*.whl" | Select-Object -First 1
if ($HailoWheel) {
    Write-Host "Found wheel: $($HailoWheel.Name)"
    & $PythonExe -m pip install $HailoWheel.FullName --no-warn-script-location
} else {
    Write-Error "FATAL: HailoRT .whl file not found in 'libs/' directory."
    exit 1
}

if ($LASTEXITCODE -ne 0) { throw "Pip install failed" }

$PyWin32Dir = "$EnvName\Lib\site-packages\pywin32_system32"
if (Test-Path $PyWin32Dir) {
    Get-ChildItem -Path $PyWin32Dir -Filter "*.dll" | Copy-Item -Destination $EnvName -Force
}

Write-Host "Fixing MeCab dictionary path..."
$SitePackages = "$EnvName\Lib\site-packages"
$UnidicLite = "$SitePackages\unidic_lite"
$Unidic = "$SitePackages\unidic"
if (Test-Path $UnidicLite) {
    if (-not (Test-Path $Unidic)) {
        Copy-Item -Path $UnidicLite -Destination $Unidic -Recurse -Force
        Write-Host "  -> Copied 'unidic_lite' to 'unidic' successfully."
    }
}

if ((Test-Path $ReuseSttAssetZip) -and (Test-Path $ReuseTtsCoreAssetZip)) {
    Write-Host "Reusing speech assets from previous release packages..."
    $ReuseDir = ".runtime-reuse"
    if (Test-Path $ReuseDir) { Remove-Item $ReuseDir -Recurse -Force }
    New-Item -ItemType Directory -Path $ReuseDir -Force | Out-Null

    $STTModelDir = Join-Path $EnvName "models"
    New-Item -ItemType Directory -Path $STTModelDir -Force | Out-Null
    7z x $ReuseSttAssetZip "-o$STTModelDir" -y | Out-Null

    $TtsExtractDir = Join-Path $ReuseDir "tts-core"
    New-Item -ItemType Directory -Path $TtsExtractDir -Force | Out-Null
    7z x $ReuseTtsCoreAssetZip "-o$TtsExtractDir" -y | Out-Null

    $TtsModelDir = Join-Path $EnvName "tts_models"
    New-Item -ItemType Directory -Path $TtsModelDir -Force | Out-Null
    Copy-Item -Path "$TtsExtractDir\piper_models" -Destination "$TtsModelDir\piper_models" -Recurse -Force
    Copy-Item -Path "$TtsExtractDir\sherpa_models" -Destination "$TtsModelDir\sherpa_models" -Recurse -Force
} else {
    .\scripts\prepare-speech-assets.ps1 -PythonExe $PythonExe -EnvName $EnvName
}

Get-ChildItem -Path $EnvName -Include "__pycache__" -Recurse -Directory | Remove-Item -Recurse -Force

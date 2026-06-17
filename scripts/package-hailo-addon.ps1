$ErrorActionPreference = "Stop"

$HailoAssetDir = "hailo-assets-package"
if (Test-Path $HailoAssetDir) { Remove-Item $HailoAssetDir -Recurse -Force }
New-Item -ItemType Directory -Path "$HailoAssetDir\models" -Force | Out-Null

$ArchiveInputs = @("models")
$HailoFiles = @(
    "models\small-whisper-encoder-5s.hef",
    "models\small-whisper-decoder-5s-seq-24.hef"
)

foreach ($file in $HailoFiles) {
    if (Test-Path $file) {
        Copy-Item -Path $file -Destination "$HailoAssetDir\models" -Force
    }
}

$QwenHef = "Qwen2.5-1.5B-Instruct.hef"
if (Test-Path $QwenHef) {
    Copy-Item -Path $QwenHef -Destination $HailoAssetDir -Force
    $ArchiveInputs += "Qwen2.5-1.5B-Instruct.hef"
} else {
    Write-Host "Qwen2.5-1.5B-Instruct.hef not found. Building Hailo addon without it."
}

Push-Location $HailoAssetDir
7z a -mx=9 "..\hailo-addon.zip" @ArchiveInputs
Pop-Location

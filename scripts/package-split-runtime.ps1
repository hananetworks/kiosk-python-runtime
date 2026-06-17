$ErrorActionPreference = "Stop"

$EnginePackageDir = "python-engine"
if (Test-Path $EnginePackageDir) { Remove-Item $EnginePackageDir -Recurse -Force }
Copy-Item -Path "python-env" -Destination $EnginePackageDir -Recurse -Force
7z a -mx=9 python-engine.zip $EnginePackageDir

Push-Location "models"
7z a -mx=9 "..\stt-assets.zip" "whisper-small-int8-ov"
Pop-Location

Push-Location "tts-assets-package"
7z a -mx=9 "..\tts-assets.zip" "piper_models" "sherpa_models" "huggingface" "nltk_data"
Pop-Location

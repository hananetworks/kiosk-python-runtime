$ErrorActionPreference = "Stop"

Write-Host "Packaging engine runtime..."
$EnginePackageDir = "python-engine"
if (Test-Path $EnginePackageDir) { Remove-Item $EnginePackageDir -Recurse -Force }
Copy-Item -Path "python-env" -Destination $EnginePackageDir -Recurse -Force
7z a -mx=9 python-engine.zip $EnginePackageDir

Write-Host "Packaging STT assets..."
Push-Location "models"
7z a -mx=9 "..\stt-assets.zip" "whisper-small-int8-ov"
Pop-Location

Write-Host "Packaging TTS assets..."
Push-Location "tts-assets-package"
7z a -mx=3 "..\tts-core-assets.zip" "piper_models" "sherpa_models" "nltk_data"
Pop-Location

$HubDir = "tts-assets-package\huggingface\hub"
$TtsPackages = @(
    @{ Name = "bert-base-uncased"; Dir = "models--bert-base-uncased"; Zip = "tts-hf-bert-base-uncased.zip" },
    @{ Name = "bert-base-multilingual-uncased"; Dir = "models--bert-base-multilingual-uncased"; Zip = "tts-hf-bert-base-multilingual-uncased.zip" },
    @{ Name = "bert-base-japanese-v3"; Dir = "models--tohoku-nlp--bert-base-japanese-v3"; Zip = "tts-hf-bert-base-japanese-v3.zip" },
    @{ Name = "melo-ko"; Dir = "models--myshell-ai--MeloTTS-Korean"; Zip = "tts-hf-melo-ko.zip" },
    @{ Name = "melo-en"; Dir = "models--myshell-ai--MeloTTS-English"; Zip = "tts-hf-melo-en.zip" },
    @{ Name = "melo-ja"; Dir = "models--myshell-ai--MeloTTS-Japanese"; Zip = "tts-hf-melo-ja.zip" },
    @{ Name = "melo-zh"; Dir = "models--myshell-ai--MeloTTS-Chinese"; Zip = "tts-hf-melo-zh.zip" }
)

Push-Location $HubDir
foreach ($package in $TtsPackages) {
    if (Test-Path $package.Dir) {
        Write-Host "Packaging TTS HF cache: $($package.Name)..."
        7z a -mx=1 "..\..\$($package.Zip)" $package.Dir
    } else {
        Write-Host "Skipping missing TTS HF cache: $($package.Dir)"
    }
}
Pop-Location

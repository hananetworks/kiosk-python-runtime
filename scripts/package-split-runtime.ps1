param(
    [switch]$SkipEnginePackage,
    [switch]$SkipSttPackage,
    [switch]$SkipTtsPackage
)

$ErrorActionPreference = "Stop"

Write-Host "Packaging engine runtime..."
if ($SkipEnginePackage) {
    Write-Host "Reusing previous python-engine.zip"
} else {
    if (Test-Path "python-engine.zip") { Remove-Item "python-engine.zip" -Force }
    Push-Location "python-env"
    7z a -mx=9 "..\python-engine.zip" "*" -xr!models -xr!tts_models
    Pop-Location
}

Write-Host "Packaging STT assets..."
if ($SkipSttPackage) {
    Write-Host "Reusing previous stt-assets.zip"
} else {
    Push-Location "models"
    7z a -mx=9 "..\stt-assets.zip" "whisper-small-int8-ov"
    Pop-Location
}

Write-Host "Packaging TTS assets..."
if ($SkipTtsPackage) {
    Write-Host "Reusing previous TTS asset packages"
} else {
    Push-Location "tts-assets-package"
    7z a -mx=3 "..\tts-core-assets.zip" "piper_models" "sherpa_models" "nltk_data"
    Pop-Location

    $HubDir = "tts-assets-package\huggingface\hub"
    $TtsPackages = @(
        @{ Name = "bert-base-uncased"; Dirs = @("models--google-bert--bert-base-uncased", "models--bert-base-uncased"); Zip = "tts-hf-bert-base-uncased.zip" },
        @{ Name = "bert-base-multilingual-uncased"; Dirs = @("models--google-bert--bert-base-multilingual-uncased", "models--bert-base-multilingual-uncased"); Zip = "tts-hf-bert-base-multilingual-uncased.zip" },
        @{ Name = "bert-base-japanese-v3"; Dirs = @("models--tohoku-nlp--bert-base-japanese-v3"); Zip = "tts-hf-bert-base-japanese-v3.zip" },
        @{ Name = "melo-ko"; Dirs = @("models--myshell-ai--MeloTTS-Korean"); Zip = "tts-hf-melo-ko.zip" },
        @{ Name = "melo-en"; Dirs = @("models--myshell-ai--MeloTTS-English"); Zip = "tts-hf-melo-en.zip" },
        @{ Name = "melo-ja"; Dirs = @("models--myshell-ai--MeloTTS-Japanese"); Zip = "tts-hf-melo-ja.zip" },
        @{ Name = "melo-zh"; Dirs = @("models--myshell-ai--MeloTTS-Chinese"); Zip = "tts-hf-melo-zh.zip" }
    )

    Push-Location $HubDir
    foreach ($package in $TtsPackages) {
        $sourceDir = $package.Dirs | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($sourceDir) {
            Write-Host "Packaging TTS HF cache: $($package.Name) from $sourceDir..."
            7z a -mx=1 "..\..\..\$($package.Zip)" $sourceDir
        } else {
            Write-Host "Skipping missing TTS HF cache: $($package.Dirs -join ', ')"
        }
    }
    Pop-Location
}

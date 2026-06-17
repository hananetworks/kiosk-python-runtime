$ErrorActionPreference = "Stop"

function Get-RequiredHash {
    param([string]$Path)

    return (Get-FileHash $Path -Algorithm SHA256).Hash
}

$releaseVersion = $env:GITHUB_REF_NAME
if ([string]::IsNullOrWhiteSpace($releaseVersion)) { $releaseVersion = "env-dev" }

$hashFull = Get-RequiredHash "python-env-full.zip"
$hashEngine = Get-RequiredHash "python-engine.zip"
$hashStt = Get-RequiredHash "stt-assets.zip"
$hashTts = Get-RequiredHash "tts-assets.zip"
$hashHailo = Get-RequiredHash "hailo-addon.zip"

@(
    "Full: $hashFull"
    "Engine: $hashEngine"
    "STT: $hashStt"
    "TTS: $hashTts"
    "HAILO: $hashHailo"
) | Set-Content -Encoding Ascii hash.txt

if ($env:PATCH_EXISTS -eq "true") {
    $hashPatch = Get-RequiredHash "patch.hdiff"
    "Patch: $hashPatch" | Add-Content -Encoding Ascii hash.txt
}

$manifest = @{
    manifestVersion = 1
    engineVersion = $releaseVersion
    sttVersion = $releaseVersion
    ttsVersion = $releaseVersion
    hailoVersion = $releaseVersion
    packages = @{
        engine = @{ required = $true; version = $releaseVersion; file = "python-engine.zip"; sha256 = $hashEngine; extractTo = "python-engine" }
        stt    = @{ required = $true; version = $releaseVersion; file = "stt-assets.zip"; sha256 = $hashStt; extractTo = "assets/stt" }
        tts    = @{ required = $true; version = $releaseVersion; file = "tts-assets.zip"; sha256 = $hashTts; extractTo = "assets/tts" }
        hailo  = @{ required = $false; version = $releaseVersion; file = "hailo-addon.zip"; sha256 = $hashHailo; extractTo = "assets/hailo" }
    }
}

$manifest | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 runtime-manifest.json

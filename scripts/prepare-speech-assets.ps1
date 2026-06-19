param(
    [Parameter(Mandatory = $true)]
    [string]$PythonExe,

    [Parameter(Mandatory = $true)]
    [string]$EnvName
)

$ErrorActionPreference = "Stop"

Write-Host "Downloading TTS Models..."
$ModelDir = Join-Path $EnvName "tts_models"
$TtsAssetDir = "tts-assets-package"
if (Test-Path $TtsAssetDir) { Remove-Item $TtsAssetDir -Recurse -Force }
New-Item -ItemType Directory -Path "$ModelDir\piper_models" -Force | Out-Null
New-Item -ItemType Directory -Path "$ModelDir\sherpa_models\vits-mms-tgl" -Force | Out-Null
New-Item -ItemType Directory -Path "$TtsAssetDir\huggingface\hub" -Force | Out-Null
New-Item -ItemType Directory -Path "$TtsAssetDir\nltk_data" -Force | Out-Null

& $PythonExe -c @"
import os, shutil, sys
try:
    from huggingface_hub import hf_hub_download, snapshot_download
    import nltk
except ImportError:
    print('required TTS download dependencies not found'); sys.exit(1)

piper_dir = r'$ModelDir\piper_models'
hf_home = r'$TtsAssetDir\huggingface'
hub_cache = os.path.join(hf_home, 'hub')
nltk_dir = r'$TtsAssetDir\nltk_data'
os.environ['HF_HOME'] = hf_home
os.environ['HUGGINGFACE_HUB_CACHE'] = hub_cache
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'

piper_files = [
    'vi/vi_VN/vivos/x_low/vi_VN-vivos-x_low.onnx',
    'vi/vi_VN/vivos/x_low/vi_VN-vivos-x_low.onnx.json',
    'es/es_ES/davefx/medium/es_ES-davefx-medium.onnx',
    'es/es_ES/davefx/medium/es_ES-davefx-medium.onnx.json',
    'fr/fr_FR/upmc/medium/fr_FR-upmc-medium.onnx',
    'fr/fr_FR/upmc/medium/fr_FR-upmc-medium.onnx.json'
]

print('Downloading Piper models...')
for fpath in piper_files:
    fname = fpath.split('/')[-1]
    try:
        hf_hub_download(repo_id='rhasspy/piper-voices', filename=fpath, local_dir=piper_dir, local_dir_use_symlinks=False)
        print(f' - OK: {fname}')
    except Exception:
        print(f' - FAIL: {fname}')

sherpa_dir = r'$ModelDir\sherpa_models\vits-mms-tgl'
sherpa_files = ['tgl/tokens.txt', 'tgl/model.onnx']

print('Downloading Sherpa models...')
for fpath in sherpa_files:
    fname = fpath.split('/')[-1]
    try:
        down_path = hf_hub_download(repo_id='willwade/mms-tts-multilingual-models-onnx', filename=fpath)
        shutil.copy(down_path, os.path.join(sherpa_dir, fname))
        print(f' - OK: {fname}')
    except Exception as e:
        print(f' - FAIL: {fname} ({e})')

hf_repos = [
    {
        'repo_id': 'google-bert/bert-base-uncased',
        'ignore_patterns': ['coreml/*', 'onnx/*', 'openvino/*', 'flax_model.msgpack', 'rust_model.ot', 'tf_model.h5']
    },
    {
        'repo_id': 'google-bert/bert-base-multilingual-uncased',
        'ignore_patterns': ['coreml/*', 'onnx/*', 'openvino/*', 'flax_model.msgpack', 'rust_model.ot', 'tf_model.h5']
    },
    {
        'repo_id': 'tohoku-nlp/bert-base-japanese-v3',
        'ignore_patterns': ['onnx/*', 'openvino/*', 'flax_model.msgpack', 'rust_model.ot', 'tf_model.h5']
    },
    { 'repo_id': 'myshell-ai/MeloTTS-Korean' },
    { 'repo_id': 'myshell-ai/MeloTTS-English' },
    { 'repo_id': 'myshell-ai/MeloTTS-Japanese' },
    { 'repo_id': 'myshell-ai/MeloTTS-Chinese' },
]

print('Downloading HuggingFace cache for MeloTTS...')
for repo in hf_repos:
    repo_id = repo['repo_id']
    kwargs = {'repo_id': repo_id, 'cache_dir': hub_cache}
    ignore_patterns = repo.get('ignore_patterns')
    if ignore_patterns:
        kwargs['ignore_patterns'] = ignore_patterns
    try:
        snapshot_download(**kwargs)
        print(f' - OK: {repo_id}')
    except Exception as e:
        print(f' - FAIL: {repo_id} ({e})')

print('Downloading NLTK resources...')
for resource_name in ['averaged_perceptron_tagger_eng', 'cmudict']:
    try:
        nltk.download(resource_name, download_dir=nltk_dir, quiet=True)
        print(f' - OK: {resource_name}')
    except Exception as e:
        print(f' - FAIL: {resource_name} ({e})')
"@

Copy-Item -Path "$ModelDir\piper_models" -Destination "$TtsAssetDir\piper_models" -Recurse -Force
Copy-Item -Path "$ModelDir\sherpa_models" -Destination "$TtsAssetDir\sherpa_models" -Recurse -Force

Write-Host "Setting up NPU STT Models..."
$STTModelDir = Join-Path $EnvName "models"
New-Item -ItemType Directory -Path $STTModelDir -Force | Out-Null

$OpenVinoModelDir = "models\whisper-small-int8-ov"
if (Test-Path $OpenVinoModelDir) {
    New-Item -ItemType Directory -Path "$STTModelDir\whisper-small-int8-ov" -Force | Out-Null
    Copy-Item -Path "$OpenVinoModelDir\*" -Destination "$STTModelDir\whisper-small-int8-ov" -Recurse -Force
    Write-Host "  -> Copied OpenVINO STT model assets: whisper-small-int8-ov"
} else {
    Write-Host "Warning: 'models\whisper-small-int8-ov' not found. Skipping OpenVINO model copy."
}

# kiosk-python-runtime

키오스크 런타임용 Python 환경과 런타임 자산을 빌드하고 GitHub Release로 배포하는 저장소입니다.

이 저장소에서 만드는 주요 산출물:

- `python-engine.zip`
- `stt-assets.zip`
- `tts-core-assets.zip`
- `tts-hf-*.zip`
- `hailo-addon.zip`
- `runtime-manifest.json`

## 기본 원칙

- 최종 배포는 항상 `env-v*` 태그 푸시로 합니다.
- STT/Hailo 실물 모델은 `runtime-models/` 아래만 수정하면 됩니다.
- TTS는 현재 두 방식이 공존합니다.
  - `runtime-models/tts/...`에 실물 모델을 넣으면 그 폴더를 우선 사용
  - 실물 모델이 없으면 `runtime-models/speech-assets.json` 기준으로 다운로드 fallback 동작

## 폴더 설명

- `runtime-models/`
  - 배포에 쓰는 모델 입력 폴더
- `scripts/`
  - 빌드, 패키징, manifest 생성 스크립트
- `.github/workflows/python-env-deploy.yml`
  - GitHub Actions 배포 워크플로

자세한 모델 폴더 규칙은 [runtime-models/README.md](C:\Users\hana_us04\Desktop\project\dev\new-pro\kiosk-python-runtime\runtime-models\README.md)를 보면 됩니다.

## 어떤 걸 어디서 바꾸는지

### 1. STT 모델 변경

- 위치: `runtime-models/stt/`
- 예: `runtime-models/stt/whisper-small-int8-ov/...`
- 결과: `stt-assets.zip`에 그대로 반영

### 2. Hailo HEF 변경

- 위치: `runtime-models/hailo/models/*.hef`
- 선택 파일: `runtime-models/hailo/Qwen2.5-1.5B-Instruct.hef`
- 결과: `hailo-addon.zip`에 반영

### 3. TTS 실물 모델로 운영할 때

- 위치:
  - `runtime-models/tts/core/piper_models/...`
  - `runtime-models/tts/core/sherpa_models/...`
  - `runtime-models/tts/core/nltk_data/...`
  - `runtime-models/tts/hf/tts-hf-*/...`
- 결과:
  - `tts-core-assets.zip`
  - `tts-hf-*.zip`

### 4. TTS를 기존 방식으로 유지할 때

- 위치: `runtime-models/speech-assets.json`
- 의미: 다운로드할 Piper, Sherpa, Hugging Face, NLTK 목록 정의

## 배포 규칙

### `main` 먼저 푸시한 뒤 태그

아래 파일이 바뀌면 엔진 캐시에 영향이 있으므로 `main`을 먼저 올리는 게 좋습니다.

- `requirements.txt`
- `libs/*.whl`
- `scripts/build-python-env.ps1`
- `scripts/package-split-runtime.ps1`

권장 순서:

1. `main` 푸시
2. `main` GitHub Actions 완료 확인
3. `env-v1.4.xx` 태그 푸시

### 태그만 푸시

엔진 패키지에 영향이 없는 변경은 태그만 바로 푸시해도 됩니다.

예시:

- `runtime-models/stt/**`
- `runtime-models/hailo/**`
- `runtime-models/tts/**`
- `runtime-models/speech-assets.json`
- `scripts/prepare-speech-assets.ps1`
- `scripts/generate-runtime-artifacts.ps1`
- `.github/workflows/python-env-deploy.yml`

권장 순서:

1. 변경 커밋 확인
2. `env-v1.4.xx` 태그 푸시

## 빠른 운영 요약

- STT/Hailo 바꿀 때는 `runtime-models/`만 수정
- TTS는 지금 당장은 기존 fallback 유지 가능
- 엔진에 영향이 있으면 `main` 먼저
- 최종 배포는 항상 태그

# kiosk-python-runtime

## 배포 규칙

이 저장소는 `cheonan-kiosk`에서 `env-v1.4.xx` 같은 릴리스 태그를 기준으로 사용합니다.

- 최종 배포는 항상 태그 푸시로 합니다.
- 차이는 태그 전에 `main`을 먼저 푸시해야 하는지 여부입니다.

### 1. `main` 먼저, 그다음 태그

아래 파일 중 하나라도 바뀌면 이 방식으로 진행합니다.

- `requirements.txt`
- `libs/*.whl`
- `scripts/build-python-env.ps1`
- `scripts/package-split-runtime.ps1`

이유:

- 이 파일들은 `python-engine.zip` 내용에 영향을 줍니다.
- 동시에 엔진 캐시 키에도 포함됩니다.
- 먼저 `main`에서 액션을 돌려 엔진 캐시를 만든 뒤 태그를 푸시해야 태그 빌드가 덜 느립니다.

권장 절차:

1. `main` 푸시
2. `main` 액션 완료 확인
3. `env-v1.4.xx` 태그 푸시

### 2. 태그만 푸시

엔진 패키지에 영향이 없는 변경이면 이 방식으로 진행합니다.

예시:

- STT 모델 변경
- TTS 모델 변경
- `scripts/prepare-speech-assets.ps1`
- `.github/workflows/python-env-deploy.yml`
- `scripts/generate-runtime-artifacts.ps1`

이유:

- 이런 변경은 보통 `python-engine.zip`을 다시 만들 필요가 없습니다.
- 다만 `cheonan-kiosk`는 태그 릴리스를 사용하므로 최종적으로는 태그가 반드시 필요합니다.

권장 절차:

1. 변경이 들어간 커밋을 태그가 가리키는지 확인
2. `env-v1.4.xx` 태그 푸시

## 한 줄 규칙

- `python-engine.zip`에 영향이 있으면 `main` 먼저, 그다음 태그
- 영향이 없으면 태그만 푸시

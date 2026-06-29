# FocusSession

집중 세션을 시작하고, 카운트다운을 보고, 끝나면 작업별로 시간을 쌓아 통계로 돌아보는 macOS 네이티브 타이머 앱.

![타이머 + 타임테이블](docs/screenshot-timer.png)

![통계 대시보드](docs/screenshot-stats.png)

## 기능

- ⏱ **원형 다이얼 타이머** — 시계 분침처럼 돌려 시간 설정 (5분 미만 ~ 60분 초과 자유롭게)
- 🎯 **세션 진행** — 카운트다운 + 메뉴바 실시간 타이머, 일시정지/재개, 종료 시 만족도·메모 기록
- 🗂 **카테고리** — 색상 지정, 이름 변경, 드래그로 순서 변경, 아카이브
- 📊 **통계 대시보드** — 기간 전환(오늘/주/월/직접지정), 카테고리 도넛·일별 막대·작업 랭킹, CSV 내보내기
- 🗓 **타임테이블 패널** — 창을 넓히면 우측에 지난 세션을 시간표처럼 표시, 블록을 드래그해 시간 조정/편집
- 🔔 알림음 · 다크 모노크롬 UI

## 설치

> ⚠️ 이 앱은 Apple Developer 서명을 받지 않은 무료 배포본입니다. macOS Gatekeeper가 첫 실행을 막으므로 **처음 한 번만** 아래 방법으로 열어주세요.

1. [Releases](../../releases/latest)에서 `FocusSession-x.x.dmg`를 다운로드
2. dmg를 열고 **FocusSession**을 **Applications** 폴더로 드래그
3. 응용 프로그램에서 FocusSession을 **우클릭 → 열기** → 경고창에서 다시 **열기**
   - 한 번만 이렇게 열면 다음부터는 더블클릭으로 실행됩니다.

터미널이 편하면 격리 속성을 직접 제거해도 됩니다:

```bash
xattr -dr com.apple.quarantine /Applications/FocusSession.app
```

### 요구 사항
- macOS 15 (Sequoia) 이상
- Apple Silicon · Intel 모두 지원 (유니버설 바이너리)

## 소스에서 빌드

[XcodeGen](https://github.com/yonaskolb/XcodeGen)이 필요합니다 (`brew install xcodegen`).

```bash
# 빌드 후 /Applications 에 설치하고 실행
./install.sh

# 배포용 .dmg 만들기 (dist/ 에 생성)
./package.sh 1.0
```

프로젝트 파일(`FocusSession.xcodeproj`)은 `project.yml`에서 생성되므로 저장소에 포함되지 않습니다. Xcode로 직접 열려면 `xcodegen generate` 후 `.xcodeproj`를 여세요.

## 기술 스택
SwiftUI · SwiftData · Swift Charts · Swift 6 (strict concurrency) · XcodeGen

## 라이선스
[PolyForm Noncommercial 1.0.0](LICENSE) — **비상업적 용도로만** 자유롭게 사용·수정·배포할 수 있습니다. 상업적 이용은 허용되지 않습니다.

# 자동 업데이트 (Sparkle)

FocusSession은 [Sparkle](https://sparkle-project.org)로 앱 안에서 새 버전을 확인·다운로드·설치·재실행합니다. 사용자는 첫 실행 시 "자동으로 업데이트를 확인할까요?"에 한 번 동의하면 이후 자동으로 갱신됩니다. 메뉴의 **FocusSession → Check for Updates…** 로 수동 확인도 가능합니다.

앱은 서명(Apple Developer ID) 없이 배포되지만, Sparkle은 **EdDSA 서명**으로 업데이트 무결성을 자체 검증하므로 안전합니다.

## 최초 1회 설정 (개발자)

1. 한 번 빌드해서 Sparkle 도구를 받습니다 (`./install.sh` 또는 `./release.sh` 첫 실행).
2. 키 쌍을 생성합니다 — **개인키는 로그인 키체인에만 저장되고 절대 커밋/공유하지 마세요.**
   ```bash
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   출력된 **public key**(base64)를 복사합니다.
3. `project.yml`의 `SUPublicEDKey` 값을 그 public key로 교체합니다.
   ```yaml
   SUPublicEDKey: <여기에 붙여넣기>
   ```
   (`SUFeedURL`은 이미 이 저장소의 appcast raw URL로 설정돼 있습니다.)

> 개인키를 잃어버리면 기존 사용자에게 업데이트를 더는 서명해 보낼 수 없어요. `generate_keys`가 안내하는 대로 키체인 백업을 보관하세요.

## 새 버전 릴리스할 때마다

1. `project.yml`에서 **버전 두 개를 올립니다** — `MARKETING_VERSION`(예: 1.2)과 `CURRENT_PROJECT_VERSION`(예: 3). Sparkle은 `CURRENT_PROJECT_VERSION`(CFBundleVersion)이 **커져야** 업데이트로 인식합니다.
2. 릴리스 아티팩트 생성 + appcast 서명:
   ```bash
   ./release.sh 1.2
   ```
   → `appcast.xml` 갱신(서명 포함), Sparkle용 `FocusSession-1.2.zip`, 최초 다운로드용 `dist/FocusSession-1.2.dmg` 생성.
3. GitHub 릴리스에 **zip과 dmg 둘 다 업로드** (zip = 자동 업데이트용, dmg = 신규 다운로드용):
   ```bash
   gh release create v1.2 \
     dist/FocusSession-1.2.dmg "<임시경로>/FocusSession-1.2.zip" \
     --title "FocusSession 1.2" --notes "…"
   ```
   (`release.sh`가 끝나며 정확한 zip 경로와 명령을 출력해줍니다.)
4. **appcast.xml 커밋 & 푸시** — 이게 실제로 업데이트를 "공개"하는 단계예요:
   ```bash
   git add appcast.xml project.yml && git commit -m "1.2" && git push
   ```

이러면 기존 사용자의 앱이 다음 확인 때 새 버전을 발견해 자동으로 받아 설치합니다.

## 동작 요약

- `SUFeedURL` → `https://raw.githubusercontent.com/baessu/focus-session/main/appcast.xml`
- `appcast.xml`의 `<item>`이 GitHub 릴리스의 zip을 가리키고, 각 항목은 EdDSA로 서명됨.
- Sparkle이 서명을 `SUPublicEDKey`로 검증한 뒤에만 설치.

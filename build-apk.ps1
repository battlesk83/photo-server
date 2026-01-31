# Flutter APK 빌드용 PowerShell 스크립트
# 사용: .\build-apk.ps1
# 출력: build\app\outputs\flutter-apk\app-release.apk (또는 app-debug.apk)

Set-Location $PSScriptRoot

Write-Host "의존성 설치 중 (flutter pub get)..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "APK 빌드 중 (flutter build apk)..." -ForegroundColor Cyan
flutter build apk
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "완료. APK 위치: build\app\outputs\flutter-apk\" -ForegroundColor Green

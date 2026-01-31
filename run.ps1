# Flutter 앱 실행용 PowerShell 스크립트
# 사용: 우클릭 → "PowerShell에서 실행" 또는 터미널에서 .\run.ps1

Set-Location $PSScriptRoot

Write-Host "의존성 설치 중 (flutter pub get)..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "에뮬레이터에서 앱 실행 중 (flutter run)..." -ForegroundColor Cyan
flutter run

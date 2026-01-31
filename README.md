# seongyu_samchon_counsel

Flutter 기반 AI 상담 앱. 상담 엔진은 서버 중계를 통해 **gpt-4o** 한 종류만 사용하며(코드: `lib/services/counsel_api_service.dart`의 `model` 상수), 천사썬/팩폭썬은 말투만 구분한다. AI 응답에는 모델명이 노출되지 않도록 시스템 지시(system_addendum)로 제한한다.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

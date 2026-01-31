/// 웹에서는 파일 저장 미지원. synthesizeToBytes() 사용.
Future<String> saveMp3ToPath(List<int> bytes, String voice) async {
  throw UnsupportedError('Use OpenAiTtsService.synthesizeToBytes() on web.');
}

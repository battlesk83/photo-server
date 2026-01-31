import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// IO 전용: MP3 바이트를 임시 파일로 저장하고 경로 반환.
Future<String> saveMp3ToPath(List<int> bytes, String voice) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/tts_${voice}_${DateTime.now().millisecondsSinceEpoch}.mp3');
  await file.writeAsBytes(bytes);
  return file.path;
}

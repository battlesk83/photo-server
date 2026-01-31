import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/counsel.dart';
import 'tts_storage_web.dart' if (dart.library.io) 'tts_storage_io.dart' as tts_storage;

/// OpenAI TTS 전용. flutter_tts/Android TTS 사용 금지.
/// 1) sun-api /tts 프록시 시도 → 2) 실패 시 API 키 있으면 OpenAI 직접 호출.
/// 실패 시 fallback 없이 예외만 발생 (재요청만 수행).
/// 웹에서는 synthesizeToBytes() + BytesSource 사용.
class OpenAiTtsService {
  static const String _baseUrl = 'https://sun-api.battlesk83.workers.dev';
  static const String _openAiSpeechUrl = 'https://api.openai.com/v1/audio/speech';
  static const String _model = 'gpt-4o-mini-tts';
  /// 말속도 (1.0 = 기본, 1.2 = 1.5에서 낮춤)
  static const double _speed = 1.2;

  /// 빌드 시 --dart-define=OPENAI_API_KEY=sk-... 로 넣으면 프록시 실패 시 직접 호출
  static String get _apiKey => String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  /// 숫자·특수문자 제거 (한글, 공백, 문장부호만 유지)
  static String _sanitize(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[0-9]'), '')
        .replaceAll(RegExp(r'[^\uAC00-\uD7A3\s.,!?]'), '');
    return cleaned.trim();
  }

  /// 쉼 없이 이어서 읽기 (문장 사이 쉼표/쉼 추가하지 않음)
  static String _addPauses(String text) {
    return text.trim();
  }

  /// 천사썬: onyx(굵은 중저음 남성), 팩폭썬: onyx
  static String _voiceFor(CounselMode mode) => 'onyx';

  /// 천사썬: 굵은 중저음 남성 / 팩폭썬: 쎄고 힘있는 만화캐릭터 성우
  static String _instructionsFor(CounselMode mode) {
    if (mode == CounselMode.angel) {
      return 'Speak in a thick, mid-low male voice. Deep and resonant—never light, frivolous, or high-pitched. Like a calm, wise father: dignified, warm, and reassuring. Serious tone, not playful. Korean male vocal tone.';
    }
    return 'Speak in a very loud, big, and extremely strong male voice. Like a powerful anime or cartoon character voice actor. Bold, intense, commanding. Maximum volume and power. Korean male vocal tone.';
  }

  /// OpenAI TTS 입력 최대 길이
  static const int _maxInputLength = 4096;

  /// TTS API 호출 후 MP3 바이트 반환. 웹에서 BytesSource 재생용.
  Future<Uint8List> synthesizeToBytes(String text, CounselMode mode) async {
    final safe = _sanitize(text);
    if (safe.isEmpty) {
      throw TtsException('TTS: 변환할 텍스트가 없습니다.');
    }
    final truncated = safe.length > _maxInputLength
        ? safe.substring(0, _maxInputLength)
        : safe;
    final input = _addPauses(truncated);
    final voice = _voiceFor(mode);
    final instructions = _instructionsFor(mode);

    final body = <String, dynamic>{
      'model': _model,
      'input': input,
      'voice': voice,
      'speed': _speed,
      'instructions': instructions,
    };

    final uris = [
      Uri.parse('$_baseUrl/tts'),
      Uri.parse(_baseUrl.endsWith('/') ? '${_baseUrl}tts' : '$_baseUrl/tts'),
    ];

    final key = _apiKey;
    if (key.isNotEmpty) {
      try {
        final res = await http
            .post(
              Uri.parse(_openAiSpeechUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $key',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          return Uint8List.fromList(res.bodyBytes);
        }
      } catch (e) {
        debugPrint('[OpenAiTtsService] OpenAI 직접 호출 실패: $e');
      }
    }

    Object? lastError;
    for (final uri in uris) {
      try {
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));

        if (res.statusCode != 200) {
          lastError = TtsException('TTS ${res.statusCode}: ${res.body.isNotEmpty ? res.body : res.reasonPhrase ?? ""}');
          debugPrint('[OpenAiTtsService] $uri → ${res.statusCode}');
          continue;
        }

        final bytes = res.bodyBytes;
        if (bytes.isEmpty) {
          lastError = TtsException('TTS: 빈 응답');
          continue;
        }

        return Uint8List.fromList(bytes);
      } catch (e) {
        lastError = e;
        debugPrint('[OpenAiTtsService] $uri 실패: $e');
      }
    }

    throw lastError is TtsException
        ? lastError!
        : TtsException(lastError?.toString() ?? 'TTS 요청 실패');
  }

  /// TTS 요청 후 mp3 파일 경로 반환. 모바일/데스크톱 전용. 웹에서는 synthesizeToBytes 사용.
  Future<String> synthesize(String text, CounselMode mode) async {
    final bytes = await synthesizeToBytes(text, mode);
    final voice = _voiceFor(mode);
    return tts_storage.saveMp3ToPath(bytes, voice);
  }
}

class TtsException implements Exception {
  TtsException(this.message);
  final String message;
  @override
  String toString() => message;
}

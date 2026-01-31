import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 관공서/프로필 사진 처리 API — POST /process-photo (image + mode).
/// baseUrl이 비어 있으면 사용 안 함(로컬 파이프라인만 사용).
class PhotoProcessApiService {
  /// 서버 base URL. 비어 있으면 API 호출 안 함.
  static const String baseUrl = String.fromEnvironment(
    'PHOTO_PROCESS_API_URL',
    defaultValue: '',
  );

  static bool get isConfigured => baseUrl.isNotEmpty;

  /// POST /process-photo (multipart: image, mode).
  /// mode: 'gov' | 'profile'
  /// 성공 시 이미지 바이트 반환. 실패 시 PhotoProcessApiException.
  Future<Uint8List> processPhoto({
    required Uint8List imageBytes,
    required String mode,
  }) async {
    if (mode != 'gov' && mode != 'profile') {
      throw PhotoProcessApiException('mode는 gov 또는 profile이어야 합니다.');
    }
    final uri = Uri.parse(baseUrl.endsWith('/')
        ? '${baseUrl}process-photo'
        : '$baseUrl/process-photo');

    final request = http.MultipartRequest('POST', uri);
    request.fields['mode'] = mode;
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      imageBytes,
      filename: 'photo.jpg',
    ));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode != 200) {
        final body = res.body;
        throw PhotoProcessApiException(
          '서버 오류 ${res.statusCode}${body.isNotEmpty ? ': $body' : ''}',
        );
      }

      final bytes = res.bodyBytes;
      if (bytes.isEmpty) throw PhotoProcessApiException('응답 이미지 없음');
      return Uint8List.fromList(bytes);
    } catch (e) {
      if (e is PhotoProcessApiException) rethrow;
      debugPrint('[PhotoProcessApiService] $e');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('timeout') ||
          e.toString().contains('Timeout')) {
        throw PhotoProcessApiException('네트워크 오류');
      }
      throw PhotoProcessApiException('일시 오류: $e');
    }
  }
}

class PhotoProcessApiException implements Exception {
  PhotoProcessApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

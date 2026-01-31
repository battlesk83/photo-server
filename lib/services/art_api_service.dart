import 'dart:convert';

import 'package:http/http.dart' as http;

/// 나도 예술가 — sun-api /artist/finish 만 호출. OpenAI 직접 호출 없음.
class ArtApiService {
  static const String _baseUrl = 'https://sun-api.battlesk83.workers.dev';

  /// 앱 스타일 ID → 서버 style 값 (만화풍 = comic)
  static const Map<String, String> _styleToApi = {
    'abstract': 'abstract',
    'oil': 'oil',
    'watercolor': 'watercolor',
    'cartoon': 'comic',
  };

  /// 캔버스 PNG 바이트 + 스타일 ID → POST /artist/finish (multipart) → 완성 이미지 바이트.
  /// 실패 시 ArtApiException. 앱은 로딩 해제 + 스낵바만 노출, 멈춤/팅김 금지.
  Future<List<int>> completeImage({
    required List<int> pngBytes,
    required String styleId,
  }) async {
    final style = _styleToApi[styleId] ?? styleId;
    final uri = Uri.parse('$_baseUrl/artist/finish');

    final request = http.MultipartRequest('POST', uri);
    request.fields['style'] = style;
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      pngBytes,
      filename: 'sketch.png',
    ));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode != 200) {
        throw ArtApiException('서버 오류 ${res.statusCode}');
      }

      final raw = res.body.trim();
      if (raw.isEmpty) throw ArtApiException('응답 없음');

      final json = jsonDecode(raw) as Map<String, dynamic>?;
      if (json == null) throw ArtApiException('응답 형식 오류');

      // 응답: { image: "data:image/png;base64,..." } 만 처리
      final imageValue = json['image'] as String?;
      if (imageValue == null || imageValue.isEmpty) throw ArtApiException('이미지 없음');

      String b64 = imageValue;
      if (b64.contains(',')) b64 = b64.split(',').last.trim();
      return base64Decode(b64);
    } catch (e) {
      if (e is ArtApiException) rethrow;
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('timeout') ||
          e.toString().contains('Timeout')) {
        throw ArtApiException('네트워크 오류');
      }
      throw ArtApiException('일시 오류');
    }
  }
}

class ArtApiException implements Exception {
  ArtApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

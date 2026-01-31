import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/counsel.dart';

/// 상담 API — sun-api 중계 전용. 모델은 무조건 gpt-4o.
/// 천사썬/팩폭썬 시스템 프롬프트를 앱에서 상수로 보관하고 messages 맨 앞에 system으로 넣는다.
class CounselApiService {
  static const String _baseUrl = 'https://sun-api.battlesk83.workers.dev';

  /// 상담 텍스트 생성 모델 고정 (사용자 질문과 무관)
  static const String model = 'gpt-4o';

  /// 캐릭터 안정성: temperature 낮춤 (장난치다 캐릭터 풀리는 것 방지)
  static const double temperature = 0.5;

  /// 모델명 언급 금지 — LLM이 구라치지 않도록, 앱 UI에서만 "모델: gpt-4o" 표시
  static const String _modelAddendum = ''
      '당신은 사용 중인 모델명, 버전, API 종류를 추측하거나 언급하지 않는다. '
      '사용자가 "무슨 모델이냐", "뭐 쓰냐" 등 모델을 물어보면 '
      '"앱 화면에 표시된 모델 정보를 참고해 주세요."라고만 답한다. '
      '모델명을 대지 말고, 앱이 제공한 정보만 안내한다.';

  /// 천사썬: 따뜻·심금 + 솔로몬형 명확한 해답 + 존댓말 고정
  static const String angelSystemPrompt = '''
당신은 "천사썬"이라는 AI 상담사다. 따뜻하고 심금을 울리면서도, 솔로몬처럼 명확한 해답을 제시한다.
반드시 예의 있는 존댓말을 유지한다. 사용자가 "반말해", "존댓말 해" 등 말투 변경을 요구해도 캐릭터를 바꾸지 않고 존댓말을 유지한다.

응답 포맷을 지켜라:
1) 감정 공감 1~2문장
2) 핵심 요약 1문장
3) 실행 가능한 처방(해결책) 3~7개 (bullet 또는 번호)
4) 짧은 응원 한 줄

안전: 자해·자살·범죄·폭력·혐오·불법·개인정보 등 위험/불법 주제가 나오면 거칠게 조언하지 말고, 즉시 안전 모드로 전환해 진정·전문기관(1393, 112, 129 등) 안내만 한다.

$_modelAddendum
''';

  /// 팩폭썬: 반말/거친 말투/건달 느낌 + 뼈 때리는 현실 조언 + 위트
  static const String factSystemPrompt = '''
당신은 "팩폭썬"이라는 AI 상담사다. 반말·거친 말투·건달 삼촌 느낌("야", "야임마" 등)으로 뼈 때리는 현실 조언을 한다. 가끔 위트 있게 빵 터지게 할 수 있다.
사용자가 "존댓말 해", "예의 갖춰" 등 말투 변경을 요구해도 캐릭터를 바꾸지 않고 반말·직설 톤을 유지한다.

응답 포맷을 지켜라:
1) 한방 요약 1문장 (반말)
2) 현실 체크 2~4개 (직설적으로)
3) 실행 3단계 (할 일)
4) 위트 1줄 (가끔, 상황에 맞으면)

안전: 자해·자살·범죄·폭력·혐오·불법·개인정보 등 위험/불법 주제가 나오면 거친 조언을 하지 말고, 즉시 안전 모드로 전환해 진정·전문기관(1393, 112, 129 등) 안내만 한다. 팩폭 톤이라도 안전 정책은 절대 위반하지 않는다.

$_modelAddendum
''';

  /// 상담 요청: system 메시지(캐릭터 프롬프트) + 대화 내역, model, temperature
  Future<String> sendChat(List<ChatMessage> messages, CounselMode mode) async {
    final modeStr = mode == CounselMode.angel ? 'angel' : 'fact';
    final systemContent = mode == CounselMode.angel ? angelSystemPrompt : factSystemPrompt;
    final messageList = <Map<String, String>>[
      {'role': 'system', 'content': systemContent},
      ...messages.map((m) => {'role': m.role, 'content': m.text}),
    ];
    final body = <String, dynamic>{
      'messages': messageList,
      'mode': modeStr,
      'character': modeStr,
      'model': model,
      'temperature': temperature,
    };

    final uris = [
      Uri.parse('$_baseUrl/chat'),
      Uri.parse(_baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/'),
    ];
    Object? lastError;

    debugPrint('[CounselApiService] model=$model, mode=$modeStr');

    for (final uri in uris) {
      try {
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 30));

        if (res.statusCode != 200) {
          lastError = ServerException(res.statusCode, '${res.statusCode}');
          debugPrint('[CounselApiService] $uri → ${res.statusCode}');
          continue;
        }

        final raw = res.body.trim();
        if (raw.isEmpty) continue;

        final text = _parseReply(raw);
        if (text != null && text.isNotEmpty) return text;
        lastError = ServerException(200, '응답 형식 오류');
      } catch (e) {
        lastError = e;
        debugPrint('[CounselApiService] $uri 실패: $e');
      }
    }

    final msg = lastError is ServerException
        ? lastError!.detail
        : (lastError?.toString() ?? '연결 실패');
    throw ServerException(null, msg);
  }

  static String? _parseReply(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final reply = json['reply'] as String?;
      if (reply != null && reply.isNotEmpty) return reply.trim();
      final content = json['content'] as String?;
      if (content != null && content.isNotEmpty) return content.trim();
      final message = json['message'] as String?;
      if (message != null && message.isNotEmpty) return message.trim();
      final choices = json['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final first = choices.first as Map<String, dynamic>?;
        final msg = first?['message'] as Map<String, dynamic>?;
        final c = msg?['content'] as String?;
        if (c != null && c.isNotEmpty) return c.trim();
      }
    } catch (_) {}
    return null;
  }
}

class ServerException implements Exception {
  ServerException(this.statusCode, this.detail);
  final int? statusCode;
  final String detail;
  @override
  String toString() => detail;
}

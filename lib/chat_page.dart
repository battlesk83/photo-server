import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

enum CounselMode { angel, fact }

class ChatMessage {
  final String role; // "user" | "assistant"
  final String text;
  ChatMessage({required this.role, required this.text});
}

class ChatPage extends StatefulWidget {
  final CounselMode mode;
  const ChatPage({super.key, required this.mode});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  // ⚠️ 시연용 임시: 배포용으로는 절대 이렇게 두지 마
  static const String _openAiApiKey = "PASTE_YOUR_OPENAI_API_KEY_HERE";

  String get _systemPrompt {
    switch (widget.mode) {
      case CounselMode.angel:
        return """
너는 '천사썬'이다. 한국어로 상담한다.
톤: 따뜻하고 다정하고 공감적. 비난/조롱 금지.
목표: 사용자의 감정을 정리해주고, 현실적인 다음 행동을 3단계로 제안.
규칙:
- 짧은 공감 1~2문장 → 핵심요약 1문장 → 선택지/행동 3개(번호) → 마지막 격려 1문장
- 위험/자해/폭력 조짐이면 즉시 안전 우선 안내(전문기관/긴급전화 권고)하고 무리한 단정 금지
""";
      case CounselMode.fact:
        return """
너는 '팩폭썬'이다. 한국어로 상담한다.
톤: 직설적이되 무례/욕설/모욕은 절대 하지 않는다. 핵심만 짧게.
목표: 사용자가 현실을 직면하고 실행하게 만든다.
규칙:
- 첫 줄: 핵심 결론 1문장
- 다음: 문제 원인 2~3개(불릿)
- 다음: 오늘 당장 할 일 3개(체크리스트)
- 마지막: 한 줄로 동기부여
- 위험/자해/폭력 조짐이면 안전 우선 안내
""";
    }
  }

  String get _title => widget.mode == CounselMode.angel ? "천사썬 상담" : "팩폭썬 상담";

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(ChatMessage(role: "user", text: text));
      _controller.clear();
      _loading = true;
    });

    _scrollToBottom();

    try {
      final reply = await _callOpenAI(_messages);
      setState(() {
        _messages.add(ChatMessage(role: "assistant", text: reply));
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(role: "assistant", text: "에러났어 형… 다시 한 번만 보내줘.\n($e)"));
      });
      _scrollToBottom();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<String> _callOpenAI(List<ChatMessage> messages) async {
    final uri = Uri.parse("https://api.openai.com/v1/chat/completions");

    final body = {
      "model": "gpt-4o-mini", // 가성비 좋고 빠름. (원하면 바꿔도 됨)
      "temperature": widget.mode == CounselMode.angel ? 0.8 : 0.6,
      "messages": [
        {"role": "system", "content": _systemPrompt},
        ...messages.map((m) => {"role": m.role, "content": m.text}),
      ],
    };

    final res = await http.post(
      uri,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_openAiApiKey",
      },
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception("OpenAI error ${res.statusCode}: ${res.body}");
    }

    final json = jsonDecode(res.body);
    final content = json["choices"][0]["message"]["content"];
    return (content ?? "").toString().trim();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAngel = widget.mode == CounselMode.angel;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: isAngel ? const Color(0xFF8EC5FC) : const Color(0xFF232526),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final isMe = m.role == "user";
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isMe
                          ? (isAngel ? const Color(0xFFE0C3FC) : const Color(0xFF414345))
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text("썬형이 생각중…"),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: "고민을 적어봐…",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _send,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      backgroundColor: isAngel ? const Color(0xFF8EC5FC) : const Color(0xFF232526),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("전송"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

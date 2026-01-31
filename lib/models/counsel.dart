/// 상담 모드: 천사썬(솔로몬형) / 팩폭썬(똑똑한 건달삼촌)
enum CounselMode { angel, fact }

/// 채팅 메시지 (role + text)
class ChatMessage {
  final String role; // "user" | "assistant"
  final String text;
  ChatMessage({required this.role, required this.text});
}

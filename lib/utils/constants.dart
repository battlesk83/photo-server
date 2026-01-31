/// 여권/증명사진 규격·배경·출력·모드별 정책 상수
class PassportConstants {
  PassportConstants._();

  // ---------- 모드 라벨 ----------
  static const String govPurposeLabel = '관공서 프리패스 제출용';
  static const String profilePurposeLabel = '프로필용 증명사진';

  /// (레거시) 화면 목적 — 관공서용과 동일
  static const String passportPurposeLabel = govPurposeLabel;

  // ---------- 출력 규격 (관공서 모드) ----------
  /// 반명함 3x4 cm 비율 픽셀
  static const int halfIdWidth = 354;
  static const int halfIdHeight = 472;

  /// 증명사진 3.5x4.5 cm 비율 픽셀
  static const int proofWidth = 413;
  static const int proofHeight = 531;

  /// 여권사진(규격) — 3.5x4.5 비율, 프레이밍만 더 타이트
  static const int passportWidth = 413;
  static const int passportHeight = 531;

  /// 출력 형식 ID (관공서 모드에서 버튼 선택)
  static const String outputFormatHalfId = 'half_id';   // 반명함 3x4
  static const String outputFormatProof = 'proof';       // 증명사진 3.5x4.5
  static const String outputFormatPassport = 'passport'; // 여권사진(규격)

  static const List<Map<String, dynamic>> govOutputFormats = [
    {'id': outputFormatHalfId, 'label': '반명함 3×4', 'width': halfIdWidth, 'height': halfIdHeight},
    {'id': outputFormatProof, 'label': '증명사진 3.5×4.5', 'width': proofWidth, 'height': proofHeight},
    {'id': outputFormatPassport, 'label': '여권사진(규격)', 'width': passportWidth, 'height': passportHeight},
  ];

  /// outputFormatId에 따른 출력 픽셀 크기
  static int outputWidthFor(String outputFormatId) {
    if (outputFormatId == outputFormatHalfId) return halfIdWidth;
    if (outputFormatId == outputFormatProof) return proofWidth;
    return passportWidth;
  }
  static int outputHeightFor(String outputFormatId) {
    if (outputFormatId == outputFormatHalfId) return halfIdHeight;
    if (outputFormatId == outputFormatProof) return proofHeight;
    return passportHeight;
  }

  // ---------- 배경 제거 (파스텔 단색 3종, 지정 값 고정) ----------
  /// 연하늘 Color(0xFFD7ECFF)
  static const int backgroundPastelSky = 0xFFD7ECFF;
  /// 연핑크 Color(0xFFFFD6E5)
  static const int backgroundPastelPink = 0xFFFFD6E5;
  /// 연보라 Color(0xFFE8D9FF)
  static const int backgroundPastelPurple = 0xFFE8D9FF;

  static const List<Map<String, dynamic>> backgroundOptions = [
    {'id': 'pastel_sky', 'label': '연하늘', 'color': backgroundPastelSky},
    {'id': 'pastel_pink', 'label': '연핑크', 'color': backgroundPastelPink},
    {'id': 'pastel_purple', 'label': '연보라', 'color': backgroundPastelPurple},
  ];

  /// (레거시) 흰/연회색 — 필요 시 유지
  static const int backgroundWhite = 0xFFFFFFFF;
  static const int backgroundLightGray = 0xFFF2F2F2;

  // ---------- 의상 템플릿 (관공서: Overlay 전용) ----------
  static const String outfitWhiteBlack = 'assets/outfits/outfit_white_black.png';
  static const String outfitWhiteNavy = 'assets/outfits/outfit_white_navy.png';
  static const String outfitDarkCollar = 'assets/outfits/outfit_dark_collar.png';

  static const List<Map<String, dynamic>> outfitTemplates = [
    {'id': 'white_black', 'label': '흰 셔츠 + 검정 자켓', 'path': outfitWhiteBlack},
    {'id': 'white_navy', 'label': '흰 셔츠 + 네이비 자켓', 'path': outfitWhiteNavy},
    {'id': 'dark_collar', 'label': '다크 칼라 셔츠', 'path': outfitDarkCollar},
  ];

  // ---------- 프로필 모드 보정 강도 3단계 ----------
  /// 자연스럽게: 살짝 자연스러운 보정
  static const String profilePresetNatural = 'natural';
  /// 연예인보정: 눈 크게, 잡티 제거, 흰 피부, 턱선 줄이기 느낌
  static const String profilePresetCelebrity = 'celebrity';
  /// 강한보정: 비율적으로 더 높은 보정
  static const String profilePresetStrong = 'strong';

  static const List<Map<String, dynamic>> profilePresets = [
    {'id': profilePresetNatural, 'label': '자연스럽게'},
    {'id': profilePresetCelebrity, 'label': '연예인보정'},
    {'id': profilePresetStrong, 'label': '강한보정'},
  ];

  /// 프로필 프리셋별 스킨 보정 강도 (blend 잡티제거, skinTone 균일화, whiten 흰피부 1.0=무변경)
  static double profileBlendStrength(String presetId) {
    switch (presetId) {
      case profilePresetNatural: return 0.22;
      case profilePresetCelebrity: return 0.42;
      case profilePresetStrong: return 0.58;
      default: return 0.22;
    }
  }
  static double profileSkinToneStrength(String presetId) {
    switch (presetId) {
      case profilePresetNatural: return 0.05;
      case profilePresetCelebrity: return 0.12;
      case profilePresetStrong: return 0.18;
      default: return 0.05;
    }
  }
  static double profileSkinWhitenFactor(String presetId) {
    switch (presetId) {
      case profilePresetNatural: return 1.0;
      case profilePresetCelebrity: return 1.06;
      case profilePresetStrong: return 1.10;
      default: return 1.0;
    }
  }

  // ---------- 강도 상한 (프로필 모드, 하드코딩) ----------
  static const double profileFaceScaleMin = 0.90;
  static const double profileFaceScaleMax = 0.94;
  static const double profileEyeScaleMin = 1.06;
  static const double profileEyeScaleMax = 1.12;
  static const double profileJawScaleMin = 0.85;
  static const double profileJawScaleMax = 0.92;
}

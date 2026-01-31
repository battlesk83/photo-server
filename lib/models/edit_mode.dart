/// 증명사진 편집 모드: 관공서 제출용(제한) vs 프로필용(강화)
enum EditMode {
  /// 관공서 프리패스 제출용 — 제도·정책 위반 없이 제한 보정만
  gov,

  /// 프로필용 증명사진 — 원터치 미용 보정 (제출용 아님)
  profile,
}

extension EditModeExtension on EditMode {
  String get label {
    switch (this) {
      case EditMode.gov:
        return '관공서 프리패스 제출용';
      case EditMode.profile:
        return '프로필용 증명사진';
    }
  }

  String get statusBadge {
    switch (this) {
      case EditMode.gov:
        return '관공서 제출용';
      case EditMode.profile:
        return '프로필 보정모드';
    }
  }

  String get policyCopy {
    switch (this) {
      case EditMode.gov:
        return '관공서 제출 기준에 맞춰 기능이 제한됩니다';
      case EditMode.profile:
        return '본 모드는 여권·신분증·관공서 제출용이 아닙니다';
    }
  }

  String get primaryButtonLabel {
    switch (this) {
      case EditMode.gov:
        return '제출용 보정 실행';
      case EditMode.profile:
        return 'AI 자동보정 실행';
    }
  }
}

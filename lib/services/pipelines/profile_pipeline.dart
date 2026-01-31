import 'dart:io';

import 'package:flutter/foundation.dart';

import '../image_pipeline.dart';
import '../../utils/constants.dart';

/// 프로필용 증명사진 파이프라인.
/// 관공서 제출용과 동일한 프레이밍 엔진(눈 기준·증명 가이드라인) 사용. 배경 + 보정 강도 3단계(자연스럽게/연예인보정/강한보정) 적용.
class ProfilePipeline {
  final ImagePipelineService _core = ImagePipelineService();

  /// 프로필용 원터치 보정. [presetId] natural | celebrity | strong (자연스럽게 | 연예인보정 | 강한보정)
  /// [backgroundColor] 선택된 배경색(연하늘/연핑크/연보라 동일 적용)
  Future<PipelineResult> run({
    required File sourceFile,
    required String presetId,
    int backgroundColor = PassportConstants.backgroundPastelSky,
  }) async {
    debugPrint('[ProfilePipeline] run() 호출: presetId=$presetId (프로필 보정 강도 적용)');
    return _core.runProofCorrection(
      sourceFile: sourceFile,
      backgroundColor: backgroundColor,
      outputFormatId: PassportConstants.outputFormatProof,
      outputPassportSize: true,
      enableResolutionEnhance: false,
      profilePresetId: presetId,
    );
  }
}

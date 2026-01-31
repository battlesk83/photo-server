import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../background_compositor.dart';
import '../image_pipeline.dart';
import '../../utils/constants.dart';

/// 관공서 프리패스 제출용 전용 파이프라인.
/// 정책: 얼굴 생김새/크기/눈/윤곽 변경 금지. 정렬·배경·LOW 피부 보정만.
class GovPipeline {
  final ImagePipelineService _core = ImagePipelineService();

  /// 관공서용 보정 실행.
  /// [outputFormatId] PassportConstants.outputFormatProof | outputFormatPassport (둘 다 413x531 픽셀 규격)
  Future<PipelineResult> run({
    required File sourceFile,
    required int backgroundColor,
    required String outputFormatId,
    bool enableResolutionEnhance = false,
  }) async {
    debugPrint('[GovPipeline] run() 호출: outputFormatId=$outputFormatId, enhance=$enableResolutionEnhance');
    return _core.runProofCorrection(
      sourceFile: sourceFile,
      backgroundColor: backgroundColor,
      outputFormatId: outputFormatId,
      outputPassportSize: true,
      enableResolutionEnhance: enableResolutionEnhance,
    );
  }

  /// 배경 칩 변경 시 캐시된 인물/마스크로 단색 배경만 재합성. 재보정 없이 즉시 반영.
  static Future<Uint8List?> recompositeWithBackground({
    required Uint8List cachedPersonImageBytes,
    required Uint8List cachedMaskBytes,
    required int backgroundColor,
    int? targetWidth,
    int? targetHeight,
  }) async {
    final w = targetWidth ?? PassportConstants.passportWidth;
    final h = targetHeight ?? PassportConstants.passportHeight;
    final result = await BackgroundCompositor.recompositeWithBackground(
      personImageBytes: cachedPersonImageBytes,
      maskBytes: cachedMaskBytes,
      backgroundColor: backgroundColor,
      targetWidth: w,
      targetHeight: h,
    );
    return result.resultBytes;
  }
}

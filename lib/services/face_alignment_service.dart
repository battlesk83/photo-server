import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../utils/constants.dart';
import 'face_landmarks.dart';

/// 출력 규격별 목표: 눈 Y, 상/하단 여백, 얼굴 높이 비율, 확대 상한.
/// 반명함(3×4)·증명사진(3.5×4.5)·여권사진(규격) 각각 규격에 맞춰 인물 배치.
class TargetEyePositionParams {
  const TargetEyePositionParams({
    required this.eyeYRatio,
    required this.eyeYRatioMin,
    required this.eyeYRatioMax,
    required this.topMarginRatioMin,
    required this.topMarginRatioMax,
    required this.bottomMarginRatioMin,
    required this.bottomMarginRatioMax,
    required this.faceHeightRatioMin,
    required this.faceHeightRatioMax,
    required this.maxScale,
  });

  final double eyeYRatio;
  final double eyeYRatioMin;
  final double eyeYRatioMax;
  final double topMarginRatioMin;
  final double topMarginRatioMax;
  final double bottomMarginRatioMin;
  final double bottomMarginRatioMax;
  final double faceHeightRatioMin;
  final double faceHeightRatioMax;
  final double maxScale;
}

TargetEyePositionParams calculateTargetEyePosition(String outputType, int targetWidth, int targetHeight) {
  switch (outputType) {
    case PassportConstants.outputFormatHalfId:
      return const TargetEyePositionParams(
        eyeYRatio: 0.40,
        eyeYRatioMin: 0.38,
        eyeYRatioMax: 0.41,
        topMarginRatioMin: 0.12,
        topMarginRatioMax: 0.18,
        bottomMarginRatioMin: 0.14,
        bottomMarginRatioMax: 0.22,
        faceHeightRatioMin: 0.55,
        faceHeightRatioMax: 0.62,
        maxScale: 1.04,
      );
    case PassportConstants.outputFormatPassport:
      return const TargetEyePositionParams(
        eyeYRatio: 0.44,
        eyeYRatioMin: 0.42,
        eyeYRatioMax: 0.46,
        topMarginRatioMin: 0.08,
        topMarginRatioMax: 0.13,
        bottomMarginRatioMin: 0.08,
        bottomMarginRatioMax: 0.14,
        faceHeightRatioMin: 0.68,
        faceHeightRatioMax: 0.78,
        maxScale: 1.08,
      );
    case PassportConstants.outputFormatProof:
    default:
      return const TargetEyePositionParams(
        eyeYRatio: 0.42,
        eyeYRatioMin: 0.40,
        eyeYRatioMax: 0.43,
        topMarginRatioMin: 0.10,
        topMarginRatioMax: 0.15,
        bottomMarginRatioMin: 0.10,
        bottomMarginRatioMax: 0.16,
        faceHeightRatioMin: 0.62,
        faceHeightRatioMax: 0.70,
        maxScale: 1.06,
      );
  }
}

/// Always-Succeed: 실패 없이 항상 image 반환. usePaddingMode 시 파이프라인에서 캔버스+패딩 적용.
class AlignCropResult {
  const AlignCropResult({
    required this.image,
    this.usePaddingMode = false,
  });
  final img.Image image;
  final bool usePaddingMode;
}

/// 눈 기준 수평 정렬은 파이프라인에서 수행.
/// Always-Succeed: 잘림 시 scale down(0.98~0.90) → 그래도 실패 시 usePaddingMode=true 반환(캔버스 확장).
/// 재시도 최대 5회. try/catch로 크래시 방지.
class FaceAlignmentService {
  static const int _maxRetries = 5;
  static const double _scaleStep = 0.02;
  static const double _scaleMin = 0.90;

  /// [outputType] half_id | proof | passport. 항상 image 반환(실패 없음).
  AlignCropResult alignAndCrop({
    required img.Image image,
    required double targetAspect,
    FaceLandmarkResult? faceResult,
    required String outputType,
    required int targetWidth,
    required int targetHeight,
  }) {
    try {
      if (faceResult == null || faceResult.faceBounds.length < 4) {
        return AlignCropResult(image: _fallbackCropImage(image, targetAspect), usePaddingMode: true);
      }

      final params = calculateTargetEyePosition(outputType, targetWidth, targetHeight);
      double eyeCenterX = (faceResult.eyeLeft[0] + faceResult.eyeRight[0]) / 2.0;
      double eyeY = (faceResult.eyeLeft[1] + faceResult.eyeRight[1]) / 2.0;
      final faceLeft = faceResult.faceBounds[0];
      final faceTop = faceResult.faceBounds[1];
      final faceW = faceResult.faceBounds[2];
      final faceH = faceResult.faceBounds[3];
      final topHead = (faceTop - 0.35 * faceH).clamp(0.0, image.height - 1.0);
      final chinY = (faceTop + faceH).toDouble();

      for (var attempt = 1; attempt <= _maxRetries; attempt++) {
        double scale = 1.00;
        while (scale >= _scaleMin) {
          final faceHeightRatioMid = (params.faceHeightRatioMin + params.faceHeightRatioMax) / 2.0;
          final faceHeightRatio = faceHeightRatioMid * scale;
          var cropH = (faceH / faceHeightRatio).round().clamp(1, image.height);
          var cropW = (cropH * targetAspect).round().clamp(1, image.width);
          if (cropW > image.width) {
            cropW = image.width;
            cropH = (cropW / targetAspect).round().clamp(1, image.height);
          }

          var cropY = (eyeY - params.eyeYRatio * cropH).round();
          var cropX = (eyeCenterX - cropW / 2).round();

          cropX = cropX.clamp(0, image.width - cropW);
          cropY = cropY.clamp(0, image.height - cropH);
          cropW = cropW.clamp(1, image.width - cropX);
          cropH = cropH.clamp(1, image.height - cropY);

          final cropTop = cropY.toDouble();
          final cropBottom = (cropY + cropH).toDouble();
          final scalpOk = topHead >= cropTop && (topHead - cropTop) >= 1;
          final chinOk = chinY <= cropBottom && (cropBottom - chinY) >= 1;

          if (scalpOk && chinOk) {
            try {
              final out = img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);
              return AlignCropResult(image: out, usePaddingMode: false);
            } catch (_) {
              scale -= _scaleStep;
              continue;
            }
          }
          scale -= _scaleStep;
        }

        if (attempt < _maxRetries) {
          eyeCenterX = (faceLeft + faceW / 2).toDouble();
          eyeY = (faceTop + faceH / 2).toDouble();
        }
      }

      return AlignCropResult(image: image, usePaddingMode: true);
    } catch (e) {
      debugPrint('[FaceAlignmentService] 예외: $e → 패딩 모드로 안전 반환');
      return AlignCropResult(image: image, usePaddingMode: true);
    }
  }

  img.Image _fallbackCropImage(img.Image image, double targetAspect) {
    final currentAspect = image.width / image.height;
    if ((currentAspect - targetAspect).abs() < 0.01) return image;
    int cropW = image.width;
    int cropH = image.height;
    if (currentAspect > targetAspect) {
      cropH = image.height;
      cropW = (cropH * targetAspect).round().clamp(1, image.width);
    } else {
      cropW = image.width;
      cropH = (cropW / targetAspect).round().clamp(1, image.height);
    }
    final x = ((image.width - cropW) / 2).round().clamp(0, image.width - cropW);
    final y = ((image.height - cropH) / 2).round().clamp(0, image.height - cropH);
    return img.copyCrop(image, x: x, y: y, width: cropW, height: cropH);
  }
}

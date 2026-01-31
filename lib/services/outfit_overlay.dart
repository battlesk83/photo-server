import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'face_landmarks.dart';

/// Step 5: 투명 배경 의상 템플릿 PNG Overlay. 생성형 AI 미사용.
/// 목·어깨 랜드마크 기준 스케일/회전/이동, 상반신 마스크에만 합성, 얼굴 영역 100% 제외.
class OutfitOverlayService {
  /// 템플릿 내 앵커: [목 하단, 왼쪽 어깨, 오른쪽 어깨] (비율 0~1)
  static const List<List<double>> _templateAnchorRatio = [
    [0.5, 0.12],  // 목 하단 중앙
    [0.22, 0.28], // 왼쪽 어깨
    [0.78, 0.28], // 오른쪽 어깨
  ];

  /// 상반신 마스크(목~어깨)에만 템플릿 합성. 얼굴 픽셀 변경 시 검증에서 실패.
  Future<OutfitResult> overlay({
    required img.Image sourceImage,
    required String templateAssetPath,
    required FaceLandmarkResult? landmarks,
  }) async {
    if (landmarks == null || landmarks.neckShoulderPoints == null || landmarks.neckShoulderPoints!.length < 3) {
      return OutfitResult(success: false, message: '얼굴이 검출되지 않았습니다. 정면을 향한 사진을 사용해 주세요.');
    }
    try {
      final byteData = await rootBundle.load(templateAssetPath);
      final bytes = byteData.buffer.asUint8List();
      final template = img.decodeImage(bytes);
      if (template == null) {
        return OutfitResult(success: false, message: '템플릿 이미지 로드 실패');
      }

      final neckBottom = landmarks.neckShoulderPoints![0];
      final leftShoulder = landmarks.neckShoulderPoints![1];
      final rightShoulder = landmarks.neckShoulderPoints![2];
      final faceBounds = landmarks.faceBounds;
      final left = faceBounds[0];
      final top = faceBounds[1];
      final fw = faceBounds[2];
      final fh = faceBounds[3];
      final faceBottom = top + fh;
      final faceCenterX = left + fw / 2.0;

      // 1) neck_to_shoulders 마스크: 상반신만 255, 얼굴 영역 0
      final mask = _createNeckToShouldersMask(
        width: sourceImage.width,
        height: sourceImage.height,
        neckBottom: neckBottom,
        leftShoulder: leftShoulder,
        rightShoulder: rightShoulder,
        faceBounds: faceBounds,
      );

      // 2) 템플릿 앵커 (픽셀)
      final tw = template.width;
      final th = template.height;
      final templateNeck = [_templateAnchorRatio[0][0] * tw, _templateAnchorRatio[0][1] * th];
      final templateLeft = [_templateAnchorRatio[1][0] * tw, _templateAnchorRatio[1][1] * th];
      final templateRight = [_templateAnchorRatio[2][0] * tw, _templateAnchorRatio[2][1] * th];

      // 3) 스케일·회전·이동: 이미지 좌표 ← 템플릿 좌표
      final scale = _estimateScale(
        neckBottom,
        leftShoulder,
        rightShoulder,
        templateNeck,
        templateLeft,
        templateRight,
      );
      final dx = neckBottom[0] - templateNeck[0] * scale;
      final dy = neckBottom[1] - templateNeck[1] * scale;

      // 4) 상반신 마스크 영역에만 합성, 경계 feather, 얼굴 영역은 원본 유지
      const featherPx = 8;
      final out = img.Image.from(sourceImage);
      final bodyBottom = (rightShoulder[1] + (rightShoulder[1] - neckBottom[1]) * 2.5).round().clamp(0, sourceImage.height - 1);
      final yStart = (neckBottom[1] - 5).round().clamp(0, sourceImage.height - 1);
      final xLeft = (leftShoulder[0] - 30).round().clamp(0, sourceImage.width - 1);
      final xRight = (rightShoulder[0] + 30).round().clamp(0, sourceImage.width - 1);

      for (var y = yStart; y < sourceImage.height && y <= bodyBottom + featherPx; y++) {
        for (var x = 0; x < sourceImage.width; x++) {
          // 얼굴 영역: 절대 덮지 않음
          if (_isInsideFace(x, y, faceBounds, margin: 2)) {
            continue;
          }
          final maskVal = mask.getPixel(x, y).r / 255.0;
          if (maskVal <= 0) continue;

          // 이미지 (x,y) → 템플릿 (tx, ty)
          final tx = (x - dx) / scale;
          final ty = (y - dy) / scale;
          final ti = tx.round();
          final tj = ty.round();
          if (ti < 0 || ti >= tw || tj < 0 || tj >= th) continue;

          final tp = template.getPixel(ti, tj);
          final ta = tp.a / 255.0;
          if (ta <= 0) continue;

          // 경계 feather: 마스크 가장자리에서 부드럽게
          final dist = _minDistToMaskEdge(mask, x, y, featherPx);
          final feather = (dist / featherPx).clamp(0.0, 1.0);
          final alpha = ta * maskVal * feather;

          final sp = sourceImage.getPixel(x, y);
          final r = (sp.r * (1 - alpha) + tp.r * alpha).round().clamp(0, 255);
          final g = (sp.g * (1 - alpha) + tp.g * alpha).round().clamp(0, 255);
          final b = (sp.b * (1 - alpha) + tp.b * alpha).round().clamp(0, 255);
          out.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return OutfitResult(success: true, image: out, message: null);
    } catch (e) {
      if (e is FlutterError) {
        return OutfitResult(success: false, message: '의상 템플릿 파일이 없습니다. assets/outfits/ 폴더를 확인하세요.');
      }
      return OutfitResult(success: false, message: '의상 합성 실패: $e');
    }
  }

  bool _isInsideFace(int x, int y, List<int> faceBounds, {int margin = 0}) {
    final left = (faceBounds[0] - margin).clamp(0, 99999);
    final top = (faceBounds[1] - margin).clamp(0, 99999);
    final right = faceBounds[0] + faceBounds[2] + margin;
    final bottom = faceBounds[1] + faceBounds[3] + margin;
    return x >= left && x < right && y >= top && y < bottom;
  }

  img.Image _createNeckToShouldersMask({
    required int width,
    required int height,
    required List<double> neckBottom,
    required List<double> leftShoulder,
    required List<double> rightShoulder,
    required List<int> faceBounds,
  }) {
    final mask = img.Image(width: width, height: height);
    final left = faceBounds[0];
    final top = faceBounds[1];
    final fw = faceBounds[2];
    final fh = faceBounds[3];
    final faceBottom = top + fh;
    final neckY = neckBottom[1].round();
    final shoulderY = (leftShoulder[1] + rightShoulder[1]) / 2;
    final bodyBottom = (shoulderY + (shoulderY - neckBottom[1]) * 2.2).clamp(0.0, height - 1.0).round();
    final xLeft = (leftShoulder[0] - 40).round().clamp(0, width - 1);
    final xRight = (rightShoulder[0] + 40).round().clamp(0, width - 1);

    for (var y = neckY; y <= bodyBottom && y < height; y++) {
      for (var x = xLeft; x <= xRight && x < width; x++) {
        if (y < faceBottom && x >= left && x < left + fw) continue;
        mask.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
    return mask;
  }

  double _estimateScale(
    List<double> imageNeck,
    List<double> imageLeft,
    List<double> imageRight,
    List<double> templateNeck,
    List<double> templateLeft,
    List<double> templateRight,
  ) {
    final imageSpan = (imageRight[0] - imageLeft[0]).abs();
    final templateSpan = (templateRight[0] - templateLeft[0]).abs();
    if (templateSpan < 1) return 1.0;
    return imageSpan / templateSpan;
  }

  double _minDistToMaskEdge(img.Image mask, int cx, int cy, int maxR) {
    if (mask.getPixel(cx, cy).r < 128) return 0;
    var minD = maxR + 1.0;
    for (var dy = -maxR; dy <= maxR; dy++) {
      for (var dx = -maxR; dx <= maxR; dx++) {
        final nx = (cx + dx).clamp(0, mask.width - 1);
        final ny = (cy + dy).clamp(0, mask.height - 1);
        if (mask.getPixel(nx, ny).r < 128) {
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < minD) minD = d;
        }
      }
    }
    return minD > maxR ? maxR.toDouble() : minD;
  }
}

class OutfitResult {
  OutfitResult({required this.success, this.image, this.message});
  final bool success;
  final img.Image? image;
  final String? message;
}

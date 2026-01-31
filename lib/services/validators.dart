import 'package:image/image.dart' as img;

/// 품질 검증: 얼굴 영역 변경 여부, 배경 단색 여부, 경계 아티팩트.
class Validators {
  /// 얼굴 영역 픽셀 변화가 threshold 넘으면 false (합성 실패)
  static bool checkFaceRegionUnchanged(
    img.Image before,
    img.Image after,
    List<int> faceBounds, {
    double threshold = 0.02,
  }) {
    if (before.width != after.width || before.height != after.height) return false;
    final left = faceBounds[0].clamp(0, before.width - 1);
    final top = faceBounds[1].clamp(0, before.height - 1);
    final w = faceBounds[2].clamp(1, before.width - left);
    final h = faceBounds[3].clamp(1, before.height - top);
    var diffSum = 0.0;
    var count = 0;
    for (var y = top; y < top + h && y < before.height; y++) {
      for (var x = left; x < left + w && x < before.width; x++) {
        final p1 = before.getPixel(x, y);
        final p2 = after.getPixel(x, y);
        diffSum += (p1.r - p2.r).abs() / 255.0;
        diffSum += (p1.g - p2.g).abs() / 255.0;
        diffSum += (p1.b - p2.b).abs() / 255.0;
        count += 3;
      }
    }
    if (count == 0) return true;
    return (diffSum / count) <= threshold;
  }

  /// 배경 영역이 단색에 가까운지 (분산이 limit 이하)
  static bool checkBackgroundSolid(img.Image image, img.Image mask, {double limit = 100.0}) {
    var sumR = 0.0, sumG = 0.0, sumB = 0.0;
    var count = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (mask.getPixel(x, y).r < 128) {
          final p = image.getPixel(x, y);
          sumR += p.r;
          sumG += p.g;
          sumB += p.b;
          count++;
        }
      }
    }
    if (count < 10) return true;
    final meanR = sumR / count;
    final meanG = sumG / count;
    final meanB = sumB / count;
    var varSum = 0.0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (mask.getPixel(x, y).r < 128) {
          final p = image.getPixel(x, y);
          varSum += (p.r - meanR) * (p.r - meanR) + (p.g - meanG) * (p.g - meanG) + (p.b - meanB) * (p.b - meanB);
        }
      }
    }
    return (varSum / count) <= limit;
  }

  /// 목/어깨 경계 깨짐 검사. blendRegion [left, top, width, height] 내 분산이 limit 초과면 실패.
  static bool checkEdgeArtifactLow(img.Image image, List<int> blendRegion, {double limit = 2500.0}) {
    if (blendRegion.length < 4) return true;
    final left = blendRegion[0].clamp(0, image.width - 1);
    final top = blendRegion[1].clamp(0, image.height - 1);
    final w = blendRegion[2].clamp(1, image.width - left);
    final h = blendRegion[3].clamp(1, image.height - top);
    double sumR = 0, sumG = 0, sumB = 0;
    var n = 0;
    for (var y = top; y < top + h && y < image.height; y++) {
      for (var x = left; x < left + w && x < image.width; x++) {
        final p = image.getPixel(x, y);
        sumR += p.r;
        sumG += p.g;
        sumB += p.b;
        n++;
      }
    }
    if (n < 4) return true;
    final meanR = sumR / n;
    final meanG = sumG / n;
    final meanB = sumB / n;
    double varSum = 0;
    for (var y = top; y < top + h && y < image.height; y++) {
      for (var x = left; x < left + w && x < image.width; x++) {
        final p = image.getPixel(x, y);
        varSum += (p.r - meanR) * (p.r - meanR) + (p.g - meanG) * (p.g - meanG) + (p.b - meanB) * (p.b - meanB);
      }
    }
    return (varSum / n) <= limit;
  }
}

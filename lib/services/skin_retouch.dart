import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 피부 보정: 관공서/프로필 공용. 미용/생성형 AI 없음.
/// 잡티 제거(스무딩) + 피부톤 균일화 + (프로필 시) 흰피부 보정. 눈·얼굴 크기·윤곽 변경 금지.
class SkinRetouchService {
  /// 얼굴 영역만 보정. [faceMaskBounds] left, top, width, height. null이면 보정 생략.
  /// [blendStrength] 잡티 제거 강도 0~1 (관공서 기본 0.25). [skinToneStrength] 피부톤 균일화 0~1. [skinWhitenFactor] 1.0=무변경, >1 밝게.
  img.Image retouch(img.Image image, {
    List<int>? faceMaskBounds,
    double? blendStrength,
    double? skinToneStrength,
    double skinWhitenFactor = 1.0,
  }) {
    if (faceMaskBounds != null && faceMaskBounds.length >= 4) {
      final left = faceMaskBounds[0].clamp(0, image.width - 1);
      final top = faceMaskBounds[1].clamp(0, image.height - 1);
      final w = faceMaskBounds[2].clamp(1, image.width - left);
      final h = faceMaskBounds[3].clamp(1, image.height - top);
      final blend = blendStrength ?? 0.25;
      final tone = skinToneStrength ?? 0.05;
      img.Image out = _retouchRegion(image, left, top, w, h, blend);
      out = _applySkinToneUniformity(out, left, top, w, h, tone);
      if (skinWhitenFactor > 1.0) {
        out = _applySkinWhiten(out, left, top, w, h, skinWhitenFactor);
      }
      return out;
    }
    return image;
  }

  /// bilateral 스타일 스무딩, 질감 유지. [blendStrength] 0~1.
  img.Image _retouchRegion(img.Image image, int left, int top, int w, int h, double blendStrength) {
    const radius = 2;
    const sigmaSpace = 1.5;
    const sigmaRange = 35.0;
    final blend = blendStrength.clamp(0.0, 1.0);

    final out = img.Image.from(image);
    final right = (left + w).clamp(0, image.width);
    final bottom = (top + h).clamp(0, image.height);

    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        double sumR = 0, sumG = 0, sumB = 0, sumW = 0;
        final center = image.getPixel(x, y);
        final cr = center.r.toDouble();
        final cg = center.g.toDouble();
        final cb = center.b.toDouble();

        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, image.width - 1);
            final ny = (y + dy).clamp(0, image.height - 1);
            final p = image.getPixel(nx, ny);
            final spatial = math.exp(-(dx * dx + dy * dy) / (2 * sigmaSpace * sigmaSpace));
            final dr = (p.r - cr).abs();
            final dg = (p.g - cg).abs();
            final db = (p.b - cb).abs();
            final colorDist = math.sqrt(dr * dr + dg * dg + db * db);
            final range = math.exp(-(colorDist * colorDist) / (2 * sigmaRange * sigmaRange));
            final weight = spatial * range;
            sumR += p.r * weight;
            sumG += p.g * weight;
            sumB += p.b * weight;
            sumW += weight;
          }
        }
        if (sumW > 0) {
          final sr = (sumR / sumW).round().clamp(0, 255);
          final sg = (sumG / sumW).round().clamp(0, 255);
          final sb = (sumB / sumW).round().clamp(0, 255);
          final or = (image.getPixel(x, y).r * (1 - blend) + sr * blend).round().clamp(0, 255);
          final og = (image.getPixel(x, y).g * (1 - blend) + sg * blend).round().clamp(0, 255);
          final ob = (image.getPixel(x, y).b * (1 - blend) + sb * blend).round().clamp(0, 255);
          out.setPixelRgba(x, y, or, og, ob, 255);
        }
      }
    }
    return out;
  }

  /// 피부톤 균일화: 얼굴 영역 평균으로 블렌드. [strength] 0~1.
  img.Image _applySkinToneUniformity(img.Image image, int left, int top, int w, int h, double strength) {
    final s = strength.clamp(0.0, 1.0);
    double sumR = 0, sumG = 0, sumB = 0;
    var n = 0;
    final right = (left + w).clamp(0, image.width);
    final bottom = (top + h).clamp(0, image.height);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final p = image.getPixel(x, y);
        sumR += p.r;
        sumG += p.g;
        sumB += p.b;
        n++;
      }
    }
    if (n < 1) return image;
    final meanR = sumR / n;
    final meanG = sumG / n;
    final meanB = sumB / n;
    final out = img.Image.from(image);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final p = image.getPixel(x, y);
        final r = (p.r * (1 - s) + meanR * s).round().clamp(0, 255);
        final g = (p.g * (1 - s) + meanG * s).round().clamp(0, 255);
        final b = (p.b * (1 - s) + meanB * s).round().clamp(0, 255);
        out.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return out;
  }

  /// 흰피부 보정: 얼굴 영역 밝기 상승. [factor] 1.0=무변경, 1.06~1.12 등.
  img.Image _applySkinWhiten(img.Image image, int left, int top, int w, int h, double factor) {
    final f = factor.clamp(1.0, 1.2);
    final right = (left + w).clamp(0, image.width);
    final bottom = (top + h).clamp(0, image.height);
    final out = img.Image.from(image);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final p = image.getPixel(x, y);
        final r = (p.r * f).round().clamp(0, 255);
        final g = (p.g * f).round().clamp(0, 255);
        final b = (p.b * f).round().clamp(0, 255);
        out.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return out;
  }
}

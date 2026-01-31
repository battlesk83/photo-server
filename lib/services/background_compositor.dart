import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 인물 컷아웃 캐시 + 단색 배경 재합성.
/// 배경 칩 변경 시 재보정 없이 미리보기/최종 이미지에 즉시 반영.
class BackgroundCompositor {
  /// composite 함수 호출 여부/마스크/resultBytes 길이 디버그 로그 필수.
  /// 반환: (파일, 결과 바이트). 실패 시 (null, null).
  static Future<({File? file, Uint8List? resultBytes})> recompositeWithBackground({
    required Uint8List personImageBytes,
    required Uint8List maskBytes,
    required int backgroundColor,
    required int targetWidth,
    required int targetHeight,
  }) async {
    debugPrint('[BackgroundCompositor] composite 호출됨 selectedBgColor=0x${backgroundColor.toRadixString(16)}');
    try {
      img.Image? person = img.decodeImage(personImageBytes);
      img.Image? mask = img.decodeImage(maskBytes);
      debugPrint('[BackgroundCompositor] mask 존재=${mask != null}, mask크기=${mask != null ? "${mask!.width}x${mask!.height}" : "null"}');
      if (person == null || mask == null) {
        debugPrint('[BackgroundCompositor] decode 실패: person=${person != null}, mask=${mask != null}');
        return (file: null, resultBytes: null);
      }
      if (person.width != mask.width || person.height != mask.height) {
        mask = img.copyResize(mask, width: person.width, height: person.height, interpolation: img.Interpolation.nearest);
      }
      final composed = _compositeSolidBackground(person, mask, backgroundColor);
      final resized = img.copyResize(
        composed,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );
      final outBytes = img.encodeJpg(resized, quality: 92);
      debugPrint('[BackgroundCompositor] resultBytes 길이=${outBytes.length}');
      final outPath = '${Directory.systemTemp.path}/passport_recomposite_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File(outPath);
      await outFile.writeAsBytes(outBytes);
      return (file: outFile, resultBytes: Uint8List.fromList(outBytes));
    } catch (e) {
      debugPrint('[BackgroundCompositor] recomposite 실패: $e');
      return (file: null, resultBytes: null);
    }
  }

  /// 단색 배경 위에 인물 알파 합성. 경계 feather 1~2px.
  static img.Image _compositeSolidBackground(img.Image image, img.Image mask, int backgroundColor) {
    const feather = 2;
    final out = img.Image(width: image.width, height: image.height);
    final r = (backgroundColor >> 16) & 0xFF;
    final g = (backgroundColor >> 8) & 0xFF;
    final b = backgroundColor & 0xFF;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        var alpha = mask.getPixel(x, y).r / 255.0;
        if (feather > 0) {
          var sum = 0.0;
          var n = 0;
          for (var dy = -feather; dy <= feather; dy++) {
            for (var dx = -feather; dx <= feather; dx++) {
              final nx = (x + dx).clamp(0, image.width - 1);
              final ny = (y + dy).clamp(0, image.height - 1);
              sum += mask.getPixel(nx, ny).r / 255.0;
              n++;
            }
          }
          alpha = sum / n;
        }
        final p = image.getPixel(x, y);
        final outR = (p.r * alpha + r * (1 - alpha)).round().clamp(0, 255);
        final outG = (p.g * alpha + g * (1 - alpha)).round().clamp(0, 255);
        final outB = (p.b * alpha + b * (1 - alpha)).round().clamp(0, 255);
        out.setPixelRgba(x, y, outR, outG, outB, 255);
      }
    }
    return out;
  }
}

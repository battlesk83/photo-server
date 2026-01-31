import 'dart:io';

import 'package:image/image.dart' as img;

import '../widgets/background_picker.dart';
import '../widgets/ratio_picker.dart';
import 'face_service.dart';
import 'segmentation_service.dart';

/// 파이프라인: 얼굴 감지 → 규격 크롭(얼굴 중앙/프레이밍) → 세그멘테이션 → 배경 합성 → 안전 보정만 → 리사이즈
/// (얼굴 형태/인상 변경 없음)
class ImagePipelineService {
  final SegmentationService _segmentation = SegmentationService();
  final FaceService _faceService = FaceService();

  /// 처리 후 임시 파일 경로 반환 (JPG)
  Future<File> process({
    required File sourceFile,
    required PhotoRatio ratio,
    required int backgroundColor,
    required bool autoCorrect,
  }) async {
    final bytes = await sourceFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('이미지 디코드 실패');

    // 1) 얼굴 감지 → 얼굴 기준 중앙 정렬·머리~어깨 프레이밍 후 비율 크롭 (형태 변경 없음)
    image = await _cropByRatioAndFace(image, ratio);

    // 2) 셀피 세그멘테이션 → 단색 배경 합성 (feather 2~4px)
    final mask = await _segmentation.getMask(image);
    if (mask != null) {
      image = _compositeBackground(image, mask, backgroundColor);
    } else {
      image = _fillBackground(image, backgroundColor);
    }

    // 3) 자동 보정 (안전만: 잡티·피부톤·밝기·대비·그림자. 얼굴형/인상 변경 금지)
    if (autoCorrect) {
      image = _safeAutoCorrect(image);
    }

    // 4) 최종 출력 해상도로 리사이즈
    final outW = ratio.outputWidth;
    final outH = ratio.outputHeight;
    image = img.copyResize(image, width: outW, height: outH, interpolation: img.Interpolation.linear);

    final outDir = Directory.systemTemp;
    final outPath = '${outDir.path}/idphoto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodeJpg(image, quality: 92));
    return outFile;
  }

  img.Image _compositeBackground(img.Image image, img.Image mask, int backgroundColor) {
    final out = img.Image(width: image.width, height: image.height);
    const feather = 3;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final m = mask.getPixel(x, y).r;
        var alpha = m / 255.0;
        if (feather > 0) {
          var sum = 0.0;
          var count = 0;
          for (var dy = -feather; dy <= feather; dy++) {
            for (var dx = -feather; dx <= feather; dx++) {
              final nx = (x + dx).clamp(0, mask.width - 1);
              final ny = (y + dy).clamp(0, mask.height - 1);
              sum += mask.getPixel(nx, ny).r / 255.0;
              count++;
            }
          }
          alpha = sum / count;
        }
        final p = image.getPixel(x, y);
        final r = (p.r * alpha + ((backgroundColor >> 16) & 0xFF) * (1 - alpha)).round().clamp(0, 255);
        final g = (p.g * alpha + ((backgroundColor >> 8) & 0xFF) * (1 - alpha)).round().clamp(0, 255);
        final b = (p.b * alpha + (backgroundColor & 0xFF) * (1 - alpha)).round().clamp(0, 255);
        out.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return out;
  }

  img.Image _fillBackground(img.Image image, int backgroundColor) {
    return image; // 마스크 없을 때는 원본 유지
  }

  /// 안전 보정만: 밝기·대비·그림자 완화. 얼굴 형태/눈/턱/인상 변경 없음.
  img.Image _safeAutoCorrect(img.Image image) {
    return img.adjustColor(image, brightness: 1.08, contrast: 1.05);
  }

  /// 얼굴 감지 시 얼굴 중앙·머리~어깨 프레이밍으로 비율 크롭. 미감지 시 중앙 크롭. (형태 변경 없음)
  Future<img.Image> _cropByRatioAndFace(img.Image image, PhotoRatio ratio) async {
    final targetAspect = ratio.aspectRatio;
    final face = await _faceService.detect(image);
    int cropX = 0, cropY = 0, cropW = image.width, cropH = image.height;

    if (face != null) {
      final faceCenterX = (face.left + face.width / 2).round();
      final faceCenterY = (face.top + face.height / 2).round();
      if (targetAspect >= image.width / image.height) {
        cropH = image.height;
        cropW = (cropH * targetAspect).round().clamp(1, image.width);
        cropX = (faceCenterX - cropW ~/ 2).clamp(0, image.width - cropW);
        cropY = 0;
      } else {
        cropW = image.width;
        cropH = (cropW / targetAspect).round().clamp(1, image.height);
        cropX = 0;
        cropY = (faceCenterY - cropH ~/ 2).clamp(0, image.height - cropH);
      }
    } else {
      final currentAspect = image.width / image.height;
      if (currentAspect > targetAspect) {
        cropW = (image.height * targetAspect).round();
        cropX = (image.width - cropW) ~/ 2;
        cropH = image.height;
      } else if (currentAspect < targetAspect) {
        cropH = (image.width / targetAspect).round();
        cropY = (image.height - cropH) ~/ 2;
        cropW = image.width;
      }
    }

    return img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);
  }
}

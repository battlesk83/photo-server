import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// 배경 제거: semantic segmentation. 인물/배경 분리만, 인물 마스크 수정 없이 배경만 단색으로 대체.
class BackgroundRemoveService {
  /// 인물 마스크 반환 (0=배경, 255=인물). 입력과 동일 크기. 실패 시 null.
  Future<img.Image?> getPersonMask(img.Image image) async {
    File? tempFile;
    try {
      final bytes = img.encodeJpg(image, quality: 95);
      tempFile = File(
        '${Directory.systemTemp.path}/seg_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes);

      final inputImage = InputImage.fromFile(tempFile);
      final segmenter = SelfieSegmenter(
        mode: SegmenterMode.stream,
        enableRawSizeMask: false,
      );
      final maskResult = await segmenter.processImage(inputImage);
      await segmenter.close();

      if (maskResult == null) return null;

      final confidences = maskResult.confidences;
      final maskW = maskResult.width;
      final maskH = maskResult.height;
      if (confidences.isEmpty || maskW <= 0 || maskH <= 0) return null;

      // 그레이스케일 마스크 이미지 생성 (0=배경, 255=인물)
      final outMask = img.Image(width: maskW, height: maskH);
      for (var i = 0; i < confidences.length && i < maskW * maskH; i++) {
        final v = (confidences[i].clamp(0.0, 1.0) * 255).round().clamp(0, 255);
        outMask.setPixelRgba(i % maskW, i ~/ maskW, v, v, v, 255);
      }

      // 입력 이미지와 크기가 다르면 리사이즈
      if (maskW != image.width || maskH != image.height) {
        return img.copyResize(
          outMask,
          width: image.width,
          height: image.height,
          interpolation: img.Interpolation.linear,
        );
      }
      return outMask;
    } catch (e) {
      debugPrint('[BackgroundRemoveService] getPersonMask 예외: $e');
      return null;
    } finally {
      try {
        tempFile?.deleteSync();
      } catch (_) {}
    }
  }
}

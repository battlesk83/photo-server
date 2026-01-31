import 'package:image/image.dart' as img;

/// 셀피 세그멘테이션 (ML Kit 또는 대체) → 사람 마스크
class SegmentationService {
  /// 입력 이미지와 동일 크기의 마스크 반환 (0=배경, 255=사람). 실패 시 null.
  Future<img.Image?> getMask(img.Image image) async {
    try {
      final segmenter = SelfieSegmenter();
      final mask = await segmenter.process(image);
      segmenter.close();
      return mask;
    } catch (_) {
      return null;
    }
  }
}

/// ML Kit Selfie Segmentation 래퍼 (에셋/모델 없어도 크래시 없이 null 반환)
class SelfieSegmenter {
  dynamic _segmenter;

  Future<img.Image?> process(img.Image image) async {
    try {
      // google_mlkit_selfie_segmentation 사용 시:
      // final input = InputImage.fromBytes(...)
      // final mask = await _segmenter.processImage(input)
      // return convertToImage(mask);
      return null; // 패키지 연동 시 구현
    } catch (_) {
      return null;
    }
  }

  void close() {
    _segmenter?.close();
  }
}

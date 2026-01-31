import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../utils/constants.dart';
import 'background_remove.dart';
import 'face_alignment_service.dart';
import 'face_landmarks.dart';
import 'skin_retouch.dart';
import 'validators.dart';

/// 증명사진 보정 파이프라인 (관공서 프리패스 제출용 전용).
/// 규칙: 에러/팝업 없이 무조건 결과 이미지 생성.
/// - 배경: 연하늘/연핑크/연보라 중 선택한 색으로 출력 캔버스 전체를 채움.
/// - 인물 배치: 반명함(3×4)·증명사진(3.5×4.5)·여권사진(규격) 각각 규격에 맞춰 눈 위치·여백·얼굴 비율 적용.
class ImagePipelineService {
  final FaceLandmarksService _faceLandmarks = FaceLandmarksService();
  final FaceAlignmentService _faceAlignment = FaceAlignmentService();
  final BackgroundRemoveService _backgroundRemove = BackgroundRemoveService();
  final SkinRetouchService _skinRetouch = SkinRetouchService();

  /// Always-Succeed: 어떤 입력이든 무조건 결과 생성. 실패/크래시 없음.
  /// [outputFormatId] half_id | proof | passport
  /// [profilePresetId] 프로필용 시 natural | celebrity | strong → 보정 강도 3단계 적용
  Future<PipelineResult> runProofCorrection({
    required File sourceFile,
    required int backgroundColor,
    String outputFormatId = PassportConstants.outputFormatProof,
    bool outputPassportSize = true,
    bool enableResolutionEnhance = false,
    String? profilePresetId,
  }) async {
    final targetW = PassportConstants.outputWidthFor(outputFormatId);
    final targetH = PassportConstants.outputHeightFor(outputFormatId);
    final targetAspect = targetW / targetH;
    bool usedPaddingMode = false;

    try {
      List<int> bytes;
      try {
        bytes = await sourceFile.readAsBytes();
      } catch (e) {
        debugPrint('[ImagePipelineService] 파일 읽기 실패: $e → 단색 배경 반환');
        return _safeResultInMemory(targetW, targetH, backgroundColor, message: '파일 읽기 실패: $e');
      }

      img.Image? image = img.decodeImage(Uint8List.fromList(bytes));
      if (image == null) {
        debugPrint('[ImagePipelineService] 이미지 디코드 실패 → 단색 배경 반환');
        return _safeResultInMemory(targetW, targetH, backgroundColor, message: '이미지 디코드 실패');
      }

      FaceLandmarkResult? faceResult;
      try {
        faceResult = await _faceLandmarks.detect(bytes);
        if (faceResult == null) debugPrint('[ImagePipelineService] 얼굴 검출 없음 → 패딩/폴백 가능');
      } catch (e) {
        debugPrint('[ImagePipelineService] 얼굴 검출 예외: $e');
        faceResult = null;
      }

      try {
        if (faceResult != null && (faceResult.headEulerAngleZ).abs() > 1.0) {
          image = img.copyRotate(image, angle: -faceResult.headEulerAngleZ, interpolation: img.Interpolation.linear);
        }
      } catch (_) {}

      AlignCropResult alignResult;
      try {
        alignResult = _faceAlignment.alignAndCrop(
          image: image!,
          targetAspect: targetAspect,
          faceResult: faceResult,
          outputType: outputFormatId,
          targetWidth: targetW,
          targetHeight: targetH,
        );
      } catch (e) {
        debugPrint('[ImagePipelineService] align 예외: $e → 패딩 모드');
        alignResult = AlignCropResult(image: image!, usePaddingMode: true);
      }

      usedPaddingMode = alignResult.usePaddingMode;

      if (alignResult.usePaddingMode) {
        debugPrint('[ImagePipelineService] 패딩 모드 사용 → 캔버스 ${targetW}x${targetH} 배경색 채움');
        try {
          img.Image padded = _drawImageOnSolidCanvas(alignResult.image, backgroundColor, targetW, targetH);
          padded = _skinRetouch.retouch(
            padded,
            faceMaskBounds: null,
            blendStrength: profilePresetId != null ? PassportConstants.profileBlendStrength(profilePresetId) : null,
            skinToneStrength: profilePresetId != null ? PassportConstants.profileSkinToneStrength(profilePresetId) : null,
            skinWhitenFactor: profilePresetId != null ? PassportConstants.profileSkinWhitenFactor(profilePresetId) : 1.0,
          );
          final outBytes = img.encodeJpg(padded, quality: 92);
          final outFile = await _writeTempJpg(outBytes);
          return PipelineResult(
            success: true,
            file: outFile,
            resultImageBytes: Uint8List.fromList(outBytes),
            message: null,
            cachedPersonImageBytes: null,
            cachedMaskBytes: null,
            usedPaddingMode: true,
          );
        } catch (_) {
          final padded = _drawImageOnSolidCanvas(alignResult.image, backgroundColor, targetW, targetH);
          final outBytes = img.encodeJpg(padded, quality: 92);
          final outFile = await _writeTempJpg(outBytes);
          return PipelineResult(
            success: true,
            file: outFile,
            resultImageBytes: Uint8List.fromList(outBytes),
            message: null,
            cachedPersonImageBytes: null,
            cachedMaskBytes: null,
            usedPaddingMode: true,
          );
        }
      }

      img.Image currentImage = alignResult.image;
      List<int>? croppedBytes;
      try {
        croppedBytes = img.encodeJpg(currentImage, quality: 95);
      } catch (_) {}
      FaceLandmarkResult? faceResultCropped;
      if (croppedBytes != null) {
        try {
          faceResultCropped = await _faceLandmarks.detect(croppedBytes);
        } catch (e) {
          debugPrint('[ImagePipelineService] 크롭 후 얼굴 검출 예외: $e');
        }
      }
      final faceBounds = faceResultCropped?.faceBounds;

      img.Image? mask;
      try {
        mask = await _backgroundRemove.getPersonMask(currentImage);
        if (mask == null) debugPrint('[ImagePipelineService] 배경 제거 마스크 없음 → 단색 캔버스에 이미지 합성');
      } catch (e) {
        debugPrint('[ImagePipelineService] 배경 제거 예외: $e');
      }

      List<int>? cachedPersonBytes;
      List<int>? cachedMaskBytes;
      if (mask != null) {
        try {
          cachedPersonBytes = img.encodeJpg(currentImage, quality: 95);
          cachedMaskBytes = img.encodePng(mask);
          currentImage = _compositeSolidBackground(currentImage, mask, backgroundColor);
          debugPrint('[ImagePipelineService] 배경 단색 합성 완료');
        } catch (e) {
          debugPrint('[ImagePipelineService] 배경 합성 예외: $e');
        }
      } else {
        try {
          currentImage = _drawImageOnSolidCanvas(currentImage, backgroundColor, currentImage.width, currentImage.height);
          debugPrint('[ImagePipelineService] 마스크 없음 → 캔버스에 이미지 fit 적용');
        } catch (e) {
          debugPrint('[ImagePipelineService] drawImageOnSolidCanvas 예외: $e');
        }
      }

      try {
        currentImage = _skinRetouch.retouch(
          currentImage,
          faceMaskBounds: faceBounds,
          blendStrength: profilePresetId != null ? PassportConstants.profileBlendStrength(profilePresetId) : null,
          skinToneStrength: profilePresetId != null ? PassportConstants.profileSkinToneStrength(profilePresetId) : null,
          skinWhitenFactor: profilePresetId != null ? PassportConstants.profileSkinWhitenFactor(profilePresetId) : 1.0,
        );
      } catch (e) {
        debugPrint('[ImagePipelineService] 스킨 보정 예외: $e');
      }

      if (enableResolutionEnhance && currentImage.width > 0 && currentImage.height > 0) {
        try {
          currentImage = _lightDenoise(currentImage);
          final upW = (currentImage.width * 1.5).round().clamp(1, 4096);
          final upH = (currentImage.height * 1.5).round().clamp(1, 4096);
          currentImage = img.copyResize(currentImage, width: upW, height: upH, interpolation: img.Interpolation.linear);
        } catch (_) {}
      }

      if (outputPassportSize) {
        try {
          currentImage = _drawImageOnSolidCanvas(currentImage, backgroundColor, targetW, targetH);
        } catch (e) {
          debugPrint('[ImagePipelineService] 최종 캔버스 그리기 예외: $e → 단색 캔버스');
          currentImage = _solidColorImage(targetW, targetH, backgroundColor);
        }
      }

      final outBytes = img.encodeJpg(currentImage, quality: 92);
      debugPrint('[ImagePipelineService] 보정 완료 출력 크기 ${currentImage.width}x${currentImage.height} bytes=${outBytes.length}');
      final outFile = await _writeTempJpg(outBytes);
      return PipelineResult(
        success: true,
        file: outFile,
        resultImageBytes: Uint8List.fromList(outBytes),
        message: null,
        cachedPersonImageBytes: cachedPersonBytes != null ? Uint8List.fromList(cachedPersonBytes) : null,
        cachedMaskBytes: cachedMaskBytes != null ? Uint8List.fromList(cachedMaskBytes) : null,
        usedPaddingMode: usedPaddingMode,
      );
    } catch (e, stack) {
      debugPrint('[ImagePipelineService] 파이프라인 예외: $e');
      debugPrint('[ImagePipelineService] 스택: $stack');
      PipelineResult fallback;
      try {
        fallback = await _safeResultFromFile(sourceFile, targetW, targetH, backgroundColor);
      } catch (e2) {
        debugPrint('[ImagePipelineService] _safeResultFromFile 예외: $e2 → 단색 배경만 반환');
        fallback = _safeResultInMemory(targetW, targetH, backgroundColor, message: '보정 중 오류: $e');
      }
      return PipelineResult(
        success: fallback.success,
        file: fallback.file,
        resultImageBytes: fallback.resultImageBytes,
        message: fallback.message ?? '보정 중 오류 발생: $e',
        cachedPersonImageBytes: fallback.cachedPersonImageBytes,
        cachedMaskBytes: fallback.cachedMaskBytes,
        usedPaddingMode: fallback.usedPaddingMode,
      );
    }
  }

  /// 파일 쓰기 없이 메모리에서 단색 배경 이미지 반환 (웹/예외 시 최종 폴백)
  PipelineResult _safeResultInMemory(int w, int h, int backgroundColor, {String? message}) {
    final fallback = _solidColorImage(w, h, backgroundColor);
    final outBytes = img.encodeJpg(fallback, quality: 92);
    return PipelineResult(
      success: true,
      file: null,
      resultImageBytes: Uint8List.fromList(outBytes),
      message: message,
      cachedPersonImageBytes: null,
      cachedMaskBytes: null,
      usedPaddingMode: true,
    );
  }

  Future<PipelineResult> _safeResult(int w, int h, int backgroundColor, {bool usedPaddingMode = false}) async {
    try {
      final fallback = _solidColorImage(w, h, backgroundColor);
      final outBytes = img.encodeJpg(fallback, quality: 92);
      final outFile = await _writeTempJpg(outBytes);
      return PipelineResult(
        success: true,
        file: outFile,
        resultImageBytes: Uint8List.fromList(outBytes),
        message: null,
        cachedPersonImageBytes: null,
        cachedMaskBytes: null,
        usedPaddingMode: usedPaddingMode,
      );
    } catch (_) {
      final fallback = _solidColorImage(w, h, backgroundColor);
      final outBytes = img.encodeJpg(fallback, quality: 92);
      final outFile = await _writeTempJpg(outBytes);
      return PipelineResult(
        success: true,
        file: outFile,
        resultImageBytes: Uint8List.fromList(outBytes),
        message: null,
        cachedPersonImageBytes: null,
        cachedMaskBytes: null,
        usedPaddingMode: true,
      );
    }
  }

  Future<PipelineResult> _safeResultFromFile(File sourceFile, int targetW, int targetH, int backgroundColor) async {
    try {
      final bytes = await sourceFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        final padded = _drawImageOnSolidCanvas(image, backgroundColor, targetW, targetH);
        final outBytes = img.encodeJpg(padded, quality: 92);
        final outFile = await _writeTempJpg(outBytes);
        return PipelineResult(
          success: true,
          file: outFile,
          resultImageBytes: Uint8List.fromList(outBytes),
          message: null,
          cachedPersonImageBytes: null,
          cachedMaskBytes: null,
          usedPaddingMode: true,
        );
      }
    } catch (_) {}
    return _safeResult(targetW, targetH, backgroundColor, usedPaddingMode: true);
  }

  img.Image _solidColorImage(int w, int h, int backgroundColor) {
    final out = img.Image(width: w, height: h);
    final r = (backgroundColor >> 16) & 0xFF;
    final g = (backgroundColor >> 8) & 0xFF;
    final b = backgroundColor & 0xFF;
    for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) out.setPixelRgba(x, y, r, g, b, 255);
    return out;
  }

  /// 마스크 없을 때: 단색 캔버스 생성 후 이미지를 맞춤 비율로 중앙에 그림 (여백에 선택 배경색 반영)
  img.Image _drawImageOnSolidCanvas(img.Image image, int backgroundColor, int canvasW, int canvasH) {
    final out = _solidColorImage(canvasW, canvasH, backgroundColor);
    final scaleW = canvasW / image.width;
    final scaleH = canvasH / image.height;
    final scale = (scaleW < scaleH ? scaleW : scaleH).clamp(0.01, 10.0);
    final drawW = (image.width * scale).round().clamp(1, canvasW);
    final drawH = (image.height * scale).round().clamp(1, canvasH);
    final scaled = img.copyResize(image, width: drawW, height: drawH, interpolation: img.Interpolation.linear);
    final x = ((canvasW - drawW) / 2).round().clamp(0, canvasW - 1);
    final y = ((canvasH - drawH) / 2).round().clamp(0, canvasH - 1);
    for (var dy = 0; dy < drawH && y + dy < canvasH; dy++) {
      for (var dx = 0; dx < drawW && x + dx < canvasW; dx++) {
        final p = scaled.getPixel(dx, dy);
        out.setPixelRgba(x + dx, y + dy, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
      }
    }
    return out;
  }

  Future<File> _writeTempJpg(List<int> bytes) async {
    final outPath = '${Directory.systemTemp.path}/passport_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File(outPath);
    await f.writeAsBytes(bytes);
    return f;
  }

  /// 경량 노이즈 완화 (1픽셀 범위 가우시안 스타일)
  img.Image _lightDenoise(img.Image image) {
    final out = img.Image.from(image);
    const r = 1;
    for (var y = r; y < image.height - r; y++) {
      for (var x = r; x < image.width - r; x++) {
        var sr = 0.0, sg = 0.0, sb = 0.0;
        var n = 0;
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final p = image.getPixel(x + dx, y + dy);
            sr += p.r;
            sg += p.g;
            sb += p.b;
            n++;
          }
        }
        out.setPixelRgba(x, y, (sr / n).round(), (sg / n).round(), (sb / n).round(), 255);
      }
    }
    return out;
  }

  img.Image _compositeSolidBackground(img.Image image, img.Image mask, int backgroundColor) {
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

class PipelineResult {
  PipelineResult({
    required this.success,
    this.file,
    this.resultImageBytes,
    this.message,
    this.cachedPersonImageBytes,
    this.cachedMaskBytes,
    this.usedPaddingMode = false,
  });
  final bool success;
  final File? file;
  final Uint8List? resultImageBytes;
  final String? message;
  final Uint8List? cachedPersonImageBytes;
  final Uint8List? cachedMaskBytes;
  /// 관공서 모드에서 패딩 적용 시 '원본 구도상 여백을 보완했습니다' 배지 표시용
  final bool usedPaddingMode;
}

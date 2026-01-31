import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// 얼굴 랜드마크: Google ML Kit Face Detection. 위치/회전 보정용, 얼굴 형태 변형 없음.
class FaceLandmarksService {
  /// 얼굴 검출 + 랜드마크 추출. 실패 시 null.
  /// [imageBytes] 원본 이미지 바이트 (JPEG/PNG 등)
  /// 반환: 눈/코/얼굴박스/회전각 (정면 정렬·프레이밍용)
  Future<FaceLandmarkResult?> detect(List<int> imageBytes) async {
    if (imageBytes.isEmpty) return null;
    File? tempFile;
    try {
      tempFile = File(
        '${Directory.systemTemp.path}/face_ml_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
        enableTracking: false,
        enableContours: false,
      );
      final detector = FaceDetector(options: options);
      final faces = await detector.processImage(inputImage);
      await detector.close();

      if (faces.isEmpty) {
        debugPrint('[FaceLandmarksService] 얼굴 검출 0개');
        return null;
      }
      final face = faces.first;

      final box = face.boundingBox;
      final left = box.left.round();
      final top = box.top.round();
      final width = box.width.round();
      final height = box.height.round();
      final faceBounds = [left, top, width, height];

      double eyeLeftX = left + width * 0.35;
      double eyeLeftY = top + height * 0.4;
      double eyeRightX = left + width * 0.65;
      double eyeRightY = top + height * 0.4;
      double noseX = left + width * 0.5;
      double noseY = top + height * 0.55;

      final landmarks = face.landmarks;
      if (landmarks != null) {
        final leftEye = landmarks[FaceLandmarkType.leftEye];
        final rightEye = landmarks[FaceLandmarkType.rightEye];
        final noseBase = landmarks[FaceLandmarkType.noseBase];
        if (leftEye != null && leftEye.position != null) {
          eyeLeftX = leftEye.position!.x.toDouble();
          eyeLeftY = leftEye.position!.y.toDouble();
        }
        if (rightEye != null && rightEye.position != null) {
          eyeRightX = rightEye.position!.x.toDouble();
          eyeRightY = rightEye.position!.y.toDouble();
        }
        if (noseBase != null && noseBase.position != null) {
          noseX = noseBase.position!.x.toDouble();
          noseY = noseBase.position!.y.toDouble();
        }
      }

      final headEulerAngleZ = face.headEulerAngleZ ?? 0.0;

      // 목 하단 / 어깨 좌우 추정 (상반신 의상 오버레이용)
      final centerX = (eyeLeftX + eyeRightX) / 2;
      final faceTop = top.toDouble();
      final faceH = height.toDouble();
      final faceW = width.toDouble();
      final neckBottomY = faceTop + faceH * 1.08; // 턱 아래 목 시작
      final shoulderY = neckBottomY + faceH * 0.25;
      final shoulderHalfSpan = (faceW * 0.85).clamp(30.0, 200.0);
      final neckBottom = [centerX, neckBottomY];
      final leftShoulder = [centerX - shoulderHalfSpan, shoulderY];
      final rightShoulder = [centerX + shoulderHalfSpan, shoulderY];
      final neckShoulderPoints = [neckBottom, leftShoulder, rightShoulder];

      return FaceLandmarkResult(
        eyeLeft: [eyeLeftX, eyeLeftY],
        eyeRight: [eyeRightX, eyeRightY],
        nose: [noseX, noseY],
        faceBounds: faceBounds,
        headEulerAngleZ: headEulerAngleZ,
        neckShoulderPoints: neckShoulderPoints,
      );
    } catch (e) {
      debugPrint('[FaceLandmarksService] detect 예외: $e');
      return null;
    } finally {
      try {
        tempFile?.deleteSync();
      } catch (_) {}
    }
  }
}

class FaceLandmarkResult {
  FaceLandmarkResult({
    required this.eyeLeft,
    required this.eyeRight,
    required this.nose,
    required this.faceBounds,
    this.headEulerAngleZ = 0.0,
    this.neckShoulderPoints,
  });
  final List<double> eyeLeft;
  final List<double> eyeRight;
  final List<double> nose;
  final List<int> faceBounds; // left, top, width, height
  final double headEulerAngleZ;
  final List<List<double>>? neckShoulderPoints;
}

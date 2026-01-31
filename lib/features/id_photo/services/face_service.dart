import 'package:image/image.dart' as img;

/// 얼굴 감지 → 프레이밍 보조 (위치·머리~어깨 정렬용. 얼굴 형태 변경 없음)
class FaceService {
  /// 얼굴 박스 또는 랜드마크 반환. 없으면 null.
  Future<FaceInfo?> detect(img.Image image) async {
    return null; // google_mlkit_face_detection 연동 시 구현
  }
}

class FaceInfo {
  FaceInfo({required this.left, required this.top, required this.width, required this.height});
  final double left;
  final double top;
  final double width;
  final double height;
}

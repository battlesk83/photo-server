import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key});

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  /// 캔버스(그리기 영역) 기준 local 좌표만 저장. globalPosition 사용 금지.
  final List<Offset?> _pointsPx = [];
  /// 스트로크별 색상 (null = 구간 끝, i번째 구간 = _strokeColors[i])
  final List<Color> _strokeColors = [];

  final GlobalKey _paintKey = GlobalKey();

  Color _strokeColor = Colors.black;
  double _strokeWidth = 6.0; // 펜 굵기 (2.0 ~ 24.0)

  bool _loading = false;
  double _loadingProgress = 0.0; // 0.0 ~ 1.0 (퍼센트 로딩바)
  bool _showResultImage = true; // true: 변환 후, false: 변환 전(원본)
  String _selectedStyleId = "comic";
  Uint8List? _resultImageBytes;
  String? _errorText;

  static const String _apiBase = "https://sun-api.battlesk83.workers.dev";

  /// 하루 무료 변환 5번 제한 (채팅과 동일 메시지·비밀번호)
  static const int _maxTransforms = 5;
  static const String _limitMessage =
      '하루 무료대화는 5번입니다. 현재는 테스트 기간이므로 비밀번호 "1004" 입력하시면 다시 이용할 수 있습니다.';
  static const String _adminPassword = '1004';
  static const String _prefKeyArtistTransformCount = 'artist_transform_count';
  static bool _artistLimitReached = false;
  static int _artistTransformCount = 0;
  final TextEditingController _limitPasswordController = TextEditingController();

  /// 무료 변환 차단 화면에서 5초 후 메인으로 이동
  Timer? _limitRedirectTimer;
  int? _limitRedirectSeconds;

  /// 뒤로가기/메인 이동해도 초기화되지 않도록 SharedPreferences에서 로드
  Future<void> _loadArtistCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_prefKeyArtistTransformCount) ?? 0;
      _artistTransformCount = count;
      if (count >= _maxTransforms) {
        _artistLimitReached = true;
        _limitRedirectSeconds = 5;
      }
      if (mounted) setState(() {});
      if (_artistLimitReached) _startLimitRedirectTimer();
    } catch (_) {}
  }

  void _startLimitRedirectTimer() {
    _limitRedirectTimer?.cancel();
    _limitRedirectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _limitRedirectTimer?.cancel();
        return;
      }
      setState(() {
        if (_limitRedirectSeconds == null || _limitRedirectSeconds! <= 0) {
          _limitRedirectTimer?.cancel();
          _limitRedirectTimer = null;
          return;
        }
        _limitRedirectSeconds = _limitRedirectSeconds! - 1;
        if (_limitRedirectSeconds! <= 0) {
          _limitRedirectTimer?.cancel();
          _limitRedirectTimer = null;
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    });
  }

  void _cancelLimitRedirectTimer() {
    _limitRedirectTimer?.cancel();
    _limitRedirectTimer = null;
    _limitRedirectSeconds = null;
  }

  Future<void> _saveArtistCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyArtistTransformCount, _artistTransformCount);
    } catch (_) {}
  }

  void _markArtistLimitReached() {
    _artistLimitReached = true;
  }

  void _unlockWithPassword() {
    if (_limitPasswordController.text.trim() != _adminPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 올바르지 않습니다.')),
      );
      return;
    }
    _cancelLimitRedirectTimer();
    _artistLimitReached = false;
    _artistTransformCount = 0;
    _limitPasswordController.clear();
    _saveArtistCount();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadArtistCount();
  }

  void _clearAll() {
    setState(() {
      _pointsPx.clear();
      _strokeColors.clear();
      _resultImageBytes = null;
      _errorText = null;
    });
  }

  void _clearDrawingOnly() {
    setState(() {
      _pointsPx.clear();
      _strokeColors.clear();
      _errorText = null;
    });
  }

  /// 한 단계 뒤로 (마지막 스트로크만 제거)
  void _undo() {
    if (_pointsPx.isEmpty) return;
    setState(() {
      final lastNull = _pointsPx.lastIndexOf(null);
      if (lastNull == -1) {
        _pointsPx.clear();
        _strokeColors.clear();
      } else {
        _pointsPx.removeRange(lastNull, _pointsPx.length);
        if (_strokeColors.isNotEmpty) _strokeColors.removeLast();
      }
      _resultImageBytes = null;
    });
  }

  void _addPoint(Offset localPos) {
    setState(() {
      // 캔버스 밖으로는 그려지지 않도록 좌표 클램프
      final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final w = box.size.width;
        final h = box.size.height;
        localPos = Offset(
          localPos.dx.clamp(0.0, w),
          localPos.dy.clamp(0.0, h),
        );
      }
      _pointsPx.add(localPos);
      _resultImageBytes = null;
    });
  }

  /// 완성한 그림을 갤러리(내 폰)에 저장
  Future<void> _saveResultToGallery() async {
    final bytes = _resultImageBytes;
    if (bytes == null || bytes.isEmpty) return;
    try {
      await Gal.requestAccess();
      await Gal.putImageBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('갤러리에 저장되었어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 실패: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// 캔버스(GestureDetector/CustomPaint) 크기 기준으로 1024 PNG 렌더
  Future<Uint8List> _renderToPngBytes({int outSize = 1024}) async {
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) throw Exception("캔버스 RenderBox 없음");
    final w = box.size.width;
    final h = box.size.height;
    if (w <= 0 || h <= 0) throw Exception("캔버스 사이즈 0");

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 흰 배경
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, outSize.toDouble(), outSize.toDouble()), bg);

    // ✅ 균일 스케일 + 중앙 정렬 (w≠h여도 캔버스에서 벗어나지 않음)
    final scale = (outSize / w) < (outSize / h) ? outSize / w : outSize / h;
    final tx = (outSize - w * scale) / 2;
    final ty = (outSize - h * scale) / 2;

    final strokeCap = StrokeCap.round;
    int strokeIndex = 0;
    Offset? prev;
    Path? path;
    Color? pathColor;

    for (final p in _pointsPx) {
      if (p == null) {
        if (path != null && pathColor != null) {
          final paint = Paint()
            ..color = pathColor
            ..strokeWidth = _strokeWidth * scale
            ..strokeCap = strokeCap
            ..style = PaintingStyle.stroke;
          canvas.drawPath(path, paint);
        }
        path = null;
        pathColor = null;
        prev = null;
        strokeIndex++;
        continue;
      }
      final color = strokeIndex < _strokeColors.length
          ? _strokeColors[strokeIndex]
          : _strokeColor;
      final sp = Offset(p.dx * scale + tx, p.dy * scale + ty);
      if (path == null || pathColor != color) {
        if (path != null && pathColor != null) {
          final paint = Paint()
            ..color = pathColor!
            ..strokeWidth = _strokeWidth * scale
            ..strokeCap = strokeCap
            ..style = PaintingStyle.stroke;
          canvas.drawPath(path, paint);
        }
        path = Path()..moveTo(sp.dx, sp.dy);
        pathColor = color;
        prev = sp;
      } else {
        final mid = Offset((prev!.dx + sp.dx) / 2, (prev.dy + sp.dy) / 2);
        path!.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        prev = sp;
      }
    }
    if (path != null && pathColor != null) {
      final paint = Paint()
        ..color = pathColor!
        ..strokeWidth = _strokeWidth * scale
        ..strokeCap = strokeCap
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(outSize, outSize);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception("PNG 렌더 실패");
    return byteData.buffer.asUint8List();
  }

  Future<void> _aiFinish() async {
    if (_artistLimitReached) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_limitMessage)),
      );
      return;
    }
    // 실제 점이 하나도 없으면 막기
    if (_pointsPx.whereType<Offset>().isEmpty) {
      setState(() => _errorText = "그림이 비어있음. 한 줄이라도 그려줘.");
      return;
    }

    setState(() {
      _loading = true;
      _loadingProgress = 0.0;
      _errorText = null;
    });

    Timer? progressTimer;
    // 로딩 평균 40~50초에 맞춰 퍼센트 진행 (약 1초당 2%, 47초에 95% 도달)
    progressTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!mounted) return;
      setState(() {
        _loadingProgress = (_loadingProgress + 0.02).clamp(0.0, 0.95);
      });
    });

    try {
      final pngBytes = await _renderToPngBytes(outSize: 1024);

      final uri = Uri.parse("$_apiBase/artist/finish");
      final req = http.MultipartRequest("POST", uri);

      req.fields["style"] = _selectedStyleId;
      req.files.add(http.MultipartFile.fromBytes(
        "image",
        pngBytes,
        filename: "drawing.png",
        contentType: http.MediaType("image", "png"),
      ));

      final streamed = await req.send();
      final status = streamed.statusCode;
      final bodyBytes = await streamed.stream.toBytes();

      String bodyText;
      try {
        bodyText = utf8.decode(bodyBytes);
      } catch (e) {
        setState(() {
          _errorText = "서버 응답을 읽을 수 없습니다. (JSON이 아닌 데이터 반환)\n잠시 후 다시 시도해 주세요.";
        });
        return;
      }

      dynamic data;
      try {
        data = jsonDecode(bodyText);
      } catch (_) {
        data = bodyText;
      }

      if (status != 200) {
        final String errMsg = _errorMessageFromResponse(data, status);
        setState(() => _errorText = errMsg);
        return;
      }

      if (data is! Map || data["image"] is! String) {
        setState(() {
          _errorText = "200인데 image가 없음\n${_pretty(data)}";
        });
        return;
      }

      final imageDataUrl = data["image"] as String;
      if (!imageDataUrl.contains("base64,")) {
        setState(() => _errorText = "image 형식이 이상함\n$imageDataUrl");
        return;
      }

      final b64 = imageDataUrl.split("base64,").last.trim();
      final bytes = base64Decode(b64);

      setState(() {
        _resultImageBytes = bytes;
        _showResultImage = true;
      });
      _artistTransformCount++;
      await _saveArtistCount();
      if (_artistTransformCount >= _maxTransforms) {
        _markArtistLimitReached();
        if (mounted) {
          setState(() => _limitRedirectSeconds = 5);
          _startLimitRedirectTimer();
        }
      }
    } catch (e) {
      setState(() => _errorText = "앱 내부 에러\n$e");
    } finally {
      progressTimer.cancel();
      if (mounted) setState(() => _loadingProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() {
        _loading = false;
        _loadingProgress = 0.0;
      });
    }
  }

  /// 서버 에러 응답에서 사용자에게 보여줄 메시지 (안전 필터 등 친절 메시지 우선)
  String _errorMessageFromResponse(dynamic data, int status) {
    if (data is Map) {
      final detail = data["detail"];
      if (detail is String && detail.contains("안전 검사")) {
        return detail;
      }
      if (data["error"] == "safety_filter" && detail is String) {
        return detail;
      }
      final inner = data["detail"] is Map ? data["detail"] as Map : null;
      final err = inner?["error"];
      if (err is Map) {
        final code = err["code"]?.toString() ?? "";
        final msg = (err["message"]?.toString() ?? "").toLowerCase();
        if (code == "moderation_blocked" || msg.contains("safety_violations") || msg.contains("safety system")) {
          return "이미지가 안전 검사에서 차단되었어요.\n다른 그림으로 시도해 주세요.";
        }
      }
    }
    return "서버응답 $status\n${_pretty(data)}";
  }

  String _pretty(dynamic data) {
    try {
      return const JsonEncoder.withIndent("  ").convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  void dispose() {
    _cancelLimitRedirectTimer();
    _limitPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_artistLimitReached) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("🎨 나도 예술가"),
          backgroundColor: Colors.deepPurple.shade700,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade600),
                  const SizedBox(height: 16),
                  Text(
                    _limitMessage,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade800,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _limitPasswordController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(
                      hintText: '비밀번호',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _unlockWithPassword(),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _unlockWithPassword,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.deepPurple.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('다시 이용하기'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '잠시 후 메인화면으로 이동합니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_limitRedirectSeconds != null && _limitRedirectSeconds! > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$_limitRedirectSeconds초',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("🎨 나도 예술가"),
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // ✅ 그리기 영역: GestureDetector가 캔버스(CustomPaint)만 직접 감쌈 → localPosition = (0,0) 기준
                        Positioned.fill(
                          child: GestureDetector(
                            key: _paintKey,
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) => _addPoint(d.localPosition),
                            onPanUpdate: (d) => _addPoint(d.localPosition),
                            onPanEnd: (_) => setState(() {
                              _pointsPx.add(null);
                              _strokeColors.add(_strokeColor);
                            }),
                            child: CustomPaint(
                              painter: _SmoothPainter(_pointsPx, _strokeColors, _strokeColor, _strokeWidth),
                            ),
                          ),
                        ),

                        if (_resultImageBytes != null && _showResultImage)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                child: Image.memory(_resultImageBytes!),
                              ),
                            ),
                          ),

                        if (_loading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.25),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "AI썬형이 열심히 색칠중... ${(_loadingProgress * 100).round()}%",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (_loadingProgress >= 0.93) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "멈춘 거 아니니 잠시 기다려 주세요",
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: 200,
                                    child: LinearProgressIndicator(
                                      value: _loadingProgress,
                                      backgroundColor: Colors.white24,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple.shade200),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Text(
                    "펜 굵기",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _strokeWidth,
                      min: 2,
                      max: 24,
                      divisions: 22,
                      label: _strokeWidth.round().toString(),
                      onChanged: _loading
                          ? null
                          : (v) => setState(() => _strokeWidth = v),
                      activeColor: Colors.deepPurple.shade600,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      "${_strokeWidth.round()}",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_resultImageBytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => setState(() => _showResultImage = !_showResultImage),
                        icon: Icon(_showResultImage ? Icons.draw : Icons.image, size: 20),
                        label: Text(
                          _showResultImage ? "변환 전 보기" : "변환 후 보기",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple.shade700,
                          side: BorderSide(color: Colors.deepPurple.shade400),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _saveResultToGallery,
                        icon: const Icon(Icons.save_alt, size: 20),
                        label: const Text(
                          "내 폰에 저장하기",
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade700,
                          side: BorderSide(color: Colors.teal.shade400),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _colorButton(Colors.black),
                  _colorButton(Colors.red),
                  _colorButton(Colors.blue),
                  _colorButton(Colors.green),
                  _colorButton(Colors.orange),
                  _colorButton(Colors.purple),
                  _colorButton(Colors.brown),
                  _colorButton(Colors.yellow),
                  // 추가 8색: 흰색, 살색, 핫핑크, 연한핑크, 민트, 형광
                  _colorButton(Colors.white),
                  _colorButton(const Color(0xFFFFDBB5)), // 살색
                  _colorButton(const Color(0xFFFF69B4)), // 핫핑크
                  _colorButton(const Color(0xFFFFB6C1)), // 연한핑크
                  _colorButton(const Color(0xFF98FF98)), // 민트
                  _colorButton(const Color(0xFFCCFF00)), // 형광 노랑/라임
                  _colorButton(const Color(0xFF39FF14)),  // 형광 그린
                  _colorButton(const Color(0xFFFF44CC)), // 형광 핑크
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _undo,
                      icon: const Icon(Icons.undo),
                      label: const Text("한 단계 뒤로", style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo.shade700,
                        side: BorderSide(color: Colors.indigo.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _clearDrawingOnly,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text("밑그림지우기", style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade800,
                        side: BorderSide(color: Colors.orange.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _clearAll,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text("전체 삭제", style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip("abstract", "추상화"),
                  _chip("oil", "유화"),
                  _chip("watercolor", "수채화"),
                  _chip("comic", "만화풍"),
                  _chip("princess", "공주님 모드"),
                  _chip("robot", "로보트 모드"),
                ],
              ),
            ),

            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text(_errorText!, style: const TextStyle(color: Colors.red)),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _aiFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade700,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: Colors.deepPurple.shade900,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    "✨✨ AI로 완성하기",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton(Color color) {
    final selected = _strokeColor.value == color.value;
    return GestureDetector(
      onTap: _loading ? null : () => setState(() => _strokeColor = color),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.deepPurple : Colors.grey.shade400,
            width: selected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String id, String label) {
    final selected = _selectedStyleId == id;
    return ChoiceChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onSelected: _loading ? null : (_) => setState(() => _selectedStyleId = id),
      selectedColor: Colors.deepPurple.shade200,
      backgroundColor: Colors.grey.shade200,
      side: BorderSide(
        color: selected ? Colors.deepPurple.shade600 : Colors.grey.shade400,
        width: selected ? 2 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

class _SmoothPainter extends CustomPainter {
  final List<Offset?> pts;
  final List<Color> strokeColors;
  final Color currentColor;
  final double strokeWidth;

  _SmoothPainter(this.pts, this.strokeColors, this.currentColor, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    int strokeIndex = 0;
    Offset? prev;
    Path? path;
    Color? pathColor;

    for (final p in pts) {
      if (p == null) {
        if (path != null && pathColor != null) {
          final paint = Paint()
            ..color = pathColor!
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawPath(path, paint);
        }
        path = null;
        pathColor = null;
        prev = null;
        strokeIndex++;
        continue;
      }
      final color = strokeIndex < strokeColors.length
          ? strokeColors[strokeIndex]
          : currentColor;
      if (path == null || pathColor != color) {
        if (path != null && pathColor != null) {
          final paint = Paint()
            ..color = pathColor!
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawPath(path, paint);
        }
        path = Path()..moveTo(p.dx, p.dy);
        pathColor = color;
        prev = p;
      } else {
        final mid = Offset((prev!.dx + p.dx) / 2, (prev.dy + p.dy) / 2);
        path!.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        prev = p;
      }
    }
    if (path != null && pathColor != null) {
      final paint = Paint()
        ..color = pathColor!
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth || oldDelegate.pts != pts;
}

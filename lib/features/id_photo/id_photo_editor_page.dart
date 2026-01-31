import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'services/image_pipeline.dart';
import 'widgets/background_picker.dart';
import 'widgets/ratio_picker.dart';
import 'id_photo_result_page.dart';

/// 편집 화면: 규격·배경·토글 후 파이프라인 실행 → 결과 페이지
class IdPhotoEditorPage extends StatefulWidget {
  const IdPhotoEditorPage({super.key, required this.sourceFile});

  final File sourceFile;

  static final ImagePicker _picker = ImagePicker();

  static Future<File?> pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    return x == null ? null : File(x.path);
  }

  static Future<File?> pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera);
    return x == null ? null : File(x.path);
  }

  @override
  State<IdPhotoEditorPage> createState() => _IdPhotoEditorPageState();
}

class _IdPhotoEditorPageState extends State<IdPhotoEditorPage> {
  PhotoRatio _ratio = PhotoRatio.proof;
  BackgroundOption _background = BackgroundOption.white;
  bool _autoCorrect = true;

  bool _processing = false;

  Future<void> _applyAndGo() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final pipeline = ImagePipelineService();
      final outFile = await pipeline.process(
        sourceFile: widget.sourceFile,
        ratio: _ratio,
        backgroundColor: _background.color,
        autoCorrect: _autoCorrect,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => IdPhotoResultPage(
            originalFile: widget.sourceFile,
            resultFile: outFile,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('편집'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                widget.sourceFile,
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),
            const Text('규격', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            RatioPicker(
              value: _ratio,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _ratio = v);
              },
            ),
            const SizedBox(height: 20),
            const Text('배경', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            BackgroundPicker(
              value: _background,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _background = v);
              },
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('자동 보정 (잡티·피부톤·밝기·대비·그림자)'),
              subtitle: Text(
                '얼굴 형태는 변경하지 않습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: _autoCorrect,
              onChanged: (v) => setState(() => _autoCorrect = v),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _processing ? null : _applyAndGo,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _processing
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('결과 보기'),
            ),
          ],
        ),
      ),
    );
  }
}

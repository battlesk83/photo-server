import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/save_service.dart';
import 'widgets/before_after_view.dart';

/// 결과 미리보기: 좌측 원본, 우측 결과 + 갤러리 저장 / 공유
class IdPhotoResultPage extends StatelessWidget {
  const IdPhotoResultPage({
    super.key,
    required this.originalFile,
    required this.resultFile,
  });

  final File originalFile;
  final File resultFile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('결과'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: BeforeAfterView(
                beforeFile: originalFile,
                afterFile: resultFile,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _saveToGallery(context),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('갤러리에 저장'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF1565C0)),
                        foregroundColor: const Color(0xFF1565C0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _share(context),
                      icon: const Icon(Icons.share),
                      label: const Text('공유'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToGallery(BuildContext context) async {
    HapticFeedback.lightImpact();
    try {
      await SaveService.saveToGallery(resultFile);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('갤러리에 저장되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    HapticFeedback.lightImpact();
    try {
      await SaveService.share(resultFile);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 실패: $e')),
        );
      }
    }
  }
}

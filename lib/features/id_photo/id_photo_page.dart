import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'id_photo_editor_page.dart';

/// 증명·여권사진 - 진입/안내 + 시작
class IdPhotoPage extends StatelessWidget {
  const IdPhotoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('증명·여권사진 만들기'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.badge, size: 64, color: Color(0xFF1565C0)),
              const SizedBox(height: 16),
              const Text(
                '증명사진·여권사진 규격에 맞게 크롭·배경·자동 보정을 도와드립니다.\n얼굴 형태나 인상을 변경하지 않습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '안내',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFE65100),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '본 기능은 사진 규격 및 품질 보정용입니다.\n'
                      '얼굴 형태나 인상을 변경하지 않습니다.\n'
                      '본인 사진만 사용하시기 바랍니다.\n'
                      '제출 승인 여부는 각 기관의 기준에 따릅니다.',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => _pickAndGo(context),
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('사진 선택하고 시작'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndGo(BuildContext context) async {
    HapticFeedback.lightImpact();
    try {
      final pickerFn = await _showSourceDialog(context);
      if (pickerFn == null || !context.mounted) return;
      final file = await pickerFn();
      if (file == null || !context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IdPhotoEditorPage(sourceFile: file),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 선택 실패: $e')),
        );
      }
    }
  }

  Future<Future<File?>? Function()?> _showSourceDialog(BuildContext context) async {
    return showModalBottomSheet<Future<File?>? Function()?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(ctx, () => IdPhotoEditorPage.pickFromGallery()),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(ctx, () => IdPhotoEditorPage.pickFromCamera()),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 갤러리 저장 / 공유
class SaveService {
  static const String _fileNamePrefix = 'idphoto_';

  static Future<String> saveToGallery(File file) async {
    final now = DateTime.now();
    final name = '${_fileNamePrefix}${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.jpg';
    final dir = await getTemporaryDirectory();
    final dest = File('${dir.path}/$name');
    await file.copy(dest.path);
    await Gal.putImage(dest.path);
    return dest.path;
  }

  static Future<void> share(File file) async {
    final name = '${_fileNamePrefix}${DateTime.now().toIso8601String().replaceAll(RegExp(r'[-:.]'), '').substring(0, 14)}.jpg';
    final dir = await getTemporaryDirectory();
    final copy = File('${dir.path}/$name');
    await file.copy(copy.path);
    await Share.shareXFiles([XFile(copy.path)], text: '증명·여권사진');
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/edit_mode.dart';
import '../services/face_landmarks.dart';
import '../services/image_pipeline.dart';
import '../services/outfit_overlay.dart';
import '../services/photo_process_api_service.dart';
import '../services/pipelines/gov_pipeline.dart';
import '../services/pipelines/profile_pipeline.dart';
import '../services/validators.dart';
import '../utils/constants.dart';

/// 여권/증명사진 보정 — 두 모드(관공서용 / 프로필용), 한 화면(스크롤 없음)
class PassportEditorPage extends StatefulWidget {
  const PassportEditorPage({super.key});

  @override
  State<PassportEditorPage> createState() => _PassportEditorPageState();
}

class _PassportEditorPageState extends State<PassportEditorPage> {
  EditMode _mode = EditMode.gov;
  File? _selectedFile;
  /// 미리보기/저장/공유는 반드시 이 바이트만 사용 (Image.memory, Gal, Share)
  Uint8List? _resultBytes;
  bool _loading = false;

  /// 관공서 모드: 배경 칩 변경 시 즉시 재합성용 캐시
  Uint8List? _cachedPersonImageBytes;
  Uint8List? _cachedMaskBytes;

  /// 관공서 모드에서 패딩 적용 시 '원본 구도상 여백을 보완했습니다' 배지 표시용
  bool _usedPaddingMode = false;

  /// 선택 배경색 (연하늘/연핑크/연보라)
  int _backgroundColor = PassportConstants.backgroundPastelSky;
  String _outfitTemplateId = PassportConstants.outfitTemplates.first['id'] as String;
  String _govOutputFormatId = PassportConstants.outputFormatProof;
  bool _enableResolutionEnhance = false;
  String _profilePresetId = PassportConstants.profilePresetNatural;

  static const double _screenPadding = 14.0;
  static const double _previewHeight = 230.0;
  static const double _previewRadius = 18.0;

  static final ImagePicker _picker = ImagePicker();

  void _onModeChanged(EditMode value) {
    if (value == _mode) return;
    setState(() {
      _mode = value;
      _resultBytes = null;
      _cachedPersonImageBytes = null;
      _cachedMaskBytes = null;
      _usedPaddingMode = false;
      _backgroundColor = PassportConstants.backgroundPastelSky;
      if (value == EditMode.gov) {
        _govOutputFormatId = PassportConstants.outputFormatProof;
      } else {
        _profilePresetId = PassportConstants.profilePresetNatural;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('여권/증명사진 보정'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ---------- 최상단 모드 탭 ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(_screenPadding, 8, _screenPadding, 6),
            child: SegmentedButton<EditMode>(
              segments: const [
                ButtonSegment<EditMode>(value: EditMode.gov, label: Text('관공서 제출용'), icon: Icon(Icons.badge_outlined, size: 18)),
                ButtonSegment<EditMode>(value: EditMode.profile, label: Text('프로필용'), icon: Icon(Icons.face_retouching_natural_outlined, size: 18)),
              ],
              selected: {_mode},
              onSelectionChanged: (Set<EditMode> s) {
                if (s.isNotEmpty) _onModeChanged(s.first);
              },
              style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          // ---------- Before/After 1:1 프리뷰 (탭으로 사진 선택) ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
            child: SizedBox(
              height: _previewHeight,
              child: Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(_previewRadius),
                child: InkWell(
                  onTap: _loading ? null : _pickPhoto,
                  borderRadius: BorderRadius.circular(_previewRadius),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_previewRadius),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                color: colorScheme.surfaceContainerHigh,
                                child: Text('Before', textAlign: TextAlign.center, style: theme.textTheme.labelSmall),
                              ),
                              Expanded(
                                child: _selectedFile != null
                                    ? Image.file(_selectedFile!, fit: BoxFit.cover)
                                    : Center(
                                        child: Icon(Icons.add_photo_alternate, size: 36, color: colorScheme.outline),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, color: colorScheme.outlineVariant),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                color: colorScheme.surfaceContainerHigh,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('After', textAlign: TextAlign.center, style: theme.textTheme.labelSmall),
                                    if (_mode == EditMode.gov && _usedPaddingMode)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '원본 구도상 여백을 보완했습니다',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.primary,
                                            fontSize: 10,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _resultBytes != null && _resultBytes!.isNotEmpty
                                    ? Image.memory(_resultBytes!, fit: BoxFit.cover)
                                    : Center(
                                        child: Text('-', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _mode.policyCopy,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
          const SizedBox(height: 8),

          // ---------- Primary CTA (모드별, 56dp, radius 16) ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
            child: SizedBox(
              height: 56,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_loading || _selectedFile == null) ? null : _runProofCorrection,
                icon: _loading
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                    : Icon(_mode == EditMode.gov ? Icons.auto_fix_high : Icons.auto_awesome, size: 24),
                label: Text(_mode.primaryButtonLabel),
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ---------- Secondary Row: [사진 선택], [단정한 옷(준비중)] ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.tonalIcon(
                      onPressed: _loading ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library, size: 20),
                      label: const Text('사진 선택'),
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('의상 기능은 준비 중입니다')));
                    },
                    child: Opacity(
                      opacity: 0.6,
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.tonalIcon(
                          onPressed: null,
                          icon: const Icon(Icons.checkroom, size: 20),
                          label: const Text('단정한 옷(준비중)'),
                          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ---------- 옵션 Card (Compact) ----------
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('배경 제거', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: PassportConstants.backgroundOptions.map((opt) {
                          final id = opt['id'] as String;
                          final label = opt['label'] as String;
                          final color = opt['color'] as int;
                          final selected = _backgroundColor == color;
                          return ChoiceChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              debugPrint('[PassportEditorPage] 배경 칩 클릭 selectedBgColor=0x${color.toRadixString(16)}');
                              setState(() => _backgroundColor = color);
                              _onBackgroundColorChanged(color);
                            },
                            selectedColor: colorScheme.primaryContainer,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                      if (_mode == EditMode.gov) ...[
                        const SizedBox(height: 8),
                        Text('출력 규격', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Row(
                          children: PassportConstants.govOutputFormats.map((f) {
                            final id = f['id'] as String;
                            final label = f['label'] as String;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: FilterChip(
                                  label: Text(label, style: const TextStyle(fontSize: 11)),
                                  selected: _govOutputFormatId == id,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _govOutputFormatId = id);
                                  },
                                  selectedColor: colorScheme.primaryContainer,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('해상도 1.5x', style: theme.textTheme.bodySmall),
                            Switch(
                              value: _enableResolutionEnhance,
                              onChanged: (v) => setState(() => _enableResolutionEnhance = v),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ],
                      if (_mode == EditMode.profile) ...[
                        const SizedBox(height: 8),
                        Text('보정 강도', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: PassportConstants.profilePresets.map((p) {
                            final id = p['id'] as String;
                            final label = p['label'] as String;
                            return ChoiceChip(
                              label: Text(label, style: const TextStyle(fontSize: 11)),
                              selected: _profilePresetId == id,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setState(() => _profilePresetId = id);
                              },
                              selectedColor: colorScheme.tertiaryContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_mode == EditMode.gov)
            Padding(
              padding: const EdgeInsets.fromLTRB(_screenPadding, 8, _screenPadding, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '※ 관공서 제출용은 외형 보정이 제한되며, 배경만 변경됩니다.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '※ 실제 제출 여부는 각 기관 기준을 확인해주세요.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

          // ---------- Sticky Bottom Bar ----------
          Container(
            padding: EdgeInsets.fromLTRB(_screenPadding, 8, _screenPadding, MediaQuery.paddingOf(context).bottom + 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [BoxShadow(color: colorScheme.shadow.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: (_resultBytes != null && _resultBytes!.isNotEmpty && !_loading) ? 1.0 : 0.5,
                    child: FilledButton.icon(
                      onPressed: (_resultBytes == null || _resultBytes!.isEmpty || _loading) ? null : _saveToGallery,
                      icon: const Icon(Icons.save_alt, size: 20),
                      label: const Text('저장'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Opacity(
                    opacity: (_resultBytes != null && _resultBytes!.isNotEmpty && !_loading) ? 1.0 : 0.5,
                    child: FilledButton.tonalIcon(
                      onPressed: (_resultBytes == null || _resultBytes!.isEmpty || _loading) ? null : _share,
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('공유'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    HapticFeedback.lightImpact();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('갤러리'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('카메라'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final x = await _picker.pickImage(source: source);
      if (x == null || !mounted) return;
      setState(() {
        _selectedFile = File(x.path);
        _resultBytes = null;
        _cachedPersonImageBytes = null;
        _cachedMaskBytes = null;
        _usedPaddingMode = false;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('사진 선택 실패: $e')));
    }
  }

  Future<void> _runProofCorrection() async {
    if (_selectedFile == null || _loading) return;
    setState(() => _loading = true);
    try {
      // 원격 API가 설정되어 있으면 먼저 시도, 실패 시 로컬 파이프라인 폴백
      if (PhotoProcessApiService.isConfigured) {
        try {
          final bytes = await _selectedFile!.readAsBytes();
          final modeStr = _mode == EditMode.gov ? 'gov' : 'profile';
          final resultBytes = await PhotoProcessApiService().processPhoto(
            imageBytes: Uint8List.fromList(bytes),
            mode: modeStr,
          );
          if (!mounted) return;
          setState(() {
            _loading = false;
            _resultBytes = resultBytes;
            if (_mode == EditMode.gov) {
              _cachedPersonImageBytes = null;
              _cachedMaskBytes = null;
              _usedPaddingMode = false;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _mode == EditMode.gov
                    ? '증명사진 보정 완료 (${PassportConstants.govPurposeLabel})'
                    : '프로필 보정 완료',
              ),
            ),
          );
          return;
        } on PhotoProcessApiException catch (e) {
          debugPrint('[PassportEditorPage] 원격 API 실패, 로컬 폴백: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('원격 보정 실패, 로컬 보정 시도: ${e.message}'), duration: const Duration(seconds: 3)),
            );
          }
        }
      }
      if (_mode == EditMode.gov) {
        await _runGovPipeline();
      } else {
        await _runProfilePipeline();
      }
    } catch (e, stack) {
      debugPrint('[PassportEditorPage] 보정 예외: $e');
      debugPrint('[PassportEditorPage] 스택: $stack');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('보정 실패: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// 배경 칩 변경 시: 캐시가 있으면 재보정 없이 단색 배경만 재합성해 After에 즉시 반영.
  Future<void> _onBackgroundColorChanged(int newColor) async {
    if (_mode != EditMode.gov ||
        _cachedPersonImageBytes == null ||
        _cachedMaskBytes == null ||
        !mounted) return;
    final bytes = await GovPipeline.recompositeWithBackground(
      cachedPersonImageBytes: _cachedPersonImageBytes!,
      cachedMaskBytes: _cachedMaskBytes!,
      backgroundColor: newColor,
      targetWidth: PassportConstants.outputWidthFor(_govOutputFormatId),
      targetHeight: PassportConstants.outputHeightFor(_govOutputFormatId),
    );
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() => _resultBytes = bytes);
      debugPrint('[PassportEditorPage] 프리뷰 Image.memory(resultBytes) 사용, length=${bytes.length}');
    }
  }

  Future<void> _runGovPipeline() async {
    debugPrint('[PassportEditorPage] runGovPipeline() 호출 source=${_selectedFile!.path}');
    final pipeline = GovPipeline();
    PipelineResult result;
    try {
      result = await pipeline.run(
        sourceFile: _selectedFile!,
        backgroundColor: _backgroundColor,
        outputFormatId: _govOutputFormatId,
        enableResolutionEnhance: _enableResolutionEnhance,
      );
    } catch (e, stack) {
      debugPrint('[PassportEditorPage] GovPipeline.run 예외: $e');
      debugPrint('[PassportEditorPage] 스택: $stack');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('관공서 보정 오류: $e'), duration: const Duration(seconds: 5)),
        );
      }
      return;
    }
    if (!mounted) return;
    Uint8List? resultBytes = result.resultImageBytes;
    if (resultBytes == null && result.file != null) {
      try {
        resultBytes = await result.file!.readAsBytes();
      } catch (e) {
        debugPrint('[PassportEditorPage] result.file 읽기 실패: $e');
      }
    }
    setState(() {
      _loading = false;
      _usedPaddingMode = result.usedPaddingMode;
      if (result.success && resultBytes != null && resultBytes.isNotEmpty) {
        _resultBytes = resultBytes;
        _cachedPersonImageBytes = result.cachedPersonImageBytes;
        _cachedMaskBytes = result.cachedMaskBytes;
        debugPrint('[PassportEditorPage] 관공서 보정 완료 length=${resultBytes.length}, usedPaddingMode=${result.usedPaddingMode}');
      } else {
        _cachedPersonImageBytes = null;
        _cachedMaskBytes = null;
        debugPrint('[PassportEditorPage] 관공서 보정 결과 없음 success=${result.success} resultBytes=${resultBytes?.length ?? 0} message=${result.message}');
      }
    });
    if (result.success && resultBytes != null && resultBytes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('증명사진 보정 완료 (${PassportConstants.govPurposeLabel})')),
      );
    } else if (mounted && (resultBytes == null || resultBytes.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? '보정 결과를 만들 수 없었습니다. 콘솔 로그를 확인해주세요.'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _runProfilePipeline() async {
    debugPrint('[PassportEditorPage] runProfilePipeline() 호출 source=${_selectedFile!.path} preset=$_profilePresetId');
    final pipeline = ProfilePipeline();
    PipelineResult result;
    try {
      result = await pipeline.run(
        sourceFile: _selectedFile!,
        presetId: _profilePresetId,
        backgroundColor: _backgroundColor,
      );
    } catch (e, stack) {
      debugPrint('[PassportEditorPage] ProfilePipeline.run 예외: $e');
      debugPrint('[PassportEditorPage] 스택: $stack');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('프로필 보정 오류: $e'), duration: const Duration(seconds: 5)),
        );
      }
      return;
    }
    if (!mounted) return;
    Uint8List? resultBytes = result.resultImageBytes;
    if (resultBytes == null && result.file != null) {
      try {
        resultBytes = await result.file!.readAsBytes();
      } catch (e) {
        debugPrint('[PassportEditorPage] result.file 읽기 실패: $e');
      }
    }
    setState(() {
      _loading = false;
      if (result.success && resultBytes != null && resultBytes.isNotEmpty) {
        _resultBytes = resultBytes;
        debugPrint('[PassportEditorPage] 프로필 보정 완료 length=${resultBytes.length}');
      } else {
        debugPrint('[PassportEditorPage] 프로필 보정 결과 없음 success=${result.success} resultBytes=${resultBytes?.length ?? 0} message=${result.message}');
      }
    });
    if (result.success && resultBytes != null && resultBytes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필 보정 완료')),
      );
    } else if (mounted && (resultBytes == null || resultBytes.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? '프로필 보정 결과를 만들 수 없었습니다. 콘솔 로그를 확인해주세요.'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    if (result.success && resultBytes != null && resultBytes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('프로필 보정 완료')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message ?? '다시 시도해 주세요.')));
    }
  }

  Future<void> _runOutfitOverlay() async {
    if (_selectedFile == null || _loading) return;
    setState(() => _loading = true);
    const failureMessage = '다른 템플릿을 선택하거나 다시 촬영해 주세요.';
    try {
      final bytes = await _selectedFile!.readAsBytes();
      final image = await _decodeImage(bytes);
      if (image == null || !mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미지 로드 실패')));
        return;
      }
      final faceService = FaceLandmarksService();
      final landmarks = await faceService.detect(bytes);
      if (landmarks == null || !mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('얼굴이 검출되지 않았습니다. 정면 사진을 사용해 주세요.'), backgroundColor: Colors.red.shade700),
        );
        return;
      }
      final template = PassportConstants.outfitTemplates.firstWhere(
        (t) => t['id'] == _outfitTemplateId,
        orElse: () => PassportConstants.outfitTemplates.first,
      );
      final path = template['path'] as String;
      final overlayService = OutfitOverlayService();
      final result = await overlayService.overlay(
        sourceImage: image,
        templateAssetPath: path,
        landmarks: landmarks,
      );
      if (!mounted) return;
      if (!result.success || result.image == null) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? failureMessage), backgroundColor: Colors.red.shade700),
        );
        return;
      }
      final outImage = result.image!;
      if (!Validators.checkFaceRegionUnchanged(image, outImage, landmarks.faceBounds, threshold: 0.02)) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('합성 품질이 낮습니다. 다른 템플릿을 선택하거나 다시 촬영해 주세요.'), backgroundColor: Colors.red.shade700),
        );
        return;
      }
      if (landmarks.neckShoulderPoints != null && landmarks.neckShoulderPoints!.length >= 3) {
        final neck = landmarks.neckShoulderPoints![0];
        final leftSh = landmarks.neckShoulderPoints![1];
        final rightSh = landmarks.neckShoulderPoints![2];
        final bandLeft = (leftSh[0] - 20).round().clamp(0, outImage.width - 1);
        final bandTop = (neck[1] + (leftSh[1] - neck[1]) * 0.5).round().clamp(0, outImage.height - 1);
        final bandW = ((rightSh[0] - leftSh[0] + 40).round()).clamp(1, outImage.width - bandLeft);
        final bandH = 30.clamp(1, outImage.height - bandTop);
        if (!Validators.checkEdgeArtifactLow(outImage, [bandLeft, bandTop, bandW, bandH], limit: 2500.0)) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('합성 품질이 낮습니다. 다른 템플릿을 선택하거나 다시 촬영해 주세요.'), backgroundColor: Colors.red.shade700),
          );
          return;
        }
      }
      final outDir = await getTemporaryDirectory();
      final outPath = '${outDir.path}/outfit_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File(outPath);
      final outBytes = _encodeJpg(outImage);
      await outFile.writeAsBytes(outBytes);
      setState(() {
        _resultBytes = Uint8List.fromList(outBytes);
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('의상 합성 완료 (${_mode == EditMode.gov ? PassportConstants.govPurposeLabel : "프로필"}')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('의상 합성 실패: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<img.Image?> _decodeImage(List<int> bytes) async {
    try {
      return img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  List<int> _encodeJpg(img.Image image) {
    return img.encodeJpg(image, quality: 92);
  }

  Future<void> _saveToGallery() async {
    if (_resultBytes == null || _resultBytes!.isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/passport_save_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final f = File(path);
      await f.writeAsBytes(_resultBytes!);
      await Gal.putImage(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('갤러리에 저장되었습니다.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  Future<void> _share() async {
    if (_resultBytes == null || _resultBytes!.isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/passport_share_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final f = File(path);
      await f.writeAsBytes(_resultBytes!);
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('공유 실패: $e')));
    }
  }
}

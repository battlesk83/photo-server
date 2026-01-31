import 'package:flutter/material.dart';

/// 규격: 한국 증명(3:4), 여권(35:45), 이력서
enum PhotoRatio {
  proof('한국 증명사진 (3:4)', 3 / 4, 354, 472),
  passport('여권사진 (35:45)', 35 / 45, 413, 531),
  resume('이력서 사진 (3:4)', 3 / 4, 354, 472);

  const PhotoRatio(this.label, this.aspectRatio, this.outputWidth, this.outputHeight);
  final String label;
  final double aspectRatio;
  final int outputWidth;
  final int outputHeight;
}

class RatioPicker extends StatelessWidget {
  const RatioPicker({super.key, required this.value, required this.onChanged});

  final PhotoRatio value;
  final ValueChanged<PhotoRatio> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PhotoRatio>(
      segments: PhotoRatio.values
          .map((r) => ButtonSegment<PhotoRatio>(value: r, label: Text(r.label)))
          .toList(),
      selected: {value},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
    );
  }
}

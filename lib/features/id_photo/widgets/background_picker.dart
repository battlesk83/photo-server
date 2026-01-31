import 'package:flutter/material.dart';

/// 배경: 흰색, 연회색, 연한 하늘색
enum BackgroundOption {
  white('흰색', 0xFFFFFFFF),
  lightGray('연회색', 0xFFF2F2F2),
  lightSkyBlue('연한 하늘색', 0xFFEAF2FF);

  const BackgroundOption(this.label, this.colorValue);
  final String label;
  final int colorValue;

  int get color => colorValue;
}

class BackgroundPicker extends StatelessWidget {
  const BackgroundPicker({super.key, required this.value, required this.onChanged});

  final BackgroundOption value;
  final ValueChanged<BackgroundOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<BackgroundOption>(
      segments: BackgroundOption.values
          .map((r) => ButtonSegment<BackgroundOption>(
                value: r,
                label: Text(r.label),
              ))
          .toList(),
      selected: {value},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
    );
  }
}

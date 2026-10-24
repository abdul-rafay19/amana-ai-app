import 'package:flutter/material.dart';

import '../theme.dart';
import '../util.dart';

/// Pill-shaped segmented control (language, voice language, auto-lock time).
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool compact;
  const Segmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 16, vertical: compact ? 6 : 9),
              decoration: BoxDecoration(
                color: i == index ? C.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: i == index
                    ? const [BoxShadow(color: C.shadow, blurRadius: 6, offset: Offset(0, 2))]
                    : null,
              ),
              child: Text(
                labels[i],
                style: T.body(hasUrdu(labels[i]),
                    size: compact ? 13 : 14.5,
                    w: i == index ? FontWeight.w800 : FontWeight.w600,
                    color: i == index ? C.indigo : C.mute),
              ),
            ),
          ),
      ]),
    );
  }
}

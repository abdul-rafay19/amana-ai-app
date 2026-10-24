import 'package:flutter/material.dart';

import '../theme.dart';

/// Four dots that fill as digits are typed.
class PinDots extends StatelessWidget {
  final int filled;
  final bool error;
  const PinDots({super.key, required this.filled, this.error = false});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final on = i < filled;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? (error ? C.madder : C.indigo) : C.white,
              border: Border.all(color: error ? C.madder : C.indigo2, width: 2),
            ),
          );
        }),
      ),
    );
  }
}

/// Phone-style keypad. Never mirrored in right-to-left layouts.
class Keypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBack;
  final bool enabled;
  const Keypad({super.key, required this.onDigit, required this.onBack, this.enabled = true});

  Widget _key(Widget child, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.all(7),
      child: Material(
        color: C.white,
        shape: const CircleBorder(side: BorderSide(color: C.line)),
        child: InkResponse(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(width: 68, height: 68, child: Center(child: child)),
        ),
      ),
    );
  }

  Widget _digit(String d) =>
      _key(Text(d, style: T.number(size: 26, w: FontWeight.w600)), () => onDigit(d));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [_digit('1'), _digit('2'), _digit('3')]),
          Row(mainAxisSize: MainAxisSize.min, children: [_digit('4'), _digit('5'), _digit('6')]),
          Row(mainAxisSize: MainAxisSize.min, children: [_digit('7'), _digit('8'), _digit('9')]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 82, height: 82),
            _digit('0'),
            _key(const Icon(Icons.backspace_outlined, color: C.indigo), onBack),
          ]),
        ]),
      ),
    );
  }
}

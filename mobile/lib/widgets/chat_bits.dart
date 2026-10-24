import 'package:flutter/material.dart';

import '../theme.dart';
import '../util.dart';
import 'mark.dart';

/// Amana's round avatar (a spool of thread).
class AmanaAvatar extends StatelessWidget {
  final double size;
  const AmanaAvatar({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) => AmanaMark(size: size);
}

class Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  const Bubble({super.key, required this.text, required this.mine});

  @override
  Widget build(BuildContext context) {
    final rtl = hasUrdu(text);
    final maxW = MediaQuery.of(context).size.width * 0.78;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? C.indigo : C.white,
        border: mine ? null : Border.all(color: C.line),
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(18),
          topEnd: const Radius.circular(18),
          bottomStart: Radius.circular(mine ? 18 : 4),
          bottomEnd: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Text(
        text,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        style: T.body(rtl, size: 16, color: mine ? C.white : C.ink),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: mine
            ? [bubble]
            : [const AmanaAvatar(), const SizedBox(width: 8), Flexible(child: bubble)],
      ),
    );
  }
}

/// "Amana is typing" dots.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});
  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        const AmanaAvatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: C.white,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
                final phase = (_c.value + i * 0.18) % 1.0;
                final up = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(C.line, C.indigo2, up),
                  ),
                );
              }));
            },
          ),
        ),
      ]),
    );
  }
}

/// Big round microphone button. Pulses while recording.
class MicButton extends StatefulWidget {
  final bool recording;
  final bool busy;
  final VoidCallback? onTap;
  final double size;
  const MicButton(
      {super.key, required this.recording, required this.busy, required this.onTap, this.size = 56});
  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s + 28,
      height: s + 28,
      child: Stack(alignment: Alignment.center, children: [
        if (widget.recording)
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = _c.value;
              return Container(
                width: s + 28 * v,
                height: s + 28 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromRGBO(178, 51, 74, 0.28 * (1 - v)),
                ),
              );
            },
          ),
        Material(
          color: widget.recording ? C.madder : C.indigo,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkResponse(
            customBorder: const CircleBorder(),
            onTap: widget.busy ? null : widget.onTap,
            child: SizedBox(
              width: s,
              height: s,
              child: Center(
                child: widget.busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: C.white))
                    : Icon(widget.recording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: C.white, size: s * 0.52),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

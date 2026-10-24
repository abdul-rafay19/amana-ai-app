import 'package:flutter/material.dart';

import '../theme.dart';
import '../util.dart';

double _c01(double v) => v < 0 ? 0.0 : (v > 1 ? 1.0 : v);

// ====================================================================== painters
class _DotLeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFB4BBD9);
    final y = size.height / 2;
    for (double x = 1; x < size.width; x += 5) {
      canvas.drawCircle(Offset(x, y), 0.9, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _StitchPainter extends CustomPainter {
  final Color color;
  _StitchPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, y), Offset(x + 6, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _StitchPainter old) => old.color != color;
}

class _AjrakPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = C.indigo);
    final big = Paint()..color = C.madder;
    final small = Paint()..color = C.white;
    final h = size.height;
    final cy = h / 2;
    for (double x = 0; x < size.width + h; x += h * 1.15) {
      final cx = x + h / 2;
      final d1 = Path()
        ..moveTo(cx, cy - h * 0.42)
        ..lineTo(cx + h * 0.42, cy)
        ..lineTo(cx, cy + h * 0.42)
        ..lineTo(cx - h * 0.42, cy)
        ..close();
      canvas.drawPath(d1, big);
      final d2 = Path()
        ..moveTo(cx, cy - h * 0.16)
        ..lineTo(cx + h * 0.16, cy)
        ..lineTo(cx, cy + h * 0.16)
        ..lineTo(cx - h * 0.16, cy)
        ..close();
      canvas.drawPath(d2, small);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Dashed "running stitch" divider.
class StitchDivider extends StatelessWidget {
  final Color color;
  const StitchDivider({super.key, this.color = C.line});
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 4, width: double.infinity, child: CustomPaint(painter: _StitchPainter(color)));
}

/// Ajrak diamond lattice strip (brand mark).
class AjrakStrip extends StatelessWidget {
  final double height;
  const AjrakStrip({super.key, this.height = 12});
  @override
  Widget build(BuildContext context) => SizedBox(
      height: height, width: double.infinity, child: CustomPaint(painter: _AjrakPainter()));
}

// ====================================================================== card + buttons
class AmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color border;
  const AmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = C.white,
    this.border = C.line,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: const [BoxShadow(color: C.shadow, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

enum BtnKind { primary, secondary, outline, danger }

class AmButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool busy;
  final bool ur;
  final IconData? icon;
  final bool expand;
  const AmButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = BtnKind.primary,
    this.busy = false,
    this.ur = false,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    Color bg;
    Color fg;
    Color bd;
    switch (kind) {
      case BtnKind.primary:
        bg = C.madder;
        fg = C.white;
        bd = C.madder;
        break;
      case BtnKind.secondary:
        bg = C.tint;
        fg = C.indigo;
        bd = C.tint;
        break;
      case BtnKind.outline:
        bg = C.white;
        fg = C.indigo;
        bd = C.line;
        break;
      case BtnKind.danger:
        bg = C.white;
        fg = C.madder;
        bd = C.madder;
        break;
    }
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              textAlign: TextAlign.center,
              style: T.body(ur, size: 16, w: FontWeight.w700, color: fg)),
        ),
      ],
    );
    return Opacity(
      opacity: (onTap == null && !busy) ? 0.45 : 1,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: bd)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded tag.
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool ur;
  const Pill(this.text,
      {super.key, this.bg = C.tint, this.fg = C.indigo, this.icon, this.ur = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
        Flexible(
            child: Text(text, style: T.body(ur, size: 12.5, w: FontWeight.w700, color: fg))),
      ]),
    );
  }
}

class IntegrityBadge extends StatelessWidget {
  final bool ok;
  final String text;
  final bool ur;
  const IntegrityBadge({super.key, required this.ok, required this.text, this.ur = false});
  @override
  Widget build(BuildContext context) {
    return Pill(text,
        bg: ok ? C.leafBg : C.madderBg,
        fg: ok ? C.leaf : C.madder,
        icon: ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
        ur: ur);
  }
}

// ====================================================================== text bits
class SectionTitle extends StatelessWidget {
  final String text;
  final bool ur;
  final double size;
  const SectionTitle(this.text, {super.key, required this.ur, this.size = 20});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: T.display(ur, size: size)),
      );
}

class Muted extends StatelessWidget {
  final String text;
  final bool ur;
  final double size;
  const Muted(this.text, {super.key, required this.ur, this.size = 13.5});
  @override
  Widget build(BuildContext context) => Text(text,
      textDirection: dirOf(text), style: T.body(ur, size: size, color: C.mute));
}

// ====================================================================== ledger
enum LKind { normal, dim, big, warn, good }

class LRow {
  final String? label;
  final String? value;
  final LKind kind;
  final bool rule;
  const LRow(this.label, this.value, [this.kind = LKind.normal]) : rule = false;
  const LRow.rule()
      : label = null,
        value = null,
        kind = LKind.normal,
        rule = true;
}

/// Khata-style rows with dotted leaders between the label and the amount.
class Ledger extends StatelessWidget {
  final List<LRow> rows;
  final bool ur;
  const Ledger({super.key, required this.rows, required this.ur});

  TextStyle _valueStyle(LRow r) {
    final v = r.value ?? '';
    if (hasUrdu(v) || RegExp(r'[A-Za-z]{4,}').hasMatch(v)) {
      return T.body(ur,
          size: 14.5, w: FontWeight.w600, color: r.kind == LKind.dim ? C.mute : C.ink);
    }
    switch (r.kind) {
      case LKind.big:
        return T.number(size: 24, color: C.indigo);
      case LKind.warn:
        return T.number(size: 18, color: C.madder);
      case LKind.good:
        return T.number(size: 18, color: C.leaf);
      case LKind.dim:
        return T.number(size: 17, color: C.mute, w: FontWeight.w500);
      case LKind.normal:
        return T.number(size: 17, w: FontWeight.w600);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          if (r.rule)
            const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: StitchDivider())
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(r.label ?? '',
                        style: T.body(ur,
                            size: 14.5,
                            color: r.kind == LKind.dim ? C.mute : C.ink,
                            w: r.kind == LKind.big ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                      child: SizedBox(
                          height: 2, child: CustomPaint(painter: _DotLeaderPainter())),
                    ),
                  ),
                  Text(r.value ?? '', style: _valueStyle(r)),
                ],
              ),
            ),
      ],
    );
  }
}

// ====================================================================== notes + flags
/// "Amana's note": the AI-written explanation, with a madder accent bar.
class AiNote extends StatelessWidget {
  final String label;
  final String text;
  final bool ur;
  const AiNote({super.key, required this.label, required this.text, required this.ur});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: C.white,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: C.madder),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, size: 16, color: C.madder),
                    const SizedBox(width: 6),
                    Text(label, style: T.body(ur, size: 13, w: FontWeight.w800, color: C.madder)),
                  ]),
                  const SizedBox(height: 6),
                  Text(text, textDirection: dirOf(text), style: T.body(hasUrdu(text) || ur, size: 15.5)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class FlagTile extends StatelessWidget {
  final String level; // red | amber | green
  final String text;
  final bool ur;
  const FlagTile({super.key, required this.level, required this.text, required this.ur});
  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData ic;
    switch (level) {
      case 'red':
        bg = C.madderBg;
        fg = C.madder;
        ic = Icons.error_outline_rounded;
        break;
      case 'green':
        bg = C.leafBg;
        fg = C.leaf;
        ic = Icons.check_circle_outline_rounded;
        break;
      default:
        bg = C.amberBg;
        fg = C.amber;
        ic = Icons.warning_amber_rounded;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ic, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                textDirection: dirOf(text),
                style: T.body(hasUrdu(text) || ur, size: 14.5, color: C.ink))),
      ]),
    );
  }
}

// ====================================================================== text fields
class AmField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool ur;
  final TextInputType? keyboard;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  final int? maxLength;
  final String? prefix;
  const AmField({
    super.key,
    required this.controller,
    required this.label,
    required this.ur,
    this.keyboard,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
    this.obscure = false,
    this.maxLength,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: T.body(ur, size: 13.5, w: FontWeight.w600, color: C.mute)),
        ),
      TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 3 : 1,
        onChanged: onChanged,
        obscureText: obscure,
        maxLength: maxLength,
        textDirection: null,
        style: T.body(ur, size: 16.5),
        decoration: InputDecoration(
          filled: true,
          fillColor: C.white,
          hintText: hint,
          hintStyle: T.body(ur, size: 15, color: C.mute),
          prefixText: prefix,
          prefixStyle: T.body(false, size: 16, color: C.mute, w: FontWeight.w600),
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: b(C.line),
          enabledBorder: b(C.line),
          focusedBorder: b(C.indigo2, 1.8),
        ),
      ),
    ]);
  }
}

// ====================================================================== stamp
/// "Agreement saved" stamp that lands with a small bounce.
class Seal extends StatelessWidget {
  const Seal({super.key});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutBack,
      builder: (context, v, child) {
        return Opacity(
          opacity: _c01(v * 1.6),
          child: Transform.rotate(
            angle: -0.2,
            child: Transform.scale(scale: 1.9 - 0.9 * v, child: child),
          ),
        );
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: C.madderBg,
          border: Border.all(color: C.madder, width: 3),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_rounded, color: C.madder, size: 38),
          Text('AMANA',
              style: T.number(size: 11.5, color: C.madder, w: FontWeight.w800)
                  .copyWith(letterSpacing: 2)),
        ]),
      ),
    );
  }
}

/// Section label with a stitched underline.
class Stitched extends StatelessWidget {
  final String text;
  final bool ur;
  const Stitched(this.text, {super.key, required this.ur});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: T.display(ur, size: 18)),
          const SizedBox(height: 6),
          const StitchDivider(),
          const SizedBox(height: 10),
        ],
      );
}

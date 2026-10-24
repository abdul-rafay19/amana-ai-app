import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

Color _c(int r, int g, int b, double o) => Color.fromRGBO(r, g, b, o < 0 ? 0 : (o > 1 ? 1 : o));

/// Draws the Amana emblem (trust seal + ajrak ring + "A" with running stitches).
/// Same geometry as tools/make_brand.py. [t] 0..1 builds it up piece by piece (splash animation).
class EmblemPainter extends CustomPainter {
  final double t;
  EmblemPainter([this.t = 1.0]);

  double _p(double a, double b) {
    final v = (t - a) / (b - a);
    final c = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    return Curves.easeOutCubic.transform(c);
  }

  Path _diamond(double cx, double cy, double r) => Path()
    ..moveTo(cx, cy - r)
    ..lineTo(cx + r, cy)
    ..lineTo(cx, cy + r)
    ..lineTo(cx - r, cy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1000.0;
    Paint mk(Color col) => Paint()..color = col..isAntiAlias = true;
    final white = mk(_c(255, 255, 255, 1));
    final indigo = mk(_c(36, 48, 99, 1));
    final madder = mk(_c(178, 51, 74, 1));

    // four corner diamonds
    final pc = _p(0.0, 0.3);
    for (final d in const [Offset(0, -1), Offset(1, 0), Offset(0, 1), Offset(-1, 0)]) {
      canvas.drawPath(_diamond((500 + d.dx * 452) * k, (500 + d.dy * 452) * k, 36 * k * pc), white);
    }
    // white seal
    canvas.drawCircle(Offset(500 * k, 500 * k), 392 * k * _p(0.05, 0.45), white);
    // ajrak ring of 16 small diamonds
    for (var i = 0; i < 16; i++) {
      final a = i * 2 * math.pi / 16;
      final pr = _p(0.32 + i * 0.012, 0.52 + i * 0.012);
      canvas.drawPath(_diamond((500 + 359 * math.cos(a)) * k, (500 + 359 * math.sin(a)) * k, 17 * k * pr), indigo);
    }
    // madder disc + thin ring
    canvas.drawCircle(Offset(500 * k, 500 * k), 326 * k * _p(0.25, 0.6), madder);
    canvas.drawCircle(
        Offset(500 * k, 500 * k),
        300 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * k
          ..color = _c(255, 255, 255, 0.47 * _p(0.55, 0.72))
          ..isAntiAlias = true);
    // the A
    final pa = _p(0.5, 0.85);
    if (pa > 0) {
      canvas.save();
      canvas.translate(0, (1 - pa) * 26 * k);
      final ap = mk(_c(255, 255, 255, pa));
      Path leg(List<Offset> pts) {
        final p = Path()..moveTo(pts[0].dx * k, pts[0].dy * k);
        for (final o in pts.skip(1)) {
          p.lineTo(o.dx * k, o.dy * k);
        }
        return p..close();
      }

      canvas.drawPath(leg(const [Offset(468, 262), Offset(532, 262), Offset(382, 728), Offset(314, 728)]), ap);
      canvas.drawPath(leg(const [Offset(468, 262), Offset(532, 262), Offset(686, 728), Offset(618, 728)]), ap);
      canvas.restore();
    }
    // three running stitches (the crossbar)
    const sw = 34.0, sh = 22.0, gap = 8.0;
    const total = 3 * sw + 2 * gap;
    for (var i = 0; i < 3; i++) {
      final ps = _p(0.72 + i * 0.07, 0.86 + i * 0.07);
      if (ps <= 0) continue;
      final x = 500 - total / 2 + i * (sw + gap);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x * k, 566 * k, sw * k * ps, sh * k), Radius.circular(10 * k)), white);
    }
  }

  @override
  bool shouldRepaint(covariant EmblemPainter old) => old.t != t;
}

/// The Amana mark. With [bg] it sits on the indigo rounded square (like the app icon).
class AmanaMark extends StatelessWidget {
  final double size;
  final bool bg;
  const AmanaMark({super.key, this.size = 40, this.bg = true});

  @override
  Widget build(BuildContext context) {
    final emblem = CustomPaint(painter: EmblemPainter(), size: Size.square(bg ? size * 0.9 : size));
    if (!bg) return SizedBox(width: size, height: size, child: emblem);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: C.indigo, borderRadius: BorderRadius.circular(size * 0.224)),
      child: emblem,
    );
  }
}

/// Emblem that builds itself up once (used on the splash screen).
class AnimatedEmblem extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  const AnimatedEmblem({super.key, required this.animation, this.size = 200});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) =>
          CustomPaint(painter: EmblemPainter(animation.value), size: Size.square(size)),
    );
  }
}

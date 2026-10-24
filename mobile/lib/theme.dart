import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens: Sindhi ajrak block print + the home ledger (khata).
class C {
  static const indigo = Color(0xFF243063);
  static const indigo2 = Color(0xFF3A4A94);
  static const ink = Color(0xFF1B2142);
  static const bg = Color(0xFFF5F6FA);
  static const tint = Color(0xFFE9ECF6);
  static const line = Color(0xFFD9DDEC);
  static const madder = Color(0xFFB2334A); // main call-to-action
  static const madderBg = Color(0xFFFBE8EB);
  static const leaf = Color(0xFF2E7D5B);
  static const leafBg = Color(0xFFE3F2EA);
  static const amber = Color(0xFFA66A0B);
  static const amberBg = Color(0xFFFCF0D8);
  static const mute = Color(0xFF5B6285);
  static const dark = Color(0xFF10143A);
  static const white = Color(0xFFFFFFFF);
  static const shadow = Color(0x14243063); // indigo at ~8%
  static const scrim = Color(0x99101436);
}

/// Text styles. English: Bricolage Grotesque (display) + Figtree (body).
/// Urdu: Noto Nastaliq Urdu (display) + Noto Naskh Arabic (body).
class T {
  static TextStyle display(bool ur,
      {double size = 24, FontWeight w = FontWeight.w700, Color color = C.ink}) {
    if (ur) {
      return GoogleFonts.notoNastaliqUrdu(
          fontSize: size * 0.82, fontWeight: w, color: color, height: 1.9);
    }
    return GoogleFonts.bricolageGrotesque(
        fontSize: size, fontWeight: w, color: color, height: 1.15);
  }

  static TextStyle body(bool ur,
      {double size = 15, FontWeight w = FontWeight.w400, Color color = C.ink, double? height}) {
    if (ur) {
      return GoogleFonts.notoNaskhArabic(
          fontSize: size + 1, fontWeight: w, color: color, height: height ?? 1.75);
    }
    return GoogleFonts.figtree(
        fontSize: size, fontWeight: w, color: color, height: height ?? 1.4);
  }

  /// Digits and money always use the display face so they stay crisp and aligned.
  static TextStyle number({double size = 28, Color color = C.ink, FontWeight w = FontWeight.w700}) {
    return GoogleFonts.bricolageGrotesque(
        fontSize: size, fontWeight: w, color: color, height: 1.1);
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.indigo, primary: C.indigo, secondary: C.madder);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    splashFactory: InkRipple.splashFactory,
  );
}

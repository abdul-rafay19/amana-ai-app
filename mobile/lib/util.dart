import 'dart:ui' show TextDirection;

/// Small typed accessors for the JSON maps the API returns.
extension JX on Map<String, dynamic> {
  String? s(String k) {
    final v = this[k];
    return v == null ? null : v.toString();
  }

  num? n(String k) {
    final v = this[k];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  bool b(String k) => this[k] == true;

  Map<String, dynamic> m(String k) {
    final v = this[k];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  List<dynamic> l(String k) {
    final v = this[k];
    return v is List ? v : <dynamic>[];
  }
}

String _group(String digits) {
  final neg = digits.startsWith('-');
  final d = neg ? digits.substring(1) : digits;
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i > 0 && (d.length - i) % 3 == 0) b.write(',');
    b.write(d[i]);
  }
  return (neg ? '-' : '') + b.toString();
}

/// Same output style as calc.fmt_rs on the server: "Rs 7,500" or "Rs 72.22".
String fmtRs(num? x) {
  if (x == null) return '-';
  final v = x.toDouble();
  if ((v - v.roundToDouble()).abs() < 1e-9) return 'Rs ${_group(v.round().toString())}';
  final parts = v.toStringAsFixed(2).split('.');
  return 'Rs ${_group(parts[0])}.${parts[1]}';
}

/// 90 -> "90", 2.5 -> "2.5"
String fmtNum(num? x) {
  if (x == null) return '-';
  final v = x.toDouble();
  if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

final RegExp _rtl = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

/// True when the text contains Urdu/Arabic script (so we can pick the right font and direction).
bool hasUrdu(String s) => _rtl.hasMatch(s);

TextDirection dirOf(String s) => hasUrdu(s) ? TextDirection.rtl : TextDirection.ltr;

/// "2026-10-18T10:20:30+00:00" -> "2026-10-18"
String dateOf(String? iso) => (iso == null || iso.length < 10) ? '' : iso.substring(0, 10);

String shortHash(String? h, [int n = 12]) => (h == null || h.length < n) ? (h ?? '') : '${h.substring(0, n)}…';

/// Parses a user-typed amount like "6,500" or "۶۵۰۰". Returns null if it is not a number.
double? parseAmount(String raw) {
  const ur = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in raw.trim().split('')) {
    final i = ur.indexOf(ch);
    final j = ar.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch != ',' && ch != ' ' && ch != '٬') {
      b.write(ch);
    }
  }
  final s = b.toString();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// 1500 -> "1,500" (like Python's f"{v:,.0f}")
String comma0(num v) => _group(v.toDouble().round().toString());

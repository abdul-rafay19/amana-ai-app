import '../util.dart';

/// Same role as ValueError in the Python backend.
class ValueError implements Exception {
  final String message;
  ValueError(this.message);
  @override
  String toString() => message;
}

double _r2(double v) => (v * 100 + (v >= 0 ? 1e-7 : -1e-7)).roundToDouble() / 100;

/// Round to 2 decimals; whole numbers come back as int (matches calc._out in Python).
num out(double v) {
  final r = _r2(v);
  return r == r.truncateToDouble() ? r.toInt() : r;
}

double toD(Object? x) {
  if (x == null || x is bool) throw ValueError('number expected');
  if (x is num) return x.toDouble();
  final v = double.tryParse(x.toString().trim());
  if (v == null) throw ValueError('number expected');
  return v;
}

num expectedTotal(Object? quantity, Object? rate) {
  final q = toD(quantity), r = toD(rate);
  if (q <= 0 || r <= 0) throw ValueError('quantity and rate must be greater than zero');
  return out(q * r);
}

/// Expected payment, earnings after direct expenses, hourly rate. The AI never does this arithmetic.
Map<String, dynamic> calculateDeal(Object? quantity, Object? rate, [Object? expenses, Object? hours]) {
  final q = toD(quantity);
  final total = toD(expectedTotal(quantity, rate));
  final o = <String, dynamic>{
    'quantity': q.truncate(),
    'rate_per_piece': out(toD(rate)),
    'expected_total': out(total),
    'material_expenses': null,
    'net_after_expenses': null,
    'estimated_hours': null,
    'hourly_net': null,
    'hourly_gross': null,
    'net_per_piece': null,
    'expense_share_pct': null,
  };
  double? h;
  if (hours != null) {
    h = toD(hours);
    if (h <= 0) throw ValueError('hours must be greater than zero');
    o['estimated_hours'] = out(h);
    o['hourly_gross'] = out(total / h);
  }
  if (expenses != null) {
    final e = toD(expenses);
    if (e < 0) throw ValueError('expenses cannot be negative');
    final net = total - e;
    o['material_expenses'] = out(e);
    o['net_after_expenses'] = out(net);
    o['net_per_piece'] = out(net / q);
    o['expense_share_pct'] = out(e / total * 100);
    if (h != null) o['hourly_net'] = out(net / h);
  }
  return o;
}

/// Rate per piece needed so that (total - expenses) / hours reaches her own target.
Map<String, dynamic> requiredRateForTarget(
    Object? quantity, Object? expenses, Object? hours, Object? targetHourly, Object? currentRate) {
  final q = toD(quantity), h = toD(hours), t = toD(targetHourly);
  final e = expenses == null ? 0.0 : toD(expenses);
  if (q <= 0 || h <= 0 || t <= 0) throw ValueError('quantity, hours and target must be greater than zero');
  final needed = (t * h + e) / q;
  final rate = ((needed * 1e6).roundToDouble() / 1e6).ceilToDouble();
  final cur = toD(currentRate);
  final newTotal = rate * q;
  return {
    'target_hourly': out(t),
    'current_rate': out(cur),
    'suggested_rate': out(rate),
    'new_total': out(newTotal),
    'new_net': out(newTotal - e),
    'new_hourly_net': out((newTotal - e) / h),
    'increase_pct': cur > 0 ? out((rate - cur) / cur * 100) : null,
    'already_meets_target': cur >= rate,
  };
}

/// advance_paid = money paid to her earlier (not part of `received`).
/// agreed_deductions = deductions both sides agreed to in advance.
Map<String, dynamic> comparePayment(Object? expected, Object? received,
    {Object? advancePaid, Object? agreedDeductions, bool isPartial = false}) {
  final ex = _r2(toD(expected)), rc = _r2(toD(received));
  final ad = _r2(advancePaid == null ? 0.0 : toD(advancePaid));
  final dd = _r2(agreedDeductions == null ? 0.0 : toD(agreedDeductions));
  if (ex <= 0) throw ValueError('expected amount must be greater than zero');
  if (rc < 0 || ad < 0 || dd < 0) throw ValueError('amounts cannot be negative');
  final difference = _r2(ex - rc);
  final explained = _r2(ad + dd);
  final unexplained = _r2(difference - explained);
  String status;
  if (difference == 0) {
    status = 'match';
  } else if (unexplained == 0) {
    status = 'explained';
  } else if (unexplained < 0) {
    status = 'over';
  } else if (isPartial) {
    status = 'partial_pending';
  } else {
    status = 'short';
  }
  return {
    'expected': out(ex),
    'received': out(rc),
    'advance_paid': out(ad),
    'agreed_deductions': out(dd),
    'difference': out(difference),
    'explained': out(explained),
    'unexplained': out(unexplained),
    'total_received_incl_advance': out(rc + ad),
    'is_partial': isPartial,
    'status': status,
  };
}

final RegExp _vagueDeduction =
    RegExp(r'(deduct|katt?|cutting|penalt|fine|کٹوتی|جرمانہ)', caseSensitive: false);

/// Rule-based flags. Each has level (red/amber/green), en and ur text.
List<Map<String, dynamic>> analyzeRisks(Map<String, dynamic> order, Map<String, dynamic>? calc, [num? minHourly]) {
  final flags = <Map<String, dynamic>>[];
  void add(String level, String code, String en, String ur) =>
      flags.add({'level': level, 'code': code, 'en': en, 'ur': ur});

  if (order['payment_terms'] == null || order['payment_terms'].toString().isEmpty) {
    add('amber', 'no_payment_terms',
        'No payment date or method was agreed. Ask when and how you will be paid.',
        'ادائیگی کی تاریخ یا طریقہ طے نہیں ہوا۔ پوچھ لیں کہ پیسے کب اور کیسے ملیں گے۔');
  }
  if (order['material_expenses'] == null) {
    add('amber', 'no_expenses',
        'Material and other costs are not entered, so your real earning may be lower than shown.',
        'مٹیریل اور دوسرے خرچے درج نہیں ہوئے، اس لیے اصل کمائی دکھائی گئی رقم سے کم ہو سکتی ہے۔');
  }
  if (order['estimated_hours'] == null) {
    add('amber', 'no_hours', 'Working hours are missing, so the hourly earning cannot be shown.',
        'کام کے گھنٹے معلوم نہیں، اس لیے فی گھنٹہ کمائی نہیں دکھائی جا سکتی۔');
  }
  if (order['deadline_days'] == null) {
    add('amber', 'no_deadline', 'No deadline was agreed.', 'ڈیڈ لائن طے نہیں ہوئی۔');
  }

  final pct = calc?['expense_share_pct'];
  if (pct is num && pct >= 30) {
    final lvl = pct >= 50 ? 'red' : 'amber';
    add(lvl, 'high_expense', 'Costs take ${fmtNum(pct)}% of the total payment.',
        'خرچے کل ادائیگی کا ${fmtNum(pct)}% کھا جاتے ہیں۔');
  }

  final hrs = order['estimated_hours'], days = order['deadline_days'];
  if (hrs is num && days is num && hrs != 0 && days != 0) {
    final perDay = (hrs.toDouble() / days.toDouble() * 10).roundToDouble() / 10;
    if (perDay > 8) {
      add(perDay > 12 ? 'red' : 'amber', 'tight_deadline',
          'This needs about ${fmtNum(perDay)} hours of work every day to finish on time.',
          'وقت پر مکمل کرنے کے لیے روزانہ تقریباً ${fmtNum(perDay)} گھنٹے کام کرنا ہوگا۔');
    }
  }

  final hourly = calc?['hourly_net'];
  if (minHourly != null && minHourly != 0 && hourly is num && hourly < minHourly) {
    add('amber', 'below_target',
        'Estimated earning is ${fmtRs(hourly)}/hour, below your own target of ${fmtRs(minHourly)}/hour.',
        'اندازاً کمائی ${fmtRs(hourly)} فی گھنٹہ ہے، جو آپ کے اپنے ہدف ${fmtRs(minHourly)} سے کم ہے۔');
  }

  final terms = ['other_terms', 'payment_terms'].map((k) => (order[k] ?? '').toString()).join(' ');
  if (_vagueDeduction.hasMatch(terms) && !RegExp(r'\d').hasMatch(terms)) {
    add('amber', 'vague_deductions', 'Deductions are mentioned but no amount or reason is written down.',
        'کٹوتی کا ذکر ہے لیکن رقم یا وجہ طے نہیں ہوئی۔');
  }

  if (flags.isEmpty) {
    add('green', 'all_clear', 'Nothing unclear found in the details you gave.',
        'آپ کی بتائی ہوئی تفصیلات میں کوئی مبہم بات نہیں ملی۔');
  }
  return flags;
}

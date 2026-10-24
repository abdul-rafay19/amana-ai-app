/// Validation of order fields (mirrors the pydantic OrderDraft in schemas.py).
const List<String> kFields = [
  'item',
  'quantity',
  'rate_per_piece',
  'deadline_days',
  'material_expenses',
  'estimated_hours',
  'payment_terms',
  'contractor_name',
  'other_terms',
  'advance_received',
];
const List<String> kRequired = ['quantity', 'rate_per_piece'];
const List<String> kAskOrder = [
  'quantity',
  'rate_per_piece',
  'material_expenses',
  'estimated_hours',
  'deadline_days',
  'payment_terms',
];

class _Res {
  final dynamic value;
  final String? error;
  _Res(this.value, [this.error]);
}

num? _num(Object? v) {
  if (v is bool) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

_Res _str(Object? v, int max) {
  if (v is! String) return _Res(null, 'Input should be a valid string');
  final s = v.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');
  if (s.length > max) return _Res(null, 'String should have at most $max characters');
  return _Res(s.isEmpty ? null : s);
}

_Res _int(Object? v, int min, int max) {
  final n = _num(v);
  if (n == null) return _Res(null, 'Input should be a valid integer');
  if (n != n.truncate()) return _Res(null, 'Input should be a valid integer, got a number with a fractional part');
  final i = n.toInt();
  if (i < min) return _Res(null, 'Input should be greater than or equal to $min');
  if (i > max) return _Res(null, 'Input should be less than or equal to $max');
  return _Res(i);
}

_Res _float(Object? v, {required bool positive, required double max}) {
  final n = _num(v);
  if (n == null) return _Res(null, 'Input should be a valid number');
  final d = n.toDouble();
  if (positive ? d <= 0 : d < 0) {
    return _Res(null, positive ? 'Input should be greater than 0' : 'Input should be greater than or equal to 0');
  }
  if (d > max) return _Res(null, 'Input should be less than or equal to $max');
  return _Res(d);
}

_Res _validate(String k, Object? v) {
  switch (k) {
    case 'item':
      return _str(v, 60);
    case 'payment_terms':
      return _str(v, 200);
    case 'contractor_name':
      return _str(v, 80);
    case 'other_terms':
      return _str(v, 300);
    case 'quantity':
      return _int(v, 1, 1000000);
    case 'deadline_days':
      return _int(v, 1, 365);
    case 'rate_per_piece':
      return _float(v, positive: true, max: 10000000);
    case 'material_expenses':
      return _float(v, positive: false, max: 100000000);
    case 'estimated_hours':
      return _float(v, positive: true, max: 10000);
    case 'advance_received':
      return _float(v, positive: false, max: 100000000);
  }
  return _Res(null, 'unknown field');
}

class MergeResult {
  final List<String> updated;
  final Map<String, String> errors;
  MergeResult(this.updated, this.errors);
}

/// Validates each new field on its own and merges the good ones into [draft].
MergeResult mergeFields(Map<String, dynamic> draft, Map<String, dynamic>? newFields) {
  final updated = <String>[];
  final errors = <String, String>{};
  (newFields ?? {}).forEach((k, v) {
    if (!kFields.contains(k) || v == null || v == '') return;
    final r = _validate(k, v);
    if (r.error != null) {
      errors[k] = r.error!;
      return;
    }
    if (r.value != null) {
      if (draft[k] != r.value) updated.add(k);
      draft[k] = r.value;
      final sk = draft['_skipped'];
      if (sk is List) sk.remove(k);
    }
  });
  return MergeResult(updated, errors);
}

List<String> missingRequired(Map<String, dynamic> draft) =>
    kRequired.where((f) => draft[f] == null).toList();

String? nextQuestion(Map<String, dynamic> draft) {
  final skipped = (draft['_skipped'] is List) ? (draft['_skipped'] as List) : const [];
  for (final f in kAskOrder) {
    if (draft[f] == null && !skipped.contains(f)) return f;
  }
  return null;
}

Map<String, dynamic> cleanOrder(Map<String, dynamic> draft) => {for (final k in kFields) k: draft[k]};

Map<String, dynamic> publicDraft(Map<String, dynamic> d) =>
    {for (final k in kFields) if (d[k] != null) k: d[k]};

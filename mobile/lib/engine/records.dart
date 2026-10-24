import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'calc.dart' show ValueError;

// ====================================================================== hashing
/// Canonical JSON: sorted keys, no spaces, same idea as records.canonical in Python.
String canonical(dynamic o) {
  if (o == null) return 'null';
  if (o is bool) return o ? 'true' : 'false';
  if (o is int) return o.toString();
  if (o is double) {
    if (!o.isFinite) return 'null';
    return (o == o.truncateToDouble() && o.abs() < 1e15) ? '${o.toInt()}.0' : o.toString();
  }
  if (o is String) return jsonEncode(o);
  if (o is List) return '[${o.map(canonical).join(',')}]';
  if (o is Map) {
    final keys = o.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(o[k])}').join(',')}}';
  }
  return jsonEncode(o.toString());
}

String sha256Hex(String s) => crypto.sha256.convert(utf8.encode(s)).toString();
String sha256Bytes(List<int> b) => crypto.sha256.convert(b).toString();

String nowIso() {
  final d = DateTime.now().toUtc();
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${p(d.year, 4)}-${p(d.month)}-${p(d.day)}T${p(d.hour)}:${p(d.minute)}:${p(d.second)}+00:00';
}

dynamic deepCopy(dynamic o) => jsonDecode(jsonEncode(o));

// ====================================================================== storage
/// One small JSON file on the phone (no server, no cloud). Pass dir = null for in-memory (tests).
class Store {
  final String? dir;
  Map<String, dynamic> db = <String, dynamic>{
    'meta': <String, dynamic>{'pin_hash': null, 'pin_salt': null, 'lock_seconds': 60},
    'records': <dynamic>[],
    'payments': <dynamic>[],
    'followups': <dynamic>[],
    'seq': 0,
  };
  Future<void> _chain = Future<void>.value();

  Store({this.dir});

  File? get _file => dir == null ? null : File('$dir/amana_store.json');

  Future<void> load() async {
    final f = _file;
    if (f == null || !await f.exists()) return;
    try {
      final d = jsonDecode(await f.readAsString());
      if (d is Map<String, dynamic>) db = d;
    } catch (_) {
      // corrupted file: start clean rather than crash
    }
  }

  void flush() {
    final f = _file;
    if (f == null) return;
    final data = jsonEncode(db);
    _chain = _chain.then((_) async {
      try {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(data, flush: true);
        await tmp.rename(f.path);
      } catch (_) {}
    });
  }

  Map<String, dynamic> get meta => db['meta'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get records => (db['records'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get payments => (db['payments'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get followups => (db['followups'] as List).cast<Map<String, dynamic>>();

  int nextId() {
    final n = ((db['seq'] as num?) ?? 0).toInt() + 1;
    db['seq'] = n;
    return n;
  }

  void wipe() {
    db['records'] = <dynamic>[];
    db['payments'] = <dynamic>[];
    db['followups'] = <dynamic>[];
    flush();
  }
}

// ====================================================================== work records
/// SHA-256 fingerprint chained to the previous record. A hash detects CHANGES after the fact;
/// it does not prove that the worker's original information was true.
class Records {
  final Store store;
  Records(this.store);
  static const String genesis = 'GENESIS';

  String _lastHash() => store.records.isEmpty ? genesis : store.records.last['hash'] as String;

  String computeHash(String orderNo, int version, String prev, Map<String, dynamic> data, String createdAt) =>
      sha256Hex(canonical({
        'order_no': orderNo,
        'version': version,
        'prev_hash': prev,
        'created_at': createdAt,
        'data': data,
      }));

  Map<String, String> fieldHashes(Map<String, dynamic> data) =>
      {for (final e in data.entries) e.key: sha256Hex(canonical(e.value))};

  String nextOrderNo() {
    final n = store.records.map((r) => r['order_no']).toSet().length;
    final ts = nowIso();
    return 'AM-${ts.substring(2, 4)}${ts.substring(5, 7)}-${(n + 1).toString().padLeft(3, '0')}';
  }

  Map<String, dynamic> createRecord(Map<String, dynamic> data, {String? orderNo, bool isSample = false}) {
    final no = orderNo ?? nextOrderNo();
    final d = Map<String, dynamic>.from(deepCopy({...data, 'order_no': no}) as Map);
    final ts = nowIso();
    final prev = _lastHash();
    final h = computeHash(no, 1, prev, d, ts);
    store.records.add({
      'id': store.nextId(),
      'order_no': no,
      'version': 1,
      'data': d,
      'original': deepCopy(d),
      'field_hashes': fieldHashes(d),
      'prev_hash': prev,
      'hash': h,
      'created_at': ts,
      'is_sample': isSample,
    });
    store.flush();
    return latestRecord(no)!;
  }

  Map<String, dynamic>? latestRecord(String orderNo) {
    Map<String, dynamic>? best;
    for (final r in store.records) {
      if (r['order_no'] != orderNo) continue;
      if (best == null || (r['version'] as int) >= (best['version'] as int)) best = r;
    }
    return best;
  }

  /// Latest version of each order, newest first.
  List<Map<String, dynamic>> listOrders() {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final r in store.records.reversed) {
      final no = r['order_no'] as String;
      if (seen.add(no)) out.add(latestRecord(no)!);
    }
    return out;
  }

  Map<String, dynamic> verifyRecord(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row['data'] as Map);
    final actual = computeHash(
        row['order_no'] as String, row['version'] as int, row['prev_hash'] as String, data, row['created_at'] as String);
    final ok = actual == row['hash'];
    final changed = <String>[];
    if (!ok) {
      final stored = Map<String, dynamic>.from(row['field_hashes'] as Map);
      final nowH = fieldHashes(data);
      final keys = {...stored.keys, ...nowH.keys}.toList()..sort();
      for (final k in keys) {
        if (stored[k] != nowH[k]) changed.add(k);
      }
    }
    return {'ok': ok, 'stored_hash': row['hash'], 'recomputed_hash': actual, 'changed_fields': changed};
  }

  Map<String, dynamic> verifyChain() {
    var prev = genesis;
    final bad = <List<dynamic>>[];
    for (final r in store.records) {
      if (!(verifyRecord(r)['ok'] as bool)) bad.add([r['order_no'], r['version'], 'data changed']);
      if (r['prev_hash'] != prev) bad.add([r['order_no'], r['version'], 'chain link broken']);
      prev = r['hash'] as String;
    }
    return {'ok': bad.isEmpty, 'length': store.records.length, 'problems': bad};
  }

  // ----- demo helpers (the "tamper test" button)
  /// Silently changes the rate inside the stored data WITHOUT re-hashing.
  String tamperDemo(String orderNo) {
    final r = latestRecord(orderNo)!;
    final data = Map<String, dynamic>.from(r['data'] as Map);
    final cur = data['rate_per_piece'];
    data['rate_per_piece'] = ((cur is num) ? cur : 0) + 50;
    r['data'] = data;
    store.flush();
    return 'rate_per_piece';
  }

  void restoreOriginal(String orderNo) {
    final r = latestRecord(orderNo)!;
    r['data'] = deepCopy(r['original']);
    store.flush();
  }

  // ----- payments
  Map<String, dynamic> savePayment(String orderNo, String agreementHash, Map<String, dynamic> data,
      [String? evidenceHash]) {
    final ts = nowIso();
    final d = Map<String, dynamic>.from(
        deepCopy({...data, 'order_no': orderNo, 'agreement_hash': agreementHash}) as Map);
    final h = sha256Hex(canonical({'created_at': ts, 'data': d}));
    store.payments.add({
      'id': store.nextId(),
      'order_no': orderNo,
      'agreement_hash': agreementHash,
      'data': d,
      'hash': h,
      'evidence_hash': evidenceHash,
      'created_at': ts,
    });
    store.flush();
    return {'hash': h, 'created_at': ts, 'data': d};
  }

  List<Map<String, dynamic>> listPayments([String? orderNo]) =>
      store.payments.where((p) => orderNo == null || p['order_no'] == orderNo).toList();

  Future<String> saveEvidence(Uint8List bytes, String filename) async {
    final h = sha256Bytes(bytes);
    final dir = store.dir;
    if (dir != null) {
      try {
        final folder = Directory('$dir/evidence');
        await folder.create(recursive: true);
        final dot = filename.lastIndexOf('.');
        final ext = dot >= 0 ? filename.substring(dot).toLowerCase() : '';
        await File('${folder.path}/${h.substring(0, 16)}${ext.length > 6 ? '' : ext}').writeAsBytes(bytes);
      } catch (_) {}
    }
    return h;
  }

  void saveFollowup(String orderNo, String text, String status) {
    store.followups.add({
      'id': store.nextId(),
      'order_no': orderNo,
      'text': text,
      'status': status,
      'created_at': nowIso(),
    });
    store.flush();
  }
}

// ====================================================================== shared-phone safe mode
class Security {
  final Store store;
  Security(this.store);
  static const int maxAttempts = 5;
  static const int lockoutSeconds = 30;

  bool validPin(String? p) => p != null && RegExp(r'^\d{4}$').hasMatch(p);

  String _hash(String salt, String pin) {
    var h = '$salt:$pin';
    for (var i = 0; i < 2000; i++) {
      h = sha256Hex('$salt$h');
    }
    return h;
  }

  void setPin(String pin) {
    if (!validPin(pin)) throw ValueError('PIN must be exactly 4 digits');
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(12, (_) => rnd.nextInt(256)));
    store.meta['pin_salt'] = salt;
    store.meta['pin_hash'] = _hash(salt, pin);
    store.flush();
  }

  void clearPin() {
    store.meta['pin_salt'] = null;
    store.meta['pin_hash'] = null;
    store.flush();
  }

  bool hasPin() => store.meta['pin_hash'] != null;

  bool checkPin(String pin) {
    if (!hasPin() || !validPin(pin)) return false;
    return _hash(store.meta['pin_salt'] as String, pin) == store.meta['pin_hash'];
  }

  int lockSeconds() => ((store.meta['lock_seconds'] as num?) ?? 60).toInt();

  void setLockSeconds(int s) {
    store.meta['lock_seconds'] = s;
    store.flush();
  }

  bool isIdle(DateTime lastActive, int seconds) => DateTime.now().difference(lastActive).inSeconds >= seconds;
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../engine/agents.dart';
import '../engine/calc.dart' as calc;
import '../engine/llm.dart';
import '../engine/records.dart';
import '../engine/schemas.dart';
import 'api.dart';

const int _maxAudio = 8 * 1024 * 1024;
const int _maxProof = 6 * 1024 * 1024;
const Set<String> _proofExt = {'.png', '.jpg', '.jpeg', '.pdf', '.webp'};
const Map<String, String> _audioMime = {
  '.wav': 'audio/wav',
  '.m4a': 'audio/aac',
  '.aac': 'audio/aac',
  '.mp3': 'audio/mp3',
  '.ogg': 'audio/ogg',
  '.webm': 'audio/webm',
  '.flac': 'audio/flac',
};

class _Session {
  Map<String, dynamic> s = {};
  List<Map<String, dynamic>> trace = [];
  String stage = 'describe'; // describe -> review -> confirmed -> report
  String? asked;
  String? orderNo;
  Map<String, dynamic>? report;
  String? follow;
  String msgText = '';
  int attempts = 0;
  DateTime? lockUntil;
  bool locked;
  DateTime lastActive = DateTime.now();

  _Session(this.locked) {
    resetOrder();
  }

  void resetOrder() {
    trace = <Map<String, dynamic>>[];
    s = <String, dynamic>{'draft': <String, dynamic>{}, 'chat': <dynamic>[], 'trace': trace, 'min_hourly': 0};
    stage = 'describe';
    asked = null;
    orderNo = null;
    report = null;
    follow = null;
    msgText = '';
  }

  Map<String, dynamic> get draft => s['draft'] as Map<String, dynamic>;
  List<dynamic> get chat => s['chat'] as List<dynamic>;

  String chatLang(String ui) => (s['chat_lang'] as String?) ?? (const ['en', 'ur', 'roman'].contains(ui) ? ui : 'en');
}

/// Everything the Python FastAPI server did, now running INSIDE the phone: same routes, same JSON,
/// so the screens do not know the difference. Data stays in one JSON file in the app's private folder.
/// AI calls go straight from the phone to Gemini/Groq/NVIDIA; without a key the rule-based mode runs.
class LocalApi {
  String? token;
  String base = 'on-device';
  final Llm llm = Llm();
  late Store store;
  late Records records;
  late Security security;
  late _Session sess;
  bool ready = false;

  /// dir = null and useDocs = false gives an in-memory store (used by tests).
  Future<void> init({String? dir, bool useDocs = true}) async {
    var d = dir;
    if (d == null && useDocs && !kIsWeb) d = (await getApplicationDocumentsDirectory()).path; // web preview keeps data in memory
    store = Store(dir: d);
    await store.load();
    records = Records(store);
    security = Security(store);
    sess = _Session(security.hasPin());
    token = 'local';
    ready = true;
  }

  void setKeys(Map<String, String> keys) {
    llm.keys
      ..clear()
      ..addAll(keys);
  }

  // ------------------------------------------------------------------ transport-compatible API
  Future<dynamic> get(String path, {Duration timeout = const Duration(seconds: 30)}) => _route('GET', path, {});

  Future<dynamic> post(String path, [Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 70)]) =>
      _route('POST', path, body ?? <String, dynamic>{});

  Future<dynamic> delete(String path) => _route('DELETE', path, {});

  Future<dynamic> multipart(String path, Map<String, String> fields,
          {String? fileField, String? filePath, String? fileName}) =>
      _route('POST', path, {}, fields: fields, filePath: filePath, fileName: fileName);

  // ------------------------------------------------------------------ guards
  void _authed() {
    if (security.hasPin()) {
      if (!sess.locked && security.isIdle(sess.lastActive, security.lockSeconds())) sess.locked = true;
      if (sess.locked) throw LockedException();
    }
    sess.lastActive = DateTime.now();
  }

  // ------------------------------------------------------------------ views
  Map<String, dynamic> _recordView(Map<String, dynamic> row) {
    final v = records.verifyRecord(row);
    return {
      'order_no': row['order_no'],
      'version': row['version'],
      'hash': row['hash'],
      'prev_hash': row['prev_hash'],
      'first': row['prev_hash'] == Records.genesis,
      'created_at': row['created_at'],
      'is_sample': row['is_sample'] == true,
      'data': row['data'],
      'integrity': {'ok': v['ok'], 'changed_fields': v['changed_fields']},
    };
  }

  Map<String, dynamic> _paymentView(Map<String, dynamic> p) {
    final d = p['data'] as Map<String, dynamic>;
    return {
      'created_at': p['created_at'],
      'hash': p['hash'],
      'received': d['received'],
      'difference': d['difference'],
      'unexplained': d['unexplained'],
      'status': d['status'],
      'note': d['note'] ?? '',
      'has_evidence': p['evidence_hash'] != null,
    };
  }

  Map<String, dynamic> _chatView() => {
        'draft': publicDraft(sess.draft),
        'skipped': (sess.draft['_skipped'] as List?) ?? <dynamic>[],
        'asked': sess.asked,
        'can_calc': missingRequired(sess.draft).isEmpty,
        'chat_lang': sess.s['chat_lang'],
        'ai_mode': llm.status()['mode'],
      };

  Map<String, dynamic> _snapshot() {
    final s = sess.s;
    final out = <String, dynamic>{
      'stage': sess.stage,
      'chat': sess.chat,
      'calc': s['calc'],
      'flags': s['flags'],
      'explain': s['explain'],
      'counter': s['counter'],
      'min_hourly': s['min_hourly'] ?? 0,
      'order_no': sess.orderNo,
      'record': null,
      'report': sess.report,
      'follow': sess.follow,
      'msg_text': sess.msgText,
      ..._chatView(),
    };
    if (sess.orderNo != null) {
      final r = records.latestRecord(sess.orderNo!);
      out['record'] = r == null ? null : _recordView(r);
    }
    return out;
  }

  Map<String, dynamic> _safeView() {
    final lu = sess.lockUntil;
    final wait = lu == null ? 0 : (lu.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 9999);
    return {
      'has_pin': security.hasPin(),
      'lock_seconds': security.lockSeconds(),
      'locked': sess.locked && security.hasPin(),
      'wait': wait,
      'attempts_left': Security.maxAttempts - sess.attempts,
    };
  }

  List<Map<String, dynamic>> _traceSince(int mark) => sess.trace.sublist(mark);

  // ------------------------------------------------------------------ router
  Future<dynamic> _route(String method, String path, Map<String, dynamic> body,
      {Map<String, String>? fields, String? filePath, String? fileName}) async {
    if (!ready) await init();
    final key = '$method $path';
    switch (key) {
      case 'GET /health':
        final st = llm.status();
        return {'ok': true, 'version': 'local-1.0', 'ai_mode': st['mode'], 'providers': st['providers'], 'voice': st['voice']};
      case 'POST /session':
        token = 'local';
        return {'token': 'local', 'ai_mode': llm.status()['mode'], 'has_pin': security.hasPin()};
      case 'GET /safe':
        return _safeView();
      case 'POST /safe/verify':
        return _safeVerify(body);
      case 'POST /safe/lock':
        if (security.hasPin()) sess.locked = true;
        return _safeView();
    }

    _authed(); // everything below needs the phone to be unlocked
    switch (key) {
      case 'GET /state':
        return _snapshot();
      case 'POST /ping':
        return {'ok': true};
      case 'POST /chat':
        return _chat(body);
      case 'POST /chat/skip':
        if (sess.asked != null && !kRequired.contains(sess.asked)) {
          (sess.draft['_skipped'] ??= <dynamic>[]);
          (sess.draft['_skipped'] as List).add(sess.asked);
          sess.asked = nextQuestion(sess.draft);
        }
        return _chatView();
      case 'POST /chat/reset':
        sess.resetOrder();
        return _snapshot();
      case 'POST /voice':
        return _voice(fields ?? {}, filePath, fileName);
      case 'POST /deal/evaluate':
        return _evaluate(body);
      case 'POST /deal/back':
        if (sess.stage == 'review') sess.stage = 'describe';
        return _chatView();
      case 'POST /deal/counter':
        return _counter(body);
      case 'POST /record/confirm':
        return _confirm();
      case 'POST /payment/check':
        return _payment(fields ?? {}, filePath, fileName);
      case 'POST /message/approve':
        return _approve(body);
      case 'POST /message/dismiss':
        return _dismiss(body);
      case 'GET /records':
        return _recordsList();
      case 'POST /records/verify':
        final r = records.verifyChain();
        return {
          'ok': r['ok'],
          'length': r['length'],
          'problems': [
            for (final p in r['problems'] as List) {'order_no': p[0], 'version': p[1], 'reason': p[2]}
          ],
        };
      case 'POST /demo/sample':
        return _sample();
      case 'POST /demo/tamper':
        _needOrder(body['order_no']);
        return {'changed_field': records.tamperDemo(body['order_no'].toString())};
      case 'POST /demo/restore':
        _needOrder(body['order_no']);
        records.restoreOriginal(body['order_no'].toString());
        return {'restored': true};
      case 'DELETE /data':
        store.wipe();
        sess.resetOrder();
        return {'deleted': true};
      case 'POST /safe/pin':
        return _setPin(body);
      case 'POST /safe/off':
        return _pinOff(body);
      case 'POST /safe/lock_seconds':
        final sec = (body['seconds'] as num?)?.toInt();
        if (sec == null || !const [30, 60, 120, 300].contains(sec)) {
          throw ApiException(422, 'Choose 30, 60, 120 or 300 seconds.');
        }
        security.setLockSeconds(sec);
        return _safeView();
    }
    throw ApiException(404, 'Not found: $key');
  }

  void _needOrder(Object? no) {
    if (no == null || records.latestRecord(no.toString()) == null) throw ApiException(404, 'No such order.');
  }

  // ------------------------------------------------------------------ chat + voice
  Future<dynamic> _chat(Map<String, dynamic> body) async {
    final text = (body['text'] ?? '').toString().trim();
    if (text.isEmpty) throw ApiException(422, 'Empty message');
    if (text.length > 1000) throw ApiException(422, 'Message too long');
    if (sess.stage != 'describe') throw ApiException(409, 'Start a new order first.');
    final mark = sess.trace.length;
    final reply = await Orchestrator(records, sess.s, Trace(sess.trace), llm).handle(text, sess.asked);
    sess.chat.addAll([
      {'role': 'user', 'text': text},
      {'role': 'assistant', 'text': reply},
    ]);
    sess.asked = nextQuestion(sess.draft);
    return {'reply': reply, 'trace': _traceSince(mark), ..._chatView()};
  }

  Future<dynamic> _voice(Map<String, String> f, String? path, String? name) async {
    if (path == null) throw ApiException(422, 'Empty audio');
    final bytes = Uint8List.fromList(await File(path).readAsBytes());
    if (bytes.isEmpty) throw ApiException(422, 'Empty audio');
    if (bytes.length > _maxAudio) throw ApiException(413, 'Audio too long');
    if (llm.status()['voice'] != true) {
      throw ApiException(503, 'Voice is not available right now. Please type your message.');
    }
    final fn = name ?? 'voice.wav';
    final dot = fn.lastIndexOf('.');
    final ext = dot >= 0 ? fn.substring(dot).toLowerCase() : '.wav';
    try {
      final text = await llm.transcribe(bytes, fn,
          language: f['language'] == 'ur' ? 'ur' : (f['language'] == 'en' ? 'en' : 'auto'), mime: _audioMime[ext] ?? 'audio/wav');
      if (text.isEmpty) throw ApiException(422, 'Could not understand the audio');
      return {'text': text};
    } on LLMUnavailable catch (e) {
      throw ApiException(502, 'Could not transcribe: ${e.message}');
    }
  }

  // ------------------------------------------------------------------ deal
  Future<dynamic> _evaluate(Map<String, dynamic> body) async {
    final mark = sess.trace.length;
    final deal = DealAgent(records, sess.s, Trace(sess.trace), llm);
    final res = deal.evaluate();
    if (res.containsKey('error')) throw ApiException(400, res['error'].toString());
    sess.s['explain'] = await deal.explain(sess.chatLang((body['lang'] ?? 'en').toString()));
    sess.stage = 'review';
    sess.s['counter'] = null;
    return {
      'calc': sess.s['calc'],
      'flags': sess.s['flags'],
      'explain': sess.s['explain'],
      'draft': publicDraft(sess.draft),
      'trace': _traceSince(mark),
    };
  }

  Future<dynamic> _counter(Map<String, dynamic> body) async {
    final target = (body['target_hourly'] as num?)?.toDouble();
    if (target == null || target <= 0 || target > 100000) throw ApiException(422, 'Enter a valid target.');
    if (sess.stage != 'review') throw ApiException(409, 'Show the numbers first.');
    if (sess.draft['estimated_hours'] == null) throw ApiException(400, 'hours missing');
    final mark = sess.trace.length;
    sess.s['min_hourly'] = target;
    final tr = Trace(sess.trace);
    DealAgent(records, sess.s, tr, llm).evaluate(); // refresh flags with the new target
    final co = await DealAgent(records, sess.s, tr, llm)
        .counteroffer(target, sess.chatLang((body['lang'] ?? 'en').toString()));
    if (co.containsKey('error')) throw ApiException(400, co['error'].toString());
    sess.s['counter'] = co;
    return {'counter': co, 'flags': sess.s['flags'], 'calc': sess.s['calc'], 'trace': _traceSince(mark)};
  }

  dynamic _confirm() {
    if (sess.stage != 'review' || sess.s['calc'] == null) throw ApiException(409, 'Nothing to confirm.');
    final mark = sess.trace.length;
    final rec = WorkRecordAgent(records, sess.s, Trace(sess.trace)).saveConfirmed();
    sess.orderNo = rec['order_no'] as String;
    sess.stage = 'confirmed';
    return {'record': _recordView(rec), 'trace': _traceSince(mark)};
  }

  // ------------------------------------------------------------------ payment
  Future<dynamic> _payment(Map<String, String> f, String? proofPath, String? proofName) async {
    final orderNo = f['order_no'] ?? '';
    final received = double.tryParse(f['received'] ?? '');
    final adv = double.tryParse(f['advance_paid'] ?? '0') ?? 0;
    final ded = double.tryParse(f['agreed_deductions'] ?? '0') ?? 0;
    if (received == null) throw ApiException(422, 'Enter the amount received.');
    if (received < 0 || adv < 0 || ded < 0) throw ApiException(400, 'Amounts cannot be negative.');
    if (records.latestRecord(orderNo) == null) throw ApiException(404, 'No such order.');
    final note = (f['note'] ?? '').trim();
    final lang = sess.chatLang(f['lang'] ?? 'en');

    String? evHash;
    var hasProof = false;
    if (proofPath != null) {
      final nm = proofName ?? proofPath.split('/').last;
      final dot = nm.lastIndexOf('.');
      final ext = dot >= 0 ? nm.substring(dot).toLowerCase() : '';
      if (!_proofExt.contains(ext)) throw ApiException(415, 'Use a photo (png, jpg) or pdf.');
      final blob = Uint8List.fromList(await File(proofPath).readAsBytes());
      if (blob.length > _maxProof) throw ApiException(413, 'File too large (max 6 MB).');
      if (blob.isNotEmpty) {
        evHash = await records.saveEvidence(blob, nm);
        hasProof = true;
      }
    }

    final mark = sess.trace.length;
    Map<String, dynamic> rep;
    try {
      rep = await PaymentAgent(records, sess.s, Trace(sess.trace), llm).run(
          orderNo, received, adv, ded, f['is_partial'] == 'true', note.length > 300 ? note.substring(0, 300) : note, lang,
          hasProof: hasProof);
    } on calc.ValueError catch (e) {
      throw ApiException(400, e.message);
    }
    if (rep['blocked'] == true) {
      return {'blocked': true, 'integrity': rep['integrity'], 'order_no': orderNo, 'trace': _traceSince(mark)};
    }
    final c = Map<String, dynamic>.from(rep['comparison'] as Map);
    records.savePayment(
        orderNo,
        rep['agreement_hash'] as String,
        {
          ...c,
          'note': note.length > 300 ? note.substring(0, 300) : note,
          'sources': {'received': hasProof ? 'supported_by_evidence' : 'reported_by_worker'},
        },
        evHash);
    sess.orderNo = orderNo;
    sess.report = rep;
    sess.follow = null;
    sess.msgText = (rep['draft_message'] ?? '').toString();
    sess.stage = 'report';
    return {'blocked': false, 'report': rep, 'msg_text': sess.msgText, 'trace': _traceSince(mark)};
  }

  dynamic _approve(Map<String, dynamic> body) {
    if (sess.stage != 'report' || sess.orderNo == null) throw ApiException(409, 'No report to approve.');
    final text = (body['text'] ?? '').toString().trim();
    if (text.isEmpty) throw ApiException(422, 'Message is empty.');
    records.saveFollowup(sess.orderNo!, text, 'approved');
    sess.follow = 'approved';
    sess.msgText = text;
    return {'status': 'approved', 'text': text, 'whatsapp_url': 'https://wa.me/?text=${Uri.encodeComponent(text)}'};
  }

  dynamic _dismiss(Map<String, dynamic> body) {
    if (sess.stage != 'report' || sess.orderNo == null) throw ApiException(409, 'No report to dismiss.');
    final t = (body['text'] ?? '').toString().trim();
    records.saveFollowup(sess.orderNo!, t.isEmpty ? sess.msgText : t, 'dismissed');
    sess.follow = 'dismissed';
    return {'status': 'dismissed'};
  }

  // ------------------------------------------------------------------ records
  dynamic _recordsList() {
    final orders = records.listOrders();
    num exp = 0, recv = 0, unx = 0;
    final out = <Map<String, dynamic>>[];
    for (final o in orders) {
      final pays = [for (final p in records.listPayments(o['order_no'] as String)) _paymentView(p)];
      exp += ((o['data'] as Map)['expected_total'] as num?) ?? 0;
      if (pays.isNotEmpty) {
        recv += (pays.last['received'] as num?) ?? 0;
        final u = (pays.last['unexplained'] as num?) ?? 0;
        unx += u > 0 ? u : 0;
      }
      out.add({..._recordView(o), 'payments': pays});
    }
    return {
      'orders': out,
      'summary': {'orders': orders.length, 'expected': exp, 'received': recv, 'open': unx},
    };
  }

  Map<String, dynamic> _sampleData() {
    final data = <String, dynamic>{
      'item': 'embroidered suits',
      'quantity': 100,
      'rate_per_piece': 80,
      'deadline_days': 10,
      'material_expenses': 1500,
      'estimated_hours': 90,
      'payment_terms': 'on delivery',
      'contractor_name': null,
      'other_terms': null,
      'advance_received': null,
      'expected_total': 8000,
      'net_after_expenses': 6500,
      'hourly_net': 72.22,
    };
    final src = <String, dynamic>{
      for (final k in ['item', 'quantity', 'rate_per_piece', 'deadline_days', 'material_expenses', 'estimated_hours', 'payment_terms'])
        k: 'reported_by_worker',
      'expected_total': 'calculated',
      'net_after_expenses': 'calculated',
      'hourly_net': 'calculated',
    };
    data['sources'] = src;
    return data;
  }

  dynamic _sample() {
    if (records.listOrders().isNotEmpty) throw ApiException(409, 'You already have records.');
    final rec = records.createRecord(_sampleData(), isSample: true);
    final cmp = calc.comparePayment(8000, 6500);
    records.savePayment(rec['order_no'] as String, rec['hash'] as String,
        {...cmp, 'note': 'sample', 'sources': {'received': 'reported_by_worker'}});
    return {'order_no': rec['order_no']};
  }

  // ------------------------------------------------------------------ safe mode
  Map<String, dynamic> _safeVerify(Map<String, dynamic> body) {
    final pin = (body['pin'] ?? '').toString();
    if (!security.validPin(pin)) throw ApiException(422, 'PIN must be 4 digits.');
    if (!security.hasPin()) {
      sess.locked = false;
      return {'ok': true, ..._safeView()};
    }
    final ok = _checkPin(pin);
    if (ok) {
      sess.locked = false;
      sess.lastActive = DateTime.now();
    }
    return {'ok': ok, ..._safeView()};
  }

  bool _checkPin(String pin) {
    final lu = sess.lockUntil;
    if (lu != null && DateTime.now().isBefore(lu)) {
      final w = lu.difference(DateTime.now()).inSeconds + 1;
      throw ApiException(429, 'Too many tries. Wait $w seconds.');
    }
    if (security.checkPin(pin)) {
      sess.attempts = 0;
      return true;
    }
    sess.attempts += 1;
    if (sess.attempts >= Security.maxAttempts) {
      sess.attempts = 0;
      sess.lockUntil = DateTime.now().add(const Duration(seconds: Security.lockoutSeconds));
    }
    return false;
  }

  dynamic _setPin(Map<String, dynamic> body) {
    if (security.hasPin()) throw ApiException(409, 'A PIN is already set. Turn it off first.');
    final pin = (body['pin'] ?? '').toString();
    try {
      security.setPin(pin);
    } on calc.ValueError catch (e) {
      throw ApiException(422, e.message);
    }
    sess.locked = false;
    return _safeView();
  }

  dynamic _pinOff(Map<String, dynamic> body) {
    if (!_checkPin((body['pin'] ?? '').toString())) throw ApiException(403, 'Wrong PIN.');
    security.clearPin();
    sess.locked = false;
    return _safeView();
  }
}

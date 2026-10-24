import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../util.dart';
import 'api.dart';
import 'local_api.dart';

enum Boot { loading, ready, failed }

/// Holds everything the screens show. The server owns the real state (agents, records, PIN);
/// this class mirrors it and calls the API.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final LocalApi api = LocalApi();
  SharedPreferences? _prefs;
  final FlutterTts _tts = FlutterTts();

  // ---- preferences
  String lang = 'en'; // UI language: en | ur
  String voiceLang = 'ur'; // what she speaks: ur | en
  bool ttsOn = false;
  bool get ur => lang == 'ur';
  String t(String key, [Map<String, Object?>? args]) => tr(key, lang, args);

  // ---- boot / connection
  Boot boot = Boot.loading;
  String? bootError;
  bool waking = false;
  String aiMode = 'unknown';
  int tab = 0; // 0 work, 1 records, 2 safe

  // ---- safe mode
  bool hasPin = false;
  bool locked = false;
  int lockSeconds = 60;
  int lockWait = 0;
  int attemptsLeft = 5;
  final ValueNotifier<int> lockLeft = ValueNotifier<int>(0);
  DateTime _last = DateTime.now();
  DateTime _lastPing = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;
  bool _firstBoot = true;

  // ---- worker flow (mirrors the server session)
  String stage = 'describe'; // describe | review | confirmed | report
  List<Map<String, dynamic>> chat = [];
  Map<String, dynamic> draft = {};
  List<String> skipped = [];
  String? asked;
  bool canCalc = false;
  String? chatLang;
  Map<String, dynamic>? calc;
  List<dynamic> flags = [];
  String? explain;
  Map<String, dynamic>? counter;
  num minHourly = 0;
  String? orderNo;
  Map<String, dynamic>? record;
  Map<String, dynamic>? report;
  String? follow;
  String msgText = '';
  String? waUrl;
  bool blocked = false;

  // ---- ui flags
  bool busy = false; // long action (evaluate, confirm, payment)
  bool sending = false; // chat message in flight
  String? _flash;
  bool _flashError = false;

  // ---- records + trace
  Map<String, dynamic>? recordsData;
  bool recordsLoading = false;
  List<Map<String, dynamic>> trace = [];

  // ================================================================== boot
  Future<void> start() async {
    final t0 = DateTime.now();
    boot = Boot.loading;
    bootError = null;
    waking = false;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    lang = p.getString('lang') ?? 'en';
    voiceLang = p.getString('voiceLang') ?? 'ur';
    ttsOn = p.getBool('tts') ?? false;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    try {
      await api.init();
      api.setKeys(aiKeys);
      await _healthWithRetry();
      if (api.token == null) await _newSession();
      final safe = await _safeOrRenew();
      _applySafe(safe);
      if (!locked) await _loadState();
      if (_firstBoot) {
        // let the splash animation finish (about 2 seconds) the first time only
        final left = const Duration(milliseconds: 2200) - DateTime.now().difference(t0);
        if (left > Duration.zero) await Future<void>.delayed(left);
        _firstBoot = false;
      }
      boot = Boot.ready;
    } catch (e) {
      boot = Boot.failed;
      bootError = e is ApiException ? e.message : tr(errorKey(e), lang);
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  Future<void> _healthWithRetry() async {
    Object? last;
    for (var i = 0; i < 3; i++) {
      try {
        final j = await api.get('/health', timeout: const Duration(seconds: 25));
        if (j is Map) aiMode = (j['ai_mode'] ?? 'unknown').toString();
        waking = false;
        return;
      } catch (e) {
        last = e;
        waking = true;
        notifyListeners();
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    throw last ?? Exception('unreachable');
  }

  Future<void> _newSession() async {
    final j = await api.post('/session');
    api.token = (j as Map)['token'].toString();
    aiMode = (j['ai_mode'] ?? aiMode).toString();
  }

  Future<Map<String, dynamic>> _safeOrRenew() async {
    try {
      return Map<String, dynamic>.from(await api.get('/safe') as Map);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      await _newSession();
      _resetLocal();
      return Map<String, dynamic>.from(await api.get('/safe') as Map);
    }
  }

  Future<void> _loadState() async {
    final j = await api.get('/state');
    _applySnapshot(Map<String, dynamic>.from(j as Map));
  }

  void _resetLocal() {
    stage = 'describe';
    chat = [];
    draft = {};
    skipped = [];
    asked = null;
    canCalc = false;
    calc = null;
    flags = [];
    explain = null;
    counter = null;
    orderNo = null;
    record = null;
    report = null;
    follow = null;
    msgText = '';
    waUrl = null;
    blocked = false;
    recordsData = null;
    trace = [];
  }

  // ================================================================== apply server data
  void _applySnapshot(Map<String, dynamic> j) {
    stage = j.s('stage') ?? 'describe';
    chat = j.l('chat').map((e) => Map<String, dynamic>.from(e as Map)).toList();
    _applyChatView(j);
    calc = j['calc'] is Map ? j.m('calc') : null;
    flags = j.l('flags');
    explain = j.s('explain');
    counter = j['counter'] is Map ? j.m('counter') : null;
    minHourly = j.n('min_hourly') ?? 0;
    orderNo = j.s('order_no');
    record = j['record'] is Map ? j.m('record') : null;
    report = j['report'] is Map ? j.m('report') : null;
    follow = j.s('follow');
    msgText = j.s('msg_text') ?? '';
  }

  void _applyChatView(Map<String, dynamic> j) {
    draft = j.m('draft');
    skipped = j.l('skipped').map((e) => e.toString()).toList();
    asked = j.s('asked');
    canCalc = j.b('can_calc');
    chatLang = j.s('chat_lang');
    aiMode = j.s('ai_mode') ?? aiMode;
  }

  void _applySafe(Map<String, dynamic> j) {
    hasPin = j.b('has_pin');
    lockSeconds = j.n('lock_seconds')?.toInt() ?? 60;
    locked = j.b('locked');
    lockWait = j.n('wait')?.toInt() ?? 0;
    attemptsLeft = j.n('attempts_left')?.toInt() ?? 5;
  }

  void _addTrace(dynamic l) {
    if (l is! List) return;
    for (final e in l) {
      if (e is Map) trace.add(Map<String, dynamic>.from(e));
    }
    if (trace.length > 400) trace = trace.sublist(trace.length - 400);
  }

  // ================================================================== error handling
  void flash(String message, {bool error = false}) {
    _flash = message;
    _flashError = error;
    notifyListeners();
  }

  /// Returns the pending message once, then clears it (the UI shows it as a snackbar).
  ({String message, bool error})? takeFlash() {
    final m = _flash;
    if (m == null) return null;
    _flash = null;
    return (message: m, error: _flashError);
  }

  Future<T?> _run<T>(Future<T> Function() f, {bool silent = false}) async {
    try {
      return await f();
    } on LockedException {
      locked = true;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (e.status == 401) {
        // server restarted and forgot this session: start a fresh one
        try {
          await _newSession();
          _resetLocal();
          flash(t('err_generic'), error: true);
        } catch (_) {}
      } else if (!silent) {
        flash(e.message, error: true);
      }
      return null;
    } catch (e) {
      if (!silent) flash(t(errorKey(e)), error: true);
      return null;
    }
  }

  // ================================================================== preferences
  Future<void> setLang(String l) async {
    lang = l;
    await _prefs?.setString('lang', l);
    notifyListeners();
  }

  Future<void> setVoiceLang(String l) async {
    voiceLang = l;
    await _prefs?.setString('voiceLang', l);
    notifyListeners();
  }

  Future<void> setTts(bool on) async {
    ttsOn = on;
    await _prefs?.setBool('tts', on);
    if (!on) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
    if (i == 1) loadRecords();
  }

  /// AI keys typed in Settings (stored only on this phone).
  Map<String, String> get aiKeys => {
        'gemini': _prefs?.getString('key_gemini') ?? '',
        'groq': _prefs?.getString('key_groq') ?? '',
        'nvidia': _prefs?.getString('key_nvidia') ?? '',
        'proxy': _prefs?.getString('key_proxy') ?? '',
      };

  Future<void> setAiKeys({String gemini = '', String groq = '', String nvidia = '', String proxy = ''}) async {
    await _prefs?.setString('key_gemini', gemini.trim());
    await _prefs?.setString('key_groq', groq.trim());
    await _prefs?.setString('key_nvidia', nvidia.trim());
    await _prefs?.setString('key_proxy', proxy.trim());
    api.setKeys(aiKeys);
    final j = await _run(() => api.get('/health'));
    if (j is Map) aiMode = (j['ai_mode'] ?? aiMode).toString();
    notifyListeners();
  }

  /// Short status for the Settings screen.
  String get aiStatus {
    final st = api.llm.status();
    final prov = (st['providers'] as List).join(', ');
    return st['mode'] == 'ai' ? 'AI on: $prov${st['voice'] == true ? ' · voice on' : ''}' : 'Offline mode (no AI key)';
  }

  // ================================================================== chat + voice
  Future<bool> sendChat(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || sending) return false;
    chat = [...chat, {'role': 'user', 'text': text}];
    sending = true;
    notifyListeners();
    final j = await _run(() => api.post('/chat', {'text': text}));
    sending = false;
    if (j is Map) {
      final m = Map<String, dynamic>.from(j);
      final reply = m.s('reply') ?? '';
      chat = [...chat, {'role': 'assistant', 'text': reply}];
      _applyChatView(m);
      _addTrace(m['trace']);
      notifyListeners();
      _speak(reply);
      return true;
    }
    chat = chat.sublist(0, chat.length - 1); // take the optimistic message back
    notifyListeners();
    return false;
  }

  Future<void> skipQuestion() async {
    final j = await _run(() => api.post('/chat/skip'));
    if (j is Map) {
      _applyChatView(Map<String, dynamic>.from(j));
      notifyListeners();
    }
  }

  Future<String?> transcribe(String path) async {
    final j = await _run(() => api.multipart('/voice', {'language': ur ? 'ur' : 'auto'},
        fileField: 'file', filePath: path, fileName: path.split('/').last));
    return j is Map ? j['text']?.toString() : null;
  }

  Future<void> _speak(String text) async {
    if (!ttsOn || chatLang == 'roman' || text.isEmpty) return;
    try {
      await _tts.setLanguage(chatLang == 'ur' ? 'ur-PK' : 'en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.speak(text);
    } catch (_) {}
  }

  // ================================================================== deal
  Future<bool> evaluate() async {
    busy = true;
    notifyListeners();
    final j = await _run(() => api.post('/deal/evaluate', {'lang': lang}));
    busy = false;
    if (j is Map) {
      final m = Map<String, dynamic>.from(j);
      calc = m.m('calc');
      flags = m.l('flags');
      explain = m.s('explain');
      counter = null;
      stage = 'review';
      _addTrace(m['trace']);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<void> backToChat() async {
    await _run(() => api.post('/deal/back'));
    stage = 'describe';
    notifyListeners();
  }

  Future<bool> makeCounter(double target) async {
    busy = true;
    notifyListeners();
    final j = await _run(() => api.post('/deal/counter', {'target_hourly': target, 'lang': lang}));
    busy = false;
    if (j is Map) {
      final m = Map<String, dynamic>.from(j);
      counter = m.m('counter');
      flags = m.l('flags');
      calc = m.m('calc');
      minHourly = target;
      _addTrace(m['trace']);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> confirmAgreement() async {
    busy = true;
    notifyListeners();
    final j = await _run(() => api.post('/record/confirm'));
    busy = false;
    if (j is Map) {
      final m = Map<String, dynamic>.from(j);
      record = m.m('record');
      orderNo = record?.s('order_no');
      stage = 'confirmed';
      recordsData = null;
      _addTrace(m['trace']);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> checkPayment({
    required double received,
    required double advance,
    required double deductions,
    required bool partial,
    required String note,
    String? proofPath,
  }) async {
    final no = orderNo;
    if (no == null) return false;
    busy = true;
    blocked = false;
    notifyListeners();
    final j = await _run(() => api.multipart(
        '/payment/check',
        {
          'order_no': no,
          'received': received.toString(),
          'advance_paid': advance.toString(),
          'agreed_deductions': deductions.toString(),
          'is_partial': partial ? 'true' : 'false',
          'note': note,
          'lang': lang,
        },
        fileField: proofPath != null ? 'proof' : null,
        filePath: proofPath,
        fileName: proofPath?.split('/').last));
    busy = false;
    if (j is Map) {
      final m = Map<String, dynamic>.from(j);
      _addTrace(m['trace']);
      if (m.b('blocked')) {
        blocked = true;
        notifyListeners();
        return false;
      }
      report = m.m('report');
      msgText = m.s('msg_text') ?? '';
      follow = null;
      waUrl = null;
      stage = 'report';
      recordsData = null;
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  void setMsgText(String v) {
    msgText = v; // no notify: the text field owns the live value
  }

  Future<bool> approveMessage(String text) async {
    final j = await _run(() => api.post('/message/approve', {'text': text}));
    if (j is Map) {
      msgText = text;
      follow = 'approved';
      waUrl = j['whatsapp_url']?.toString();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> dismissMessage(String text) async {
    final j = await _run(() => api.post('/message/dismiss', {'text': text}));
    if (j is Map) {
      follow = 'dismissed';
      notifyListeners();
    }
  }

  Future<void> newOrder() async {
    final j = await _run(() => api.post('/chat/reset'));
    if (j is Map) {
      _applySnapshot(Map<String, dynamic>.from(j));
      counter = null;
      waUrl = null;
      blocked = false;
      notifyListeners();
    }
  }

  // ================================================================== records
  Future<void> loadRecords() async {
    recordsLoading = true;
    notifyListeners();
    final j = await _run(() => api.get('/records'));
    if (j is Map) recordsData = Map<String, dynamic>.from(j);
    recordsLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> verifyChain() async {
    final j = await _run(() => api.post('/records/verify'));
    return j is Map ? Map<String, dynamic>.from(j) : null;
  }

  Future<void> loadSample() async {
    final j = await _run(() => api.post('/demo/sample'));
    if (j != null) await loadRecords();
  }

  Future<void> tamper(String orderNo) async {
    final j = await _run(() => api.post('/demo/tamper', {'order_no': orderNo}));
    if (j != null) await loadRecords();
  }

  Future<void> restore(String orderNo) async {
    final j = await _run(() => api.post('/demo/restore', {'order_no': orderNo}));
    if (j != null) await loadRecords();
  }

  Future<void> wipeAll() async {
    final j = await _run(() => api.delete('/data'));
    if (j != null) {
      _resetLocal();
      await _run(() => _loadState());
      notifyListeners();
      await loadRecords();
    }
  }

  // ================================================================== safe mode
  /// Called on every touch. Keeps the server's idle timer in step with the app's timer.
  void touch() {
    final now = DateTime.now();
    _last = now;
    if (hasPin && !locked && now.difference(_lastPing).inSeconds >= 10) {
      _lastPing = now;
      unawaited(api.post('/ping').then((_) {}, onError: (_) {}));
    }
  }

  void _tick() {
    if (boot != Boot.ready || !hasPin || locked) {
      if (lockLeft.value != 0) lockLeft.value = 0;
      return;
    }
    final left = lockSeconds - DateTime.now().difference(_last).inSeconds;
    if (left <= 0) {
      lockNow();
    } else {
      lockLeft.value = left;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && hasPin && !locked && boot == Boot.ready) {
      if (DateTime.now().difference(_last).inSeconds >= lockSeconds) lockNow();
    }
  }

  Future<void> lockNow() async {
    if (!hasPin) return;
    locked = true;
    lockLeft.value = 0;
    notifyListeners();
    try {
      await api.post('/safe/lock');
    } catch (_) {}
  }

  /// Returns true when the PIN was right. On a wrong PIN, attemptsLeft / lockWait are updated.
  Future<bool> verifyPin(String pin) async {
    try {
      final j = Map<String, dynamic>.from(await api.post('/safe/verify', {'pin': pin}) as Map);
      final ok = j.b('ok');
      _applySafe(j);
      if (ok) {
        locked = false;
        lockWait = 0;
        _last = DateTime.now();
        try {
          await _loadState();
        } catch (_) {}
      }
      notifyListeners();
      return ok;
    } on ApiException catch (e) {
      if (e.status == 429) {
        try {
          _applySafe(Map<String, dynamic>.from(await api.get('/safe') as Map));
        } catch (_) {}
        notifyListeners();
      } else {
        flash(e.message, error: true);
      }
      return false;
    } catch (e) {
      flash(t(errorKey(e)), error: true);
      return false;
    }
  }

  Future<String?> setPin(String pin) async {
    try {
      final j = await api.post('/safe/pin', {'pin': pin});
      _applySafe(Map<String, dynamic>.from(j as Map));
      locked = false;
      _last = DateTime.now();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return t(errorKey(e));
    }
  }

  /// null = success, otherwise an error message (wrong PIN, lockout ...).
  Future<String?> turnOffPin(String pin) async {
    try {
      final j = await api.post('/safe/off', {'pin': pin});
      _applySafe(Map<String, dynamic>.from(j as Map));
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return t(errorKey(e));
    }
  }

  Future<void> setLockSeconds(int s) async {
    final j = await _run(() => api.post('/safe/lock_seconds', {'seconds': s}));
    if (j is Map) {
      _applySafe(Map<String, dynamic>.from(j));
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    lockLeft.dispose();
    super.dispose();
  }
}

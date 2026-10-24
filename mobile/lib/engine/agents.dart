import 'dart:convert';

import '../util.dart';
import 'calc.dart' as calc;
import 'llm.dart';
import 'offline.dart' as offline;
import 'records.dart';
import 'schemas.dart';

/// Orchestrator + the three agents. The AI understands language, chooses which tool to call and
/// writes plain-language explanations. Code does the maths and the record keeping. If no AI is
/// reachable, the rule-based path keeps the app working.

const List<String> _badWords = [
  'چور', 'دھوکہ', 'دھوکا', 'فراڈ', 'جھوٹ', 'بے ایمان', 'cheat', 'fraud', 'thief', 'liar', 'scam', 'steal',
  'dhoka', 'chor', 'jhoot',
];
const String _digitsFrom = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';

String _ascii(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = _digitsFrom.indexOf(ch);
    b.write(i >= 0 ? '${i % 10}' : ch);
  }
  return b.toString();
}

Set<double> _nums(String s) => RegExp(r'\d+(?:\.\d+)?')
    .allMatches(_ascii(s).replaceAll(',', ''))
    .map((m) => double.parse(m.group(0)!))
    .toSet();

/// AI-written text is used only if every number in it appears in the facts and it has no accusing word.
bool safeText(String text, Object? facts) {
  final low = text.toLowerCase();
  final known = _nums(jsonEncode(facts, toEncodable: (o) => o.toString()));
  return _nums(text).every(known.contains) && !_badWords.any(low.contains);
}

String? _guard(Trace trace, String agent, String? text, Object? facts) {
  if (text == null || text.isEmpty) return null;
  if (safeText(text, facts)) return text;
  trace.add(agent, 'safety_check', 'check', {'text': text.length > 80 ? text.substring(0, 80) : text},
      'rejected (unknown number or accusing word): fixed template used', false, 0);
  return null;
}

const Map<String, String> kLangName = {
  'en': 'English',
  'roman': 'Roman Urdu (Urdu written in English letters)',
  'ur': 'Urdu (Urdu script)',
};

/// Every model call and tool call lands here and is shown in the AI view.
class Trace {
  final List<Map<String, dynamic>> store;
  Trace(this.store);

  void add(String agent, String tool, String kind,
      [Map<String, dynamic>? args, Object? result, bool ok = true, int ms = 0]) {
    store.add({
      'n': store.length + 1,
      'agent': agent,
      'tool': tool,
      'kind': kind,
      'args': args ?? <String, dynamic>{},
      'result': result,
      'ok': ok,
      'ms': ms,
    });
  }
}

Future<Map<String, dynamic>> _llmCall(Llm llm, Trace trace, String agent, List<Map<String, dynamic>> messages,
    {List<Map<String, dynamic>>? tools, double temperature = 0.2, int maxTokens = 900}) async {
  final sw = Stopwatch()..start();
  final resp = await llm.chat(messages, tools: tools, temperature: temperature, maxTokens: maxTokens);
  trace.add(agent, 'model_call', 'ai', {
    'provider': resp['provider'],
    'model': resp['model'],
    'tool_calls': [for (final c in resp['tool_calls'] as List) c['name']],
  }, null, true, (resp['ms'] as int) != 0 ? resp['ms'] as int : sw.elapsedMilliseconds);
  return resp;
}

// ====================================================================== tools
const Map<String, String> _fieldDoc = {
  'item': 'kind of product, e.g. dress, frock, suit',
  'quantity': 'number of pieces in the order (integer)',
  'rate_per_piece': 'payment in Rs for ONE piece',
  'deadline_days': 'days allowed to finish the order',
  'material_expenses': 'total Rs she will spend on thread, cloth, etc. Use 0 if she says nothing',
  'estimated_hours': 'total hours she expects the whole order to take',
  'payment_terms': "when/how she will be paid, e.g. 'on delivery'",
  'contractor_name': 'name of the contractor, if given',
  'other_terms': 'any other condition, e.g. deductions mentioned',
  'advance_received': 'advance already paid to her in Rs',
};
const Map<String, String> _types = {
  'item': 'string',
  'payment_terms': 'string',
  'contractor_name': 'string',
  'other_terms': 'string',
  'quantity': 'integer',
  'deadline_days': 'integer',
};

final List<Map<String, dynamic>> kChatTools = [
  {
    'type': 'function',
    'function': {
      'name': 'record_order_details',
      'description': 'Save order details the worker just mentioned. Call it every time she gives any new detail. '
          'Only include fields she actually stated. Never guess.',
      'parameters': {
        'type': 'object',
        'properties': {
          for (final f in kFields) f: {'type': _types[f] ?? 'number', 'description': _fieldDoc[f]},
        },
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'calculate_deal',
      'description': 'Run the deterministic calculation (expected payment, earnings after expenses, hourly rate, '
          'risk flags). Call it only when quantity and rate are known.',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  },
];

final List<Map<String, dynamic>> kPaymentTools = [
  {
    'type': 'function',
    'function': {
      'name': 'get_record',
      'description': 'Fetch the saved agreement for an order, including its integrity check.',
      'parameters': {
        'type': 'object',
        'properties': {'order_no': {'type': 'string'}},
        'required': ['order_no'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'compare_payment',
      'description': 'Compare the agreed expected payment with what she received. advance_paid is money paid to her '
          'earlier (not part of received). agreed_deductions are deductions both sides agreed in advance.',
      'parameters': {
        'type': 'object',
        'properties': {
          'order_no': {'type': 'string'},
          'received': {'type': 'number'},
          'advance_paid': {'type': 'number'},
          'agreed_deductions': {'type': 'number'},
          'is_partial': {'type': 'boolean'},
        },
        'required': ['order_no', 'received'],
      },
    },
  },
];

/// Plain, testable functions the agents can call. The AI decides WHEN; the numbers always come from calc.dart.
class ToolBox {
  final Records records;
  final Map<String, dynamic> state;
  final Trace trace;
  ToolBox(this.records, this.state, this.trace);

  Map<String, dynamic> run(String agent, String name, Map<String, dynamic>? args) {
    final sw = Stopwatch()..start();
    Map<String, dynamic> res;
    var ok = true;
    try {
      switch (name) {
        case 'record_order_details':
          res = recordOrderDetails(args ?? {});
          break;
        case 'calculate_deal':
          res = calculateDeal();
          break;
        case 'get_record':
          res = getRecord((args?['order_no'] ?? '').toString());
          break;
        case 'compare_payment':
          final a = args ?? {};
          res = comparePayment(
              (a['order_no'] ?? '').toString(), a['received'], a['advance_paid'], a['agreed_deductions'],
              a['is_partial'] == true);
          break;
        default:
          res = {'error': 'unknown tool'};
      }
      ok = !res.containsKey('error');
    } on calc.ValueError catch (e) {
      res = {'error': e.message};
      ok = false;
    } catch (e) {
      res = {'error': e.toString()};
      ok = false;
    }
    trace.add(agent, name, 'code', args, res, ok, sw.elapsedMilliseconds);
    return res;
  }

  Map<String, dynamic> get _draft => (state['draft'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  Map<String, dynamic> recordOrderDetails(Map<String, dynamic> fields) {
    final draft = _draft;
    final r = mergeFields(draft, fields);
    return {
      'updated': r.updated,
      'errors': r.errors,
      'draft': publicDraft(draft),
      'missing_required': missingRequired(draft),
      'next_question': nextQuestion(draft),
    };
  }

  Map<String, dynamic> calculateDeal() {
    final d = _draft;
    final miss = missingRequired(d);
    if (miss.isNotEmpty) return {'error': 'missing required fields: $miss'};
    final c = calc.calculateDeal(d['quantity'], d['rate_per_piece'], d['material_expenses'], d['estimated_hours']);
    final flags = calc.analyzeRisks(d, c, state['min_hourly'] as num?);
    state['calc'] = c;
    state['flags'] = flags;
    return {
      'calc': c,
      'flags': [for (final f in flags) {'level': f['level'], 'code': f['code']}],
    };
  }

  Map<String, dynamic> getRecord(String orderNo) {
    final r = records.latestRecord(orderNo);
    if (r == null) return {'error': 'no record for $orderNo'};
    final v = records.verifyRecord(r);
    state['agreement'] = r;
    final data = r['data'] as Map<String, dynamic>;
    return {
      'order_no': orderNo,
      'version': r['version'],
      'hash': (r['hash'] as String).substring(0, 16),
      'integrity_ok': v['ok'],
      'changed_fields': v['changed_fields'],
      'agreement': {
        for (final k in ['item', 'quantity', 'rate_per_piece', 'expected_total', 'deadline_days', 'payment_terms'])
          k: data[k]
      },
    };
  }

  Map<String, dynamic> comparePayment(String orderNo, Object? received, Object? advancePaid,
      Object? agreedDeductions, bool isPartial) {
    final r = (state['agreement'] as Map<String, dynamic>?) ?? records.latestRecord(orderNo);
    if (r == null) return {'error': 'no record for $orderNo'};
    final res = calc.comparePayment((r['data'] as Map<String, dynamic>)['expected_total'], received,
        advancePaid: advancePaid, agreedDeductions: agreedDeductions, isPartial: isPartial);
    state['last_compare'] = res;
    return res;
  }
}

// ====================================================================== Orchestrator
class Orchestrator {
  final Records records;
  final Map<String, dynamic> state;
  final Trace trace;
  final Llm llm;
  late final ToolBox tools = ToolBox(records, state, trace);
  Orchestrator(this.records, this.state, this.trace, this.llm);

  String _system(String lang) {
    final d = (state['draft'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return 'You are Amana, a warm, calm assistant for a woman who does piecework from home in Pakistan '
        '(stitching, embroidery, handicrafts). She talks about an order a contractor offered her.\n'
        'Reply in ${kLangName[lang]}, matching how she writes. Use very simple words and 1-3 short sentences.\n'
        'Rules:\n'
        '- Whenever she gives order details, call record_order_details with ONLY what she stated.\n'
        '- NEVER do arithmetic or state totals, profit or hourly rates yourself. Numbers come from tools.\n'
        "- After recording, ask exactly ONE question: the tool's next_question (one short sentence). "
        "If next_question is null and quantity and rate are known, tell her she can press the 'Show me the numbers' button.\n"
        '- If a tool returns errors for a field, politely ask her to confirm that number.\n'
        '- Never promise profit, never accuse the contractor, never give legal advice.\n'
        'Current saved details: ${jsonEncode(publicDraft(d))}\n'
        'Question she is answering now: ${state['asked_field']}';
  }

  Future<String> handle(String raw, String? askedField) async {
    final text = offline.normalize(raw);
    final lang = offline.detectLang(text);
    state['chat_lang'] = lang;
    state['asked_field'] = askedField;
    if (llm.available().isNotEmpty) {
      try {
        return await _handleLlm(text, lang, askedField);
      } on LLMUnavailable catch (e) {
        trace.add('Orchestrator', 'fallback', 'code', {'reason': e.message}, 'using rule-based parser', false, 0);
      }
    }
    return _handleOffline(text, lang, askedField);
  }

  String _handleOffline(String text, String lang, String? askedField) {
    final fields = offline.extractOffline(text, askedField);
    final res = tools.run('Deal Intelligence', 'record_order_details', fields);
    final d = state['draft'] as Map<String, dynamic>;
    return offline.replyOffline(d, List<String>.from(res['updated'] as List), Map<String, String>.from(res['errors'] as Map),
        res['next_question'] as String?, lang, missingRequired(d).isEmpty);
  }

  Future<String> _handleLlm(String text, String lang, String? askedField) async {
    final chat = (state['chat'] as List?) ?? const [];
    final recent = chat.length > 8 ? chat.sublist(chat.length - 8) : chat;
    final hist = [
      for (final m in recent)
        {'role': (m as Map)['role'] == 'user' ? 'user' : 'assistant', 'content': m['text']}
    ];
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _system(lang)},
      ...hist,
      {'role': 'user', 'content': text},
    ];
    var calledRecord = false;
    for (var i = 0; i < 5; i++) {
      final resp = await _llmCall(llm, trace, 'Orchestrator', messages, tools: kChatTools);
      final calls = resp['tool_calls'] as List;
      final content = resp['content'] as String;
      if (calls.isEmpty) {
        if (!calledRecord) {
          // safety net: the model skipped the tool
          final fields = offline.extractOffline(text, askedField);
          if (fields.isNotEmpty) {
            tools.run('Deal Intelligence', 'record_order_details', fields);
            return content.isNotEmpty ? content : _handleOffline(text, lang, null);
          }
        }
        return content.isNotEmpty ? content : _handleOffline(text, lang, askedField);
      }
      messages.add(llm.assistantMessage(resp));
      for (final c in calls) {
        Map<String, dynamic> res;
        if (c['name'] == 'record_order_details') {
          calledRecord = true;
          res = tools.run('Deal Intelligence', c['name'] as String, Map<String, dynamic>.from(c['arguments'] as Map));
        } else if (c['name'] == 'calculate_deal') {
          res = tools.run('Deal Intelligence', c['name'] as String, {});
        } else {
          res = {'error': 'unknown tool'};
        }
        messages.add({'role': 'tool', 'tool_call_id': c['id'], 'content': jsonEncode(res)});
      }
    }
    return _handleOffline(text, lang, askedField);
  }
}

// ====================================================================== Deal Intelligence
Future<String?> _simpleLlm(Llm llm, Trace trace, String agent, String system, String user, {int maxTokens = 400}) async {
  try {
    final r = await _llmCall(llm, trace, agent, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ], temperature: 0.3, maxTokens: maxTokens);
    final c = r['content'] as String;
    return c.isEmpty ? null : c;
  } on LLMUnavailable {
    return null;
  }
}

class DealAgent {
  final Records records;
  final Map<String, dynamic> state;
  final Trace trace;
  final Llm llm;
  late final ToolBox tools = ToolBox(records, state, trace);
  DealAgent(this.records, this.state, this.trace, this.llm);

  Map<String, dynamic> evaluate() => tools.run('Deal Intelligence', 'calculate_deal', {});

  Future<String> explain(String lang) async {
    final c = state['calc'] as Map<String, dynamic>;
    final flags = state['flags'] as List;
    final nonGreen = [for (final f in flags) if (f['level'] != 'green') f['en']];
    final facts = {
      'expected_total': c['expected_total'],
      'net_after_expenses': c['net_after_expenses'],
      'hourly_net': c['hourly_net'],
      'flags': nonGreen,
    };
    final txt = await _simpleLlm(
        llm,
        trace,
        'Deal Intelligence',
        'You explain a piecework offer to a home-based woman worker in ${kLangName[lang]}. '
            'Use ONLY the numbers given, never add or change numbers. 2-3 very short sentences. '
            'Say these are estimates from her own figures, not guaranteed profit. Mention the most important flag if any.',
        jsonEncode(facts));
    final ok = _guard(trace, 'Deal Intelligence', txt,
        {'calc': c, 'draft': publicDraft(state['draft'] as Map<String, dynamic>), 'flags': nonGreen});
    return ok ?? _template(c, flags, lang);
  }

  static String _template(Map<String, dynamic> c, List flags, String lang) {
    final n = flags.where((f) => f['level'] != 'green').length;
    final hr = c['hourly_net'] as num?;
    final net = c['net_after_expenses'] as num?;
    final total = c['expected_total'] as num?;
    if (lang == 'ur') {
      var s = 'کل ادائیگی ${fmtRs(total)} بنتی ہے۔';
      if (net != null) s += ' خرچے کے بعد ${fmtRs(net)} بچتے ہیں۔';
      if (hr != null) s += ' یعنی تقریباً ${fmtRs(hr)} فی گھنٹہ۔';
      return '$s یہ آپ کے بتائے ہوئے اعداد پر اندازہ ہے، پکی کمائی نہیں۔ دیکھنے والی باتیں: $n۔';
    }
    if (lang == 'roman') {
      var s = 'Kul payment ${fmtRs(total)} banti hai.';
      if (net != null) s += ' Kharche ke baad ${fmtRs(net)} bachte hain.';
      if (hr != null) s += ' Yaani taqreeban ${fmtRs(hr)} per ghanta.';
      return '$s Yeh aap ke bataye hue figures par andaza hai, pakki kamai nahi. Dekhne wali baatein: $n.';
    }
    var s = 'The total payment is ${fmtRs(total)}.';
    if (net != null) s += ' After costs, about ${fmtRs(net)} is left.';
    if (hr != null) s += ' That is roughly ${fmtRs(hr)} per hour.';
    return '$s These are estimates from your own figures, not guaranteed profit. Things to check: $n.';
  }

  Future<Map<String, dynamic>> counteroffer(num targetHourly, String lang) async {
    final d = state['draft'] as Map<String, dynamic>;
    if (d['estimated_hours'] == null) return {'error': 'hours missing'};
    final sw = Stopwatch()..start();
    final res = calc.requiredRateForTarget(
        d['quantity'], d['material_expenses'] ?? 0, d['estimated_hours'], targetHourly, d['rate_per_piece']);
    trace.add('Deal Intelligence', 'required_rate_for_target', 'code', {'target_hourly': targetHourly}, res, true,
        sw.elapsedMilliseconds);
    final facts = {
      'item': d['item'] ?? 'pieces',
      'quantity': d['quantity'],
      'current_rate': res['current_rate'],
      'suggested_rate': res['suggested_rate'],
      'hours': d['estimated_hours'],
      'expenses': d['material_expenses'] ?? 0,
    };
    final msg = await _simpleLlm(
        llm,
        trace,
        'Deal Intelligence',
        'Write a short, polite WhatsApp message in ${kLangName[lang]} from a woman home-worker to her contractor '
            'asking to do the order at the suggested rate. Use ONLY the given numbers. Also ask to confirm the deadline and '
            'payment date. No threats, no accusations. Max 70 words. Output only the message.',
        jsonEncode(facts));
    final ok = _guard(trace, 'Deal Intelligence', msg, {'facts': facts, 'result': res});
    res['message'] = ok ?? _counterTemplate(facts, lang);
    return res;
  }

  static String _counterTemplate(Map<String, dynamic> f, String lang) {
    final it = f['item'];
    final q = fmtNum(f['quantity'] as num?);
    final sr = fmtNum(f['suggested_rate'] as num?);
    final cr = fmtNum(f['current_rate'] as num?);
    final h = fmtNum(f['hours'] as num?);
    if (lang == 'ur') {
      return 'السلام علیکم۔ $q $it کے آرڈر کے لیے میں Rs $sr فی پیس پر کام کر سکتی ہوں '
          '(ابھی Rs $cr ہے)، کیونکہ مٹیریل اور تقریباً $h گھنٹے کا کام ہے۔ '
          'براہِ مہربانی ڈیڈ لائن اور ادائیگی کی تاریخ بھی طے کر لیں۔ شکریہ۔';
    }
    if (lang == 'roman') {
      return 'Assalam o Alaikum. $q $it ke order ke liye main Rs $sr per piece par kaam kar sakti hoon '
          '(abhi Rs $cr hai), kyunke material aur taqreeban $h ghante ka kaam hai. '
          'Meherbani karke deadline aur payment ki tareekh bhi tay kar lein. Shukriya.';
    }
    return 'Assalam o Alaikum. For the order of $q $it, I can do the work at Rs $sr per piece '
        '(currently Rs $cr), because of the material costs and about $h hours of work. '
        'Could we also confirm the deadline and the payment date? Thank you.';
  }
}

// ====================================================================== Work Record
class WorkRecordAgent {
  final Records records;
  final Map<String, dynamic> state;
  final Trace trace;
  WorkRecordAgent(this.records, this.state, this.trace);

  /// Called ONLY after the woman presses Confirm.
  Map<String, dynamic> saveConfirmed({bool isSample = false}) {
    final d = state['draft'] as Map<String, dynamic>;
    final c = state['calc'] as Map<String, dynamic>;
    final order = cleanOrder(d);
    final data = <String, dynamic>{
      ...order,
      'expected_total': c['expected_total'],
      'net_after_expenses': c['net_after_expenses'],
      'hourly_net': c['hourly_net'],
    };
    final sources = <String, dynamic>{
      for (final e in order.entries) if (e.value != null) e.key: 'reported_by_worker',
      'expected_total': 'calculated',
      'net_after_expenses': 'calculated',
      'hourly_net': 'calculated',
    };
    data['sources'] = sources;
    final sw = Stopwatch()..start();
    final rec = records.createRecord(data, isSample: isSample);
    trace.add('Work Record', 'create_record', 'code', {'order_no': rec['order_no'], 'version': 1},
        {'hash': (rec['hash'] as String).substring(0, 16), 'prev': (rec['prev_hash'] as String).substring(0, rec['prev_hash'] == Records.genesis ? 7 : 16)},
        true, sw.elapsedMilliseconds);
    final v = records.verifyRecord(rec);
    trace.add('Work Record', 'verify_record', 'check', {'order_no': rec['order_no']}, {'integrity_ok': v['ok']},
        v['ok'] as bool, 1);
    return rec;
  }
}

// ====================================================================== Payment Discrepancy
const Map<String, Map<String, String>> _tExpl = {
  'match': {
    'en': 'The payment matches the agreement. Nothing to follow up.',
    'roman': 'Payment agreement ke mutabiq hai. Kisi follow-up ki zaroorat nahi.',
    'ur': 'ادائیگی طے شدہ رقم کے مطابق ہے۔ کسی فالو اپ کی ضرورت نہیں۔'
  },
  'explained': {
    'en': 'The gap of {diff} is fully explained by the advance ({adv}) and agreed deductions ({ded}).',
    'roman': '{diff} ka farq poori tarah advance ({adv}) aur tay shuda katautiyon ({ded}) se samajh aata hai.',
    'ur': '{diff} کا فرق پیشگی ({adv}) اور طے شدہ کٹوتیوں ({ded}) سے مکمل طور پر واضح ہے۔'
  },
  'short': {
    'en': 'You received {rec} against {exp}. {unx} is not explained by any advance or agreed deduction.',
    'roman': 'Aap ko {rec} mile jabke tay {exp} tha. {unx} kisi advance ya tay shuda katauti se wazeh nahi hota.',
    'ur': 'آپ کو {rec} ملے جبکہ طے شدہ رقم {exp} تھی۔ {unx} کسی پیشگی یا طے شدہ کٹوتی سے واضح نہیں ہوتے۔'
  },
  'partial_pending': {
    'en': 'This looks like a partial payment. {unx} is still outstanding.',
    'roman': 'Yeh partial payment lagti hai. {unx} abhi baqi hain.',
    'ur': 'یہ جزوی ادائیگی لگتی ہے۔ {unx} ابھی باقی ہیں۔'
  },
  'over': {
    'en': 'You received {unx} more than the agreed amount. It may be a bonus or a mistake; worth confirming.',
    'roman': 'Aap ko tay shuda raqam se {unx} zyada mile. Yeh bonus ya ghalti ho sakti hai; confirm kar lein.',
    'ur': 'آپ کو طے شدہ رقم سے {unx} زیادہ ملے۔ یہ بونس یا غلطی ہو سکتی ہے؛ تصدیق کر لیں۔'
  },
};
const Map<String, Map<String, String>> _tMiss = {
  'adv': {
    'en': 'Was any advance paid to you earlier for this order?',
    'roman': 'Kya is order ka koi advance pehle mila tha?',
    'ur': 'کیا اس آرڈر کی کوئی پیشگی رقم پہلے ملی تھی؟'
  },
  'ded': {
    'en': 'Was any deduction agreed in advance (for example for faults or transport)?',
    'roman': 'Kya koi katauti pehle se tay hui thi (masalan nuqs ya transport)?',
    'ur': 'کیا کوئی کٹوتی پہلے سے طے ہوئی تھی (مثلاً نقص یا ٹرانسپورٹ)؟'
  },
  'part': {
    'en': 'Is more payment still expected for this order?',
    'roman': 'Kya is order ki baqi payment abhi aani hai?',
    'ur': 'کیا اس آرڈر کی باقی ادائیگی ابھی آنی ہے؟'
  },
  'proof': {
    'en': 'Do you have a photo of the order slip or a receipt?',
    'roman': 'Kya order slip ya raseed ki photo hai?',
    'ur': 'کیا آرڈر پرچی یا رسید کی تصویر موجود ہے؟'
  },
};
const Map<String, String> _tDraft = {
  'en': 'Assalam o Alaikum. For order {no} ({q} {it}, Rs {r:g} per piece) the agreed total was {exp}. I have received {rec}, '
      'so there is a difference of {unx}. Could you please let me know the reason for the difference, or when the remaining '
      'payment will be made? Thank you.',
  'roman': 'Assalam o Alaikum. Order {no} ({q} {it}, Rs {r:g} per piece) ka tay shuda total {exp} tha. Mujhe {rec} mile hain, '
      'is liye {unx} ka farq reh gaya hai. Meherbani karke bata dein ke yeh farq kis wajah se hai, ya baqi payment kab tak '
      'mil jayegi. Shukriya.',
  'ur': 'السلام علیکم۔ آرڈر {no} ({q} {it}، Rs {r:g} فی پیس) کا طے شدہ کل {exp} تھا۔ مجھے {rec} ملے ہیں، یوں {unx} کا فرق ہے۔ '
      'مہربانی کرکے بتا دیں کہ یہ فرق کس وجہ سے ہے، یا باقی ادائیگی کب تک ہوگی۔ شکریہ۔',
};

String _fill(String tpl, Map<String, dynamic> cmp) => tpl
    .replaceAll('{diff}', fmtRs(cmp['difference'] as num))
    .replaceAll('{adv}', fmtRs(cmp['advance_paid'] as num))
    .replaceAll('{ded}', fmtRs(cmp['agreed_deductions'] as num))
    .replaceAll('{rec}', fmtRs(cmp['received'] as num))
    .replaceAll('{exp}', fmtRs(cmp['expected'] as num))
    .replaceAll('{unx}', fmtRs((cmp['unexplained'] as num).abs()));

class _Narrative {
  final String explanation;
  final List<String> missingInfo;
  final String draftMessage;
  _Narrative(this.explanation, this.missingInfo, this.draftMessage);
}

class PaymentAgent {
  final Records records;
  final Map<String, dynamic> state;
  final Trace trace;
  final Llm llm;
  late final ToolBox tools = ToolBox(records, state, trace);
  PaymentAgent(this.records, this.state, this.trace, this.llm);

  Future<Map<String, dynamic>> run(String orderNo, double received, double advancePaid, double agreedDeductions,
      bool isPartial, String note, String lang, {bool hasProof = false}) async {
    state.remove('last_compare');
    state.remove('agreement');
    _Narrative? narrative;
    if (llm.available().isNotEmpty) {
      try {
        narrative = await _llmLoop(orderNo, received, advancePaid, agreedDeductions, isPartial, note, lang);
      } on LLMUnavailable catch (e) {
        trace.add('Payment Discrepancy', 'fallback', 'code', {'reason': e.message}, 'using rule-based report', false, 0);
      }
    }
    // the numbers always come from deterministic tools, even if the model skipped them
    if (!state.containsKey('agreement')) tools.run('Payment Discrepancy', 'get_record', {'order_no': orderNo});
    final lc = state['last_compare'] as Map<String, dynamic>?;
    if (lc == null || lc['received'] != calc.out(received)) {
      tools.run('Payment Discrepancy', 'compare_payment', {
        'order_no': orderNo,
        'received': received,
        'advance_paid': advancePaid,
        'agreed_deductions': agreedDeductions,
        'is_partial': isPartial,
      });
    }
    final rec = state['agreement'] as Map<String, dynamic>;
    final integrity = records.verifyRecord(rec);
    if (!(integrity['ok'] as bool)) {
      // never build a payment report on a record that changed after saving
      trace.add('Payment Discrepancy', 'integrity_gate', 'check', {'order_no': orderNo},
          {'integrity_ok': false, 'changed_fields': integrity['changed_fields']}, false, 0);
      return {'blocked': true, 'integrity': integrity, 'order_no': orderNo};
    }
    final cmp = state['last_compare'] as Map<String, dynamic>;
    final d = rec['data'] as Map<String, dynamic>;
    final status = cmp['status'] as String;
    var missing = _missing(cmp, advancePaid, agreedDeductions, isPartial, hasProof, lang);
    var explanation = _fill(_tExpl[status]![lang] ?? _tExpl[status]!['en']!, cmp);
    var draft = '';
    if (status == 'short' || status == 'partial_pending' || status == 'over') {
      draft = _fill(
          _tDraft[lang]!
              .replaceAll('{no}', orderNo)
              .replaceAll('{q}', fmtNum(d['quantity'] as num?))
              .replaceAll('{it}', (d['item'] ?? 'pieces').toString())
              .replaceAll('{r:g}', fmtNum((d['rate_per_piece'] ?? 0) as num)),
          cmp);
    }
    if (narrative != null) {
      // the model's wording may replace the template wording, never the numbers
      final facts = {'comparison': cmp, 'order': orderNo, 'agreement': d};
      explanation = _guard(trace, 'Payment Discrepancy', narrative.explanation, facts) ?? explanation;
      draft = _guard(trace, 'Payment Discrepancy', narrative.draftMessage, facts) ?? draft;
      final kept = [
        for (final m in narrative.missingInfo)
          if (_guard(trace, 'Payment Discrepancy', m, facts) != null) m
      ];
      if (kept.isNotEmpty) missing = kept;
    }
    return {
      'comparison': cmp,
      'explanation': explanation,
      'missing_info': missing,
      'draft_message': draft,
      'integrity': integrity,
      'order_no': orderNo,
      'agreement_hash': rec['hash'],
      'note': note,
    };
  }

  static List<String> _missing(Map<String, dynamic> cmp, double adv, double ded, bool partial, bool proof, String lang) {
    final l = _tMiss['adv']!.containsKey(lang) ? lang : 'en';
    final out = <String>[];
    final st = cmp['status'];
    if (st == 'short' || st == 'partial_pending') {
      if (adv == 0) out.add(_tMiss['adv']![l]!);
      if (ded == 0) out.add(_tMiss['ded']![l]!);
      if (!partial) out.add(_tMiss['part']![l]!);
    }
    if (st != 'match' && !proof) out.add(_tMiss['proof']![l]!);
    return out;
  }

  Future<_Narrative?> _llmLoop(String orderNo, double received, double advancePaid, double agreedDeductions,
      bool isPartial, String note, String lang) async {
    final sys = 'You are the Payment Discrepancy Agent for Amana, helping a home-based woman worker check a payment. '
        'Steps: 1) call get_record, 2) call compare_payment with her numbers, 3) answer. '
        'Write in ${kLangName[lang]}, very simple words. Final answer must be ONLY a JSON object: '
        '{"explanation": "...", "missing_info": ["question 1", ...], "draft_message": "..."}. '
        'explanation: 2 short sentences using ONLY numbers from compare_payment. missing_info: up to 3 short questions '
        'about what is still unknown (advance, agreed deduction, partial payment, proof). draft_message: a polite message '
        'to the contractor asking for clarification, empty string if the payment matches. '
        'Never accuse anyone, never promise to recover money, never invent numbers.';
    final user = 'Order $orderNo. Received Rs ${fmtNum(received)}. Advance paid earlier: Rs ${fmtNum(advancePaid)}. '
        'Agreed deductions: Rs ${fmtNum(agreedDeductions)}. Partial payment: ${isPartial ? 'True' : 'False'}. '
        "Her note: ${note.isEmpty ? '-' : note}";
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': user},
    ];
    for (var i = 0; i < 5; i++) {
      final resp = await _llmCall(llm, trace, 'Payment Discrepancy', messages, tools: kPaymentTools, maxTokens: 900);
      final calls = resp['tool_calls'] as List;
      if (calls.isEmpty) return _parse(resp['content'] as String);
      messages.add(llm.assistantMessage(resp));
      for (final c in calls) {
        final a = Map<String, dynamic>.from(c['arguments'] as Map);
        Map<String, dynamic> res;
        if (c['name'] == 'compare_payment') {
          // never trust model-copied numbers: use what she entered
          a.addAll({
            'order_no': orderNo,
            'received': received,
            'advance_paid': advancePaid,
            'agreed_deductions': agreedDeductions,
            'is_partial': isPartial,
          });
          res = tools.run('Payment Discrepancy', 'compare_payment', a);
        } else if (c['name'] == 'get_record') {
          a['order_no'] = orderNo;
          res = tools.run('Payment Discrepancy', 'get_record', a);
        } else {
          res = {'error': 'unknown tool'};
        }
        messages.add({'role': 'tool', 'tool_call_id': c['id'], 'content': jsonEncode(res)});
      }
    }
    return null;
  }

  static _Narrative? _parse(String text) {
    if (text.isEmpty) return null;
    final m = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
    if (m == null) return null;
    try {
      final j = jsonDecode(m.group(0)!);
      if (j is! Map) return null;
      final ex = j['explanation'];
      if (ex is! String || ex.length < 3 || ex.length > 700) return null;
      final mi = j['missing_info'] ?? const [];
      if (mi is! List || mi.length > 5 || mi.any((e) => e is! String)) return null;
      final dm = j['draft_message'] ?? '';
      if (dm is! String || dm.length > 900) return null;
      return _Narrative(ex, List<String>.from(mi), dm);
    } catch (_) {
      return null;
    }
  }
}

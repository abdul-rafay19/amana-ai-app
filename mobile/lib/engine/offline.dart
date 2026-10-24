import '../util.dart';
import 'schemas.dart';

/// Rule-based fallback so Amana still works with no AI key or no internet.
/// Handles English, Roman Urdu and Urdu script for the common order phrasing.

const String _east = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';

const Map<String, int> _wordNum = {
  'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'twelve': 12, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'hundred': 100,
  'teen': 3, 'char': 4, 'panch': 5, 'paanch': 5, 'chay': 6, 'saat': 7, 'aath': 8, 'nau': 9, 'das': 10,
  'bees': 20, 'tees': 30, 'pachas': 50, 'تین': 3, 'چار': 4, 'پانچ': 5, 'چھ': 6, 'سات': 7, 'آٹھ': 8,
  'نو': 9, 'دس': 10, 'بیس': 20, 'تیس': 30, 'پچاس': 50,
};

String normalize(String? text) {
  final b = StringBuffer();
  for (final ch in (text ?? '').split('')) {
    final i = _east.indexOf(ch);
    b.write(i >= 0 ? '${i % 10}' : ch);
  }
  var t = b.toString();
  t = t.replaceAll(RegExp(r'[\u060C\u061B\u061F\u06D4]'), ' ');
  t = t.replaceAllMapped(RegExp(r'(?<=\d),(?=\d{3}\b)'), (m) => '');
  t = t.replaceAllMapped(RegExp(r'[A-Za-z0-9_\u0600-\u06FF]+'), (m) {
    final w = m.group(0)!;
    final n = _wordNum[w.toLowerCase()];
    return n != null ? '$n' : w;
  });
  return t.trim();
}

final RegExp _urduRe = RegExp(r'[\u0600-\u06FF]');
const Set<String> _roman = {
  'din', 'dino', 'rupay', 'rupaye', 'hai', 'hain', 'mein', 'ka', 'ke', 'ki', 'kar', 'dena', 'mila',
  'mili', 'kapra', 'kapray', 'ghante', 'ghanta', 'lagega', 'lagenge', 'mujhe', 'meri', 'mera', 'har',
  'aur', 'kharcha', 'kharch', 'peshgi', 'order', 'hoga', 'wala', 'karna', 'kitne', 'kitna', 'se',
  'payment', 'milegi', 'milenge', 'jora', 'joray', 'bana', 'banana', 'silai',
};

/// 'ur' (Urdu script), 'roman' (Roman Urdu) or 'en'.
String detectLang(String? text) {
  final t = text ?? '';
  if (_urduRe.hasMatch(t)) return 'ur';
  final words = RegExp(r'[a-z]+').allMatches(t.toLowerCase()).map((m) => m.group(0)!).toSet();
  return words.intersection(_roman).length >= 2 ? 'roman' : 'en';
}

const Set<String> _cur = {'rs', 'rupees', 'rupee', 'rupay', 'rupaye', 'rupaya', 'rupiya', 'روپے', 'روپیہ', 'روپیے', 'pkr'};
const Set<String> _hours = {'hour', 'hours', 'hr', 'hrs', 'ghanta', 'ghante', 'ghantay', 'گھنٹے', 'گھنٹہ', 'گھنٹوں'};
const Set<String> _days = {'day', 'days', 'din', 'dino', 'دن', 'دنوں'};
const Set<String> _weeks = {'week', 'weeks', 'hafta', 'hafte', 'ہفتہ', 'ہفتے'};
const Set<String> _per = {'per', 'each', 'har', 'ek', 'fi', 'فی', 'ہر', 'ایک', 'pe', 'prati'};
const Set<String> _ratew = {'rate', 'price', 'ریٹ', 'قیمت'};
const Set<String> _adv = {'advance', 'peshgi', 'پیشگی', 'ایڈوانس'};
const Set<String> _exp = {
  'material', 'materials', 'kharcha', 'kharch', 'kharche', 'expense', 'expenses', 'cost', 'costs',
  'lagat', 'kapra', 'kapray', 'kapre', 'dhaga', 'thread', 'fabric', 'cloth', 'خرچ', 'خرچہ', 'مٹیریل',
  'کپڑا', 'کپڑے', 'دھاگہ', 'لاگت',
};
const Set<String> _items = {
  'dress', 'dresses', 'suit', 'suits', 'frock', 'frocks', 'garment', 'garments', 'piece', 'pieces',
  'pcs', 'pc', 'shirt', 'shirts', 'kurta', 'kurtas', 'shalwar', 'bag', 'bags', 'cap', 'caps',
  'dupatta', 'dupattas', 'scarf', 'scarves', 'item', 'items', 'joray', 'jore', 'jora', 'pair', 'pairs',
  'جوڑے', 'جوڑا', 'سوٹ', 'فراک', 'پیس', 'ڈریس', 'کرتے', 'کرتا', 'شرٹ', 'شرٹس', 'دوپٹے', 'عدد',
};
const Set<String> _generic = {'piece', 'pieces', 'pcs', 'pc', 'item', 'items', 'عدد', 'پیس'};
const Set<String> _qtyw = {'order', 'quantity', 'qty', 'total', 'received', 'got', 'mila', 'mili', 'آرڈر'};

final RegExp _terms = RegExp(
    r'(on delivery|after delivery|on completion|after completion|cash on delivery|weekly|monthly|'
    r'delivery par|delivery ke baad|delivery pe|delivery k baad|ڈیلیوری پر|ڈیلیوری کے بعد|مال دینے پر|ہفتہ وار|ماہانہ)',
    caseSensitive: false);
final RegExp _word = RegExp(r'[A-Za-z0-9_\u0600-\u06FF]+');
final RegExp _nothing = RegExp(r'\b(nothing|none|no cost|koi kharcha nahi|kuch nahi)\b|کچھ نہیں|کوئی خرچ');

List<String> _words(String s) => _word.allMatches(s).map((m) => m.group(0)!).toList();

List<String> _last(List<String> l, int n) => l.length <= n ? l : l.sublist(l.length - n);
List<String> _first(List<String> l, int n) => l.length <= n ? l : l.sublist(0, n);

String? _classify(List<String> before, List<String> after) {
  final a = after.where((w) => !_cur.contains(w)).toList();
  final b = before.where((w) => !_cur.contains(w)).toList();
  final a1 = a.isNotEmpty ? a[0] : '';
  if (_hours.contains(a1)) return 'hours';
  if (_days.contains(a1)) return 'days';
  if (_weeks.contains(a1)) return 'weeks';
  final near = [..._first(a, 3), ..._last(b, 3)];
  if (near.any(_adv.contains)) return 'advance';
  final a2 = _first(a, 2);
  final forEach = a2.length == 2 && a2[0] == 'for' && (a2[1] == 'each' || a2[1] == 'every');
  if (_per.contains(a1) || forEach || (b.isNotEmpty && _ratew.contains(b.last))) return 'rate';
  if (_items.contains(a1)) return 'qty';
  if (near.any(_exp.contains)) return 'expenses';
  if (b.isNotEmpty && _qtyw.contains(b.last)) return 'qty';
  return null;
}

num _asNum(double v) => v == v.truncateToDouble() ? v.toInt() : v;

Map<String, dynamic> extractOffline(String text, [String? askedField]) {
  final t = normalize(text);
  final low = t.toLowerCase();
  final out = <String, dynamic>{};
  final nums = RegExp(r'\d+(?:\.\d+)?').allMatches(low).toList();
  const keyOf = {
    'hours': 'estimated_hours',
    'days': 'deadline_days',
    'weeks': 'deadline_days',
    'advance': 'advance_received',
    'rate': 'rate_per_piece',
    'qty': 'quantity',
    'expenses': 'material_expenses',
  };
  for (final m in nums) {
    final from = m.start - 40 < 0 ? 0 : m.start - 40;
    final to = m.end + 40 > low.length ? low.length : m.end + 40;
    final before = _last(_words(low.substring(from, m.start)), 3);
    final after = _first(_words(low.substring(m.end, to)), 3);
    final role = _classify(before, after);
    var val = _asNum(double.parse(m.group(0)!));
    final key = role == null ? null : keyOf[role];
    if (key == null || out.containsKey(key)) continue;
    if (role == 'weeks') val = (val * 7).truncate();
    out[key] = val;
    if (role == 'qty' && after.isNotEmpty && _items.contains(after[0]) && !_generic.contains(after[0])) {
      out['item'] = after[0];
    }
  }
  // a bare number answers the question we just asked
  if (askedField != null && !out.containsKey(askedField) && nums.length == 1 && out.isEmpty) {
    final v = _asNum(double.parse(nums[0].group(0)!));
    if (askedField != 'payment_terms' && askedField != 'item') out[askedField] = v;
  }
  final tm = _terms.firstMatch(t);
  if (tm != null) {
    out['payment_terms'] = tm.group(0);
  } else if (askedField == 'payment_terms' && t.isNotEmpty) {
    out['payment_terms'] = t.length > 200 ? t.substring(0, 200) : t;
  }
  if (_nothing.hasMatch(low) && askedField == 'material_expenses') {
    out.putIfAbsent('material_expenses', () => 0);
  }
  return out;
}

// ---------------- replies (en / roman / ur) ----------------
const Map<String, Map<String, String>> kQuestions = {
  'quantity': {'en': 'How many pieces is the order?', 'roman': 'Order kitne pieces ka hai?', 'ur': 'آرڈر کتنے پیس کا ہے؟'},
  'rate_per_piece': {
    'en': 'How much will you be paid for each piece (in Rs)?',
    'roman': 'Har piece ke kitne rupay milenge?',
    'ur': 'ہر پیس کے کتنے روپے ملیں گے؟'
  },
  'material_expenses': {
    'en': 'How much will you spend on materials (thread, cloth, etc.)? Say 0 if nothing.',
    'roman': 'Material (dhaga, kapra wagera) par kitna kharcha hoga? Kuch nahi to 0 likhein.',
    'ur': 'مٹیریل (دھاگہ، کپڑا وغیرہ) پر کتنا خرچ ہوگا؟ اگر کچھ نہیں تو 0 لکھیں۔'
  },
  'estimated_hours': {
    'en': 'About how many hours will the whole order take you?',
    'roman': 'Poora order karne mein taqreeban kitne ghante lagenge?',
    'ur': 'پورا آرڈر کرنے میں تقریباً کتنے گھنٹے لگیں گے؟'
  },
  'deadline_days': {
    'en': 'In how many days must you deliver it?',
    'roman': 'Order kitne din mein dena hai?',
    'ur': 'آرڈر کتنے دن میں دینا ہے؟'
  },
  'payment_terms': {
    'en': 'When and how will you be paid? (for example, on delivery)',
    'roman': 'Payment kab aur kaise milegi? (masalan delivery par)',
    'ur': 'ادائیگی کب اور کیسے ہوگی؟ (مثلاً ڈیلیوری پر)'
  },
};
const Map<String, Map<String, String>> _label = {
  'quantity': {'en': 'pieces', 'roman': 'pieces', 'ur': 'پیس'},
  'rate_per_piece': {'en': 'per piece', 'roman': 'per piece', 'ur': 'فی پیس'},
  'material_expenses': {'en': 'materials', 'roman': 'material', 'ur': 'مٹیریل'},
  'estimated_hours': {'en': 'hours', 'roman': 'ghante', 'ur': 'گھنٹے'},
  'deadline_days': {'en': 'days', 'roman': 'din', 'ur': 'دن'},
};
const Map<String, Map<String, String>> _msg = {
  'got': {'en': 'Got it:', 'roman': 'Samajh gayi:', 'ur': 'سمجھ گئی:'},
  'ready': {
    'en': 'I have what I need. Press “Show me the numbers” to see the calculation.',
    'roman': 'Mujhe zaroori maloomat mil gayi hain. “Hisaab dikhayein” dabayein.',
    'ur': 'ضروری معلومات مل گئی ہیں۔ “حساب دکھائیں” دبائیں۔'
  },
  'nothing': {
    'en': 'I could not find order details in that. Tell me the number of pieces and the rate, for example: “30 dresses, Rs 250 each”.',
    'roman': 'Is mein order ki tafseel nahi mili. Pieces aur rate batayein, masalan: “30 dress, 250 per piece”.',
    'ur': 'اس میں آرڈر کی تفصیل نہیں ملی۔ پیس اور ریٹ بتائیں، مثلاً: “30 ڈریس، 250 روپے فی پیس”۔'
  },
  'bad': {'en': 'That number does not look right:', 'roman': 'Yeh number theek nahi lag raha:', 'ur': 'یہ عدد درست نہیں لگ رہا:'},
};

String summarize(Map<String, dynamic> draft, String lang) {
  final parts = <String>[];
  for (final f in ['quantity', 'rate_per_piece', 'material_expenses', 'estimated_hours', 'deadline_days']) {
    final v = draft[f];
    if (v == null) continue;
    final lab = _label[f]![lang]!;
    if (f == 'rate_per_piece' || f == 'material_expenses') {
      parts.add(lang != 'ur' ? 'Rs ${comma0(v as num)} $lab' : '$lab Rs ${comma0(v as num)}');
    } else {
      parts.add('${fmtNum(v as num)} $lab');
    }
  }
  if (draft['payment_terms'] != null && draft['payment_terms'].toString().isNotEmpty) {
    parts.add(draft['payment_terms'].toString());
  }
  return parts.join(lang == 'ur' ? '، ' : ', ');
}

String replyOffline(Map<String, dynamic> draft, List<String> updated, Map<String, String> errors,
    String? nextQ, String lang, bool canCalc) {
  final l = (lang == 'en' || lang == 'roman' || lang == 'ur') ? lang : 'en';
  final lines = <String>[];
  if (errors.isNotEmpty) lines.add('${_msg['bad']![l]} ${errors.keys.join(', ')}');
  if (updated.isNotEmpty) {
    lines.add('${_msg['got']![l]} ${summarize(draft, l)}');
  } else if (errors.isEmpty && draft['quantity'] == null && draft['rate_per_piece'] == null) {
    lines.add(_msg['nothing']![l]!);
  }
  if (nextQ != null) {
    lines.add(kQuestions[nextQ]![l]!);
  } else if (canCalc) {
    lines.add(_msg['ready']![l]!);
  }
  return lines.join('\n\n');
}

bool hasMissingRequired(Map<String, dynamic> d) => missingRequired(d).isNotEmpty;

"""Generates lib/l10n/strings.dart from the Streamlit app's i18n.py (single source of truth) + mobile-only strings.
Run from the repo root:  python mobile/tools/gen_strings.py"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, ROOT)
import i18n  # noqa: E402

EXTRA = {
 "app_name": ("Amana", "امانہ"),
 "settings": ("Settings", "سیٹنگز"),
 "server": ("Server address", "سرور کا پتہ"),
 "server_hint": ("Example: https://your-space.hf.space or http://192.168.1.5:8000", "مثال: https://your-space.hf.space یا http://192.168.1.5:8000"),
 "test_conn": ("Test connection", "کنکشن چیک کریں"), "save": ("Save", "محفوظ کریں"),
 "conn_ok": ("Connected. AI mode: {m}", "کنکشن ٹھیک ہے۔ AI موڈ: {m}"),
 "language": ("Language", "زبان"), "ai_view": ("AI view", "AI ویو"),
 "ai_calls": ("AI calls", "AI کالز"), "code_calls": ("Code steps", "کوڈ کے مراحل"), "checks": ("Checks", "چیکس"),
 "who_title": ("Who does what", "کون کیا کرتا ہے"),
 "who_ai": ("AI understands her words and writes the wording.", "AI اس کی بات سمجھتی ہے اور الفاظ لکھتی ہے۔"),
 "who_code": ("Code does every calculation and every record.", "کوڈ ہر حساب اور ہر ریکارڈ کرتا ہے۔"),
 "who_human": ("She confirms. Nothing is saved or sent without her.", "تصدیق وہ کرتی ہے۔ اس کے بغیر کچھ محفوظ یا ارسال نہیں ہوتا۔"),
 "retry": ("Try again", "دوبارہ کوشش کریں"),
 "waking": ("Waking up the server. This can take up to a minute.", "سرور جاگ رہا ہے۔ ایک منٹ تک لگ سکتا ہے۔"),
 "conn_fail": ("Can't reach the server.", "سرور تک رسائی نہیں ہو سکی۔"),
 "change_server": ("Change server", "سرور بدلیں"),
 "tap_mic": ("Tap to speak", "بولنے کے لیے دبائیں"),
 "recording": ("Listening. Tap to stop.", "سن رہی ہوں۔ رکنے کے لیے دبائیں۔"),
 "transcribing": ("Understanding your voice…", "آواز سمجھ رہی ہوں…"),
 "heard": ("Check what I heard, then press send.", "جو سنا اسے دیکھ لیں، پھر بھیجیں۔"),
 "mic_denied": ("Microphone permission is needed to speak.", "بولنے کے لیے مائیک کی اجازت چاہیے۔"),
 "voice_lang": ("I will speak in", "میں بولوں گی"),
 "send": ("Send", "بھیجیں"), "asking_now": ("asking now", "پوچھ رہی ہوں"),
 "pick_photo": ("Choose photo", "تصویر چنیں"), "take_photo": ("Take photo", "تصویر لیں"),
 "photo_added": ("Photo added", "تصویر شامل ہو گئی"), "remove": ("Remove", "ہٹائیں"),
 "copy": ("Copy", "کاپی"), "copied": ("Copied", "کاپی ہو گیا"),
 "copy_summary": ("Copy summary", "خلاصہ کاپی کریں"),
 "demo_tools": ("Demo tools (for judges)", "ڈیمو ٹولز (ججز کے لیے)"),
 "delete_confirm": ("Delete all your orders, payments and messages? This cannot be undone.", "اپنے تمام آرڈر، ادائیگیاں اور پیغام مٹا دیں؟ یہ واپس نہیں ہو سکتا۔"),
 "cancel": ("Cancel", "منسوخ"), "delete": ("Delete", "مٹائیں"), "ok": ("OK", "ٹھیک ہے"),
 "details": ("Details", "تفصیل"), "enter_number": ("Enter a number", "عدد لکھیں"),
 "pin_set_title": ("Set a 4-digit PIN", "4 ہندسوں کا PIN لگائیں"),
 "pin_off_title": ("Enter your PIN to turn safe mode off", "محفوظ موڈ بند کرنے کے لیے PIN لکھیں"),
 "offline_banner": ("Offline mode: simple rules are used instead of the AI model.", "آف لائن موڈ: AI ماڈل کے بجائے سادہ اصول استعمال ہو رہے ہیں۔"),
 "err_timeout": ("The server is slow or asleep. Please try again.", "سرور سست یا سویا ہوا ہے۔ دوبارہ کوشش کریں۔"),
 "err_network": ("No connection to the server. Check the internet and the server address.", "سرور سے رابطہ نہیں۔ انٹرنیٹ اور سرور کا پتہ دیکھیں۔"),
 "err_generic": ("Something went wrong. Please try again.", "کچھ غلط ہو گیا۔ دوبارہ کوشش کریں۔"),
 "locked_msg": ("Locked. Enter your PIN.", "لاک ہے۔ اپنا PIN لکھیں۔"),
 "orders_word": ("orders", "آرڈرز"), "chip_none": ("not told yet", "ابھی نہیں بتایا"),
 "pcs": ("pieces", "پیس"), "per_pc": ("per piece", "فی پیس"),
 "audit_note": ("Every step the agents took in this session.", "اس سیشن میں ایجنٹس کا ہر قدم۔"),
 "no_trace": ("No steps yet. Describe an order first.", "ابھی کوئی قدم نہیں۔ پہلے آرڈر بتائیں۔"),
 "new_session": ("Start a fresh profile on this phone", "اس فون پر نیا پروفائل شروع کریں"),
 "more": ("More", "مزید"),
 "how_it_works": ("How Amana works", "امانہ کیسے کام کرتی ہے"),
 "how_sub": ("See every step the assistant took", "دیکھیں اسسٹنٹ نے ہر قدم کیا کیا"),
 "optional_details": ("More details (optional)", "مزید تفصیل (اختیاری)"),
 "show_details": ("Show details", "تفصیل دیکھیں"),
 "hide_details": ("Hide details", "تفصیل چھپائیں"),
 "voice_unavailable": ("Voice is not available right now. Please type your message.", "آواز ابھی دستیاب نہیں۔ براہِ مہربانی لکھ کر بتائیں۔"),
 "step_of": ("Step {n} of 5", "مرحلہ {n} از 5"),
 "tip_try": ("Try an example", "مثال آزمائیں"),
 "learn_more": ("Why this matters", "یہ کیوں اہم ہے"),
 "lock_now_short": ("Lock now", "ابھی لاک کریں"),
 "about": ("About Amana", "امانہ کے بارے میں"),
 "about_text": ("Amana helps home-based women workers understand an order, keep a trusted record and check their payment.", "امانہ گھر سے کام کرنے والی خواتین کو آرڈر سمجھنے، قابلِ اعتماد ریکارڈ رکھنے اور ادائیگی جانچنے میں مدد دیتی ہے۔"),
 "open_wa": ("Open in WhatsApp", "واٹس ایپ میں کھولیں"),
}

LISTS = dict(i18n.S)
LISTS["limits"] = (
    ["A PIN alone cannot fully protect a shared phone.", "Your phone's own screen lock and updates still matter.",
     "Locking hides records on screen; it is not a replacement for device encryption."],
    ["صرف PIN مشترکہ فون کو مکمل طور پر محفوظ نہیں کر سکتا۔", "فون کا اپنا اسکرین لاک اور اپڈیٹس بھی اہم ہیں۔",
     "لاک اسکرین پر ریکارڈ چھپاتا ہے، یہ فون انکرپشن کا متبادل نہیں۔"])


def dart(s):
    assert "$" not in s, s
    return json.dumps(s, ensure_ascii=False)

out = ["// GENERATED by tools/gen_strings.py from i18n.py. Do not edit by hand; edit i18n.py or EXTRA and re-run.",
       "// ignore_for_file: prefer_single_quotes", "",
       "const Map<String, List<String>> _s = {"]
keys = {}
for k, v in i18n.S.items():
    if isinstance(v[0], str):
        keys[k] = v
keys.update(EXTRA)
for k, (en, ur) in keys.items():
    out.append(f"  {dart(k)}: [{dart(en)}, {dart(ur)}],")
out.append("};\n")
out.append("const Map<String, List<List<String>>> _lists = {")
for k, v in LISTS.items():
    if isinstance(v[0], list):
        out.append(f"  {dart(k)}: [[{', '.join(dart(x) for x in v[0])}], [{', '.join(dart(x) for x in v[1])}]],")
out.append("};\n")
out.append('''/// Translate a UI key. lang is 'en' or 'ur'. Placeholders look like {n}.
String tr(String key, String lang, [Map<String, Object?>? args]) {
  final v = _s[key];
  if (v == null) return key;
  var text = v[lang == 'ur' ? 1 : 0];
  if (args != null) {
    args.forEach((k, val) => text = text.replaceAll('{$k}', '${val ?? ''}'));
  }
  return text;
}

List<String> trList(String key, String lang) {
  final v = _lists[key];
  if (v == null) return const <String>[];
  return v[lang == 'ur' ? 1 : 0];
}
''')
path = os.path.join(HERE, "..", "lib", "l10n", "strings.dart")
open(path, "w", encoding="utf-8").write("\n".join(out))
print("wrote", os.path.abspath(path), len(keys), "strings")

# Amana AI: standalone Android app (no server, no cloud, no Docker)

Everything runs **inside the phone**: the agents, the maths, the hash-chained records, the PIN lock,
the offline Roman-Urdu/Urdu/English parser. Data is one private JSON file on the device.
The only network use is the optional AI call: through your own small proxy (keys hidden), or straight from the phone.

```
Flutter screens ──▶ LocalApi (same routes/JSON as before) ──▶ lib/engine/*  (Dart port of the tested Python)
                                                              ├─ calc.dart      deterministic money maths
                                                              ├─ offline.dart   rule-based parser + replies
                                                              ├─ agents.dart    Orchestrator / Deal / Record / Payment + safety gate
                                                              ├─ records.dart   SHA-256 hash chain, PIN, JSON file storage
                                                              └─ llm.dart       Gemini → Groq → NVIDIA fallback, voice-to-text
```
**Works with no internet and no key** (offline mode). With a key + internet, language understanding and voice improve.

## 1. One-time setup (Flutter installed)
```powershell
# from the repo root
powershell -ExecutionPolicy Bypass -File mobile\setup_flutter.ps1
```
It creates the android folder, adds permissions, sets min SDK 24, then runs `flutter analyze` and `flutter test`.

## 2. Verify the port (important)
```powershell
cd mobile
flutter test
```
`test/golden.json` was produced by the tested Python code. The Dart engine must give the same numbers,
flags and parsed fields, and the journey tests run the whole worker flow offline. If something fails, paste the output.
(Re-generate the golden file any time: `python mobile/tools/gen_golden.py`.)

## 3. Run and build
```powershell
flutter run                                   # phone/emulator, offline mode
flutter build apk --release                   # build\app\outputs\flutter-apk\app-release.apk
```
Give judges the APK file (WhatsApp / USB / Drive). Install with "allow unknown sources".

### Making AI + voice work for every user (developer does this ONCE)
Users never see keys, links or "offline mode". AI is wired in by the developer:
1. Deploy `../ai-proxy` on Vercel (keys stay in Vercel's environment variables, see `ai-proxy/README.md`).
2. Open `lib/app_config.dart` and put your Vercel address in `kAiProxyUrl` (and the same `APP_TOKEN` in `kAiProxyToken`).
3. Build the APK. That is all: install it and AI + voice just work.

If the proxy is unreachable (no internet, quota finished) the app silently continues with its built-in rules, so it never breaks.
Voice needs the proxy; without it the mic politely says "please type your message".

## 4. What each screen does
- **Work:** voice or text chat (Urdu / Roman Urdu / English) → order ticket fills live → *Show me the numbers* → ledger, risk flags, counteroffer → *Confirm* (only then saved) → payment check (optional proof photo) → report + message she approves (WhatsApp opens; nothing is sent automatically).
- **Records:** totals, hash-chain check, per-order integrity badge, demo tools to tamper with a record and watch the check catch it.
- **Safe mode:** 4-digit PIN, auto-lock, lock when the app was in the background too long, 5 wrong tries → 30 s lockout.
- **AI view** (hub icon): every model call and tool call, labelled AI / CODE / CHECK.

## 5. Demo script (2 minutes)
1. Tap the "Roman Urdu" example → ticket fills, Amana asks one question.
2. Answer by voice → check the text → send.
3. *Show me the numbers* → ledger + amber flags → Counteroffer 150/hour.
4. *Confirm* → stamp + fingerprint → Received 6500 → report: Rs 1,000 unexplained.
5. Edit message → Approve → Open in WhatsApp.
6. Records → expand → tamper demo → red badge → *Check all records*.
7. Safe mode → set PIN → Lock now → wrong PIN.

## 6. Honest limits
- The PIN protects against a casual user of a shared phone. The data file is not encrypted.
- A chat in progress is kept in memory: closing the app starts a fresh chat (saved records stay).
- The hash chain detects changes after saving; it does not prove the original information was true.
- Voice needs internet and a Groq or Gemini key. Everything else works offline.
- The Dart code has not been compiled by its author here: `flutter analyze` + `flutter test` are the first things to run.

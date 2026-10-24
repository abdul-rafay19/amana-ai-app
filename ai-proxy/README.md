# Amana AI proxy (Vercel)

A 150-line server that holds your AI keys so they are **never inside the APK or the GitHub repo**.
The app talks to it only for AI wording and voice. Everything else (maths, records, PIN) stays on the phone.
If this proxy is down, asleep or out of quota, the app automatically falls back to offline mode, so it never breaks.

| Endpoint | Purpose |
|---|---|
| `POST /api/chat` | forwards the chat to Gemini, then Groq, then NVIDIA (first that works). Client cannot choose the model. |
| `POST /api/stt`  | voice to text (Groq Whisper, Gemini as backup) |
| `GET  /api/health` | shows which providers are configured (never the keys) |

## Deploy (free, about 5 minutes, no Docker)
1. Put this `ai-proxy/` folder in your GitHub repo. The repo can be PUBLIC: there are no secrets in it.
2. vercel.com → **Add New → Project** → import the repo → **Root Directory = `ai-proxy`** → Framework: *Other* → Deploy.
3. Project → **Settings → Environment Variables**, add (Production):
   - `GEMINI_API_KEY`, `GROQ_API_KEY`, `NVIDIA_API_KEY` (at least one; Groq also enables voice)
   - `APP_TOKEN` = any long random text (optional but recommended)
4. **Redeploy** once so the variables apply. Open `https://<name>.vercel.app/api/health`: it should show your providers.
5. Build the app with the link:
   ```
   flutter build apk --release --dart-define=AI_PROXY_URL=https://<name>.vercel.app --dart-define=AI_PROXY_TOKEN=<same APP_TOKEN>
   ```

Test the code locally without any key: `node test.js`.

## For anyone reusing the project
Fork the repo, deploy your own proxy with your own keys, build the APK with your own link. Nobody shares your quota.
`APP_TOKEN` is not a provider key: it only stops strangers from casually using your proxy. If someone abuses it, change the
value in Vercel and rebuild; the provider keys were never exposed.

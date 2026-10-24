const { PROVIDERS, authorized, limited, readBody, cors } = require('./_lib');

// POST /api/stt   raw audio bytes as the body.
// Headers: content-type = audio mime, x-filename, x-language (ur|en).  Returns { text }.
module.exports = async (req, res) => {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!authorized(req)) return res.status(401).json({ error: 'unauthorized' });
  if (limited(req, 15)) return res.status(429).json({ error: 'slow down' });

  let audio;
  try {
    audio = await readBody(req, 4 * 1024 * 1024);
  } catch (e) {
    return res.status(e.status || 400).json({ error: 'bad request' });
  }
  if (!audio.length) return res.status(400).json({ error: 'empty audio' });

  const mime = String(req.headers['content-type'] || 'audio/wav').split(';')[0];
  const filename = String(req.headers['x-filename'] || 'voice.wav').replace(/[^\w.\-]/g, '_');
  const hint = req.headers['x-language'];
  const language = hint === 'ur' || hint === 'en' ? hint : null; // null = let the model detect
  const errors = [];

  if (process.env.GROQ_API_KEY) {
    try {
      const form = new FormData();
      form.append('file', new Blob([audio], { type: mime }), filename);
      form.append('model', 'whisper-large-v3');
      if (language) form.append('language', language);
      if (language !== 'ur') form.append('prompt', 'Pakistani speaker. Urdu, Roman Urdu or English. Piecework order, rate per piece, rupees.');
      form.append('response_format', 'json');
      form.append('temperature', '0');
      const r = await fetch(`${PROVIDERS.groq.base}/audio/transcriptions`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${process.env.GROQ_API_KEY}` },
        body: form,
        signal: AbortSignal.timeout(40000),
      });
      if (r.ok) return res.status(200).json({ text: String((await r.json()).text || '').trim(), provider: 'groq' });
      errors.push(`groq: HTTP ${r.status}`);
    } catch (e) {
      errors.push(`groq: ${e.name}`);
    }
  }

  if (process.env.GEMINI_API_KEY) {
    try {
      const r = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${PROVIDERS.gemini.model}:generateContent`,
        {
          method: 'POST',
          headers: { 'x-goog-api-key': process.env.GEMINI_API_KEY, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ role: 'user', parts: [
              { inlineData: { mimeType: mime, data: audio.toString('base64') } },
              { text: 'Transcribe this audio exactly. Write Urdu in Urdu script. Output only the transcript.' },
            ] }],
            generationConfig: { temperature: 0 },
          }),
          signal: AbortSignal.timeout(40000),
        });
      if (r.ok) {
        const j = await r.json();
        const text = (j.candidates?.[0]?.content?.parts || []).map((p) => p.text || '').join('').trim();
        return res.status(200).json({ text, provider: 'gemini' });
      }
      errors.push(`gemini: HTTP ${r.status}`);
    } catch (e) {
      errors.push(`gemini: ${e.name}`);
    }
  }
  return res.status(502).json({ error: 'transcription failed', detail: errors.join('; ') || 'no provider configured' });
};

// raw audio is read from the stream, so Vercel must not parse the body
module.exports.config = { api: { bodyParser: false } };

const { PROVIDERS, order, authorized, limited, readBody, cors } = require('./_lib');

const RETRY = new Set([429, 500, 502, 503, 504]);

// POST /api/chat   body: { messages, tools?, temperature?, max_tokens?, response_format? }
// Returns the provider's OpenAI-style JSON plus { _amana: { provider, model } }.
// The client can NOT choose the model or the provider: that is decided here.
module.exports = async (req, res) => {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!authorized(req)) return res.status(401).json({ error: 'unauthorized' });
  if (limited(req)) return res.status(429).json({ error: 'slow down' });

  let body;
  try {
    body = JSON.parse((await readBody(req, 200 * 1024)).toString('utf8'));
  } catch (e) {
    return res.status(e.status || 400).json({ error: 'bad request' });
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0 || body.messages.length > 40) {
    return res.status(400).json({ error: 'messages required (max 40)' });
  }

  const provs = order();
  if (!provs.length) return res.status(503).json({ error: 'no provider configured' });

  let last = 'none';
  for (const p of provs) {
    const cfg = PROVIDERS[p];
    const payload = {
      model: cfg.model,
      messages: body.messages,
      temperature: typeof body.temperature === 'number' ? body.temperature : 0.2,
      max_tokens: Math.min(Number(body.max_tokens) || 900, 1200),
    };
    if (Array.isArray(body.tools) && body.tools.length) {
      payload.tools = body.tools;
      payload.tool_choice = 'auto';
    } else if (body.response_format) {
      payload.response_format = body.response_format;
    }
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const r = await fetch(`${cfg.base}/chat/completions`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${process.env[cfg.env]}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(25000),
        });
        if (RETRY.has(r.status)) {
          last = `${p}: HTTP ${r.status}`;
          await new Promise((ok) => setTimeout(ok, 800 * (attempt + 1)));
          continue;
        }
        if (!r.ok) { last = `${p}: HTTP ${r.status}`; break; }
        const j = await r.json();
        j._amana = { provider: p, model: cfg.model };
        return res.status(200).json(j);
      } catch (e) {
        last = `${p}: ${e.name}`;
        break;
      }
    }
  }
  return res.status(502).json({ error: 'all providers failed', detail: last });
};

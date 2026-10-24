// Shared helpers for the Amana AI proxy (Vercel serverless functions, Node 18+).
// Keys live ONLY in Vercel environment variables. Nothing here is secret, so this repo can be public.

const PROVIDERS = {
  gemini: { base: 'https://generativelanguage.googleapis.com/v1beta/openai', model: 'gemini-flash-lite-latest', env: 'GEMINI_API_KEY' },
  groq: { base: 'https://api.groq.com/openai/v1', model: 'openai/gpt-oss-120b', env: 'GROQ_API_KEY' },
  nvidia: { base: 'https://integrate.api.nvidia.com/v1', model: 'meta/llama-3.3-70b-instruct', env: 'NVIDIA_API_KEY' },
};

function order() {
  return (process.env.PROVIDER_ORDER || 'gemini,groq,nvidia')
    .split(',').map((s) => s.trim()).filter((p) => PROVIDERS[p] && process.env[PROVIDERS[p].env]);
}

// Optional shared token: stops random scanners from using your quota. It is NOT a provider key.
function authorized(req) {
  const t = process.env.APP_TOKEN;
  return !t || req.headers['x-app-token'] === t;
}

// Best-effort per-IP limit (serverless instances are short-lived, so this only blunts bursts).
const hits = new Map();
function limited(req, max = 30, windowMs = 60000) {
  const ip = String(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '?').split(',')[0].trim();
  const now = Date.now();
  const arr = (hits.get(ip) || []).filter((t) => now - t < windowMs);
  if (arr.length >= max) return true;
  arr.push(now);
  hits.set(ip, arr);
  if (hits.size > 5000) hits.clear();
  return false;
}

async function readBody(req, maxBytes) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > maxBytes) throw Object.assign(new Error('too large'), { status: 413 });
    chunks.push(c);
  }
  return Buffer.concat(chunks);
}

// CORS: lets the web preview (Chrome) call the proxy. The phone app does not need it.
function cors(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type, x-app-token, x-filename, x-language');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  if (req.method === 'OPTIONS') { res.status(204).end(); return true; }
  return false;
}

module.exports = { PROVIDERS, order, authorized, limited, readBody, cors };

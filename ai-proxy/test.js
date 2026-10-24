// node test.js  : runs the handlers with fake req/res and a stubbed fetch (no network, no keys needed)
process.env.GEMINI_API_KEY = 'g'; process.env.GROQ_API_KEY = 'q'; process.env.APP_TOKEN = 'tok';
const assert = require('assert');
const { Readable } = require('stream');
const chat = require('./api/chat'), stt = require('./api/stt'), health = require('./api/health');

function mk(method, headers, body) {
  const req = Readable.from(body ? [Buffer.from(body)] : []);
  Object.assign(req, { method, headers: { 'x-forwarded-for': '1.1.1.' + Math.floor(Math.random() * 250), ...headers }, socket: {} });
  const out = {};
  out.headers = {};
  const res = { setHeader(k, v) { out.headers[k] = v; }, end() { out.ended = true; return res; }, status(c) { out.code = c; return res; }, json(j) { out.json = j; return res; } };
  return { req, res, out };
}
const calls = [];
function stub(handler) { global.fetch = async (url, opt) => { calls.push({ url, opt }); return handler(url, opt); }; }
const ok = (j) => ({ ok: true, status: 200, json: async () => j });
const bad = (s) => ({ ok: false, status: s, json: async () => ({}) });

(async () => {
  // CORS preflight (web preview)
  let pf = mk('OPTIONS', {}); await chat(pf.req, pf.res); assert.equal(pf.out.code, 204); assert.equal(pf.out.headers['Access-Control-Allow-Origin'], '*');
  // auth + method
  let t = mk('GET', {}); await chat(t.req, t.res); assert.equal(t.out.code, 405);
  t = mk('POST', {}, '{}'); await chat(t.req, t.res); assert.equal(t.out.code, 401);
  t = mk('POST', { 'x-app-token': 'tok' }, '{"messages":[]}'); await chat(t.req, t.res); assert.equal(t.out.code, 400);

  // happy path: gemini answers, client cannot pick the model, max_tokens capped
  stub(() => ok({ choices: [{ message: { content: 'hi' } }] }));
  t = mk('POST', { 'x-app-token': 'tok' }, JSON.stringify({ model: 'evil', max_tokens: 99999, messages: [{ role: 'user', content: 'x' }] }));
  await chat(t.req, t.res);
  assert.equal(t.out.code, 200); assert.equal(t.out.json._amana.provider, 'gemini');
  const sent = JSON.parse(calls.at(-1).opt.body);
  assert.equal(sent.model, 'gemini-flash-lite-latest'); assert.equal(sent.max_tokens, 1200);
  assert.ok(calls.at(-1).url.startsWith('https://generativelanguage'));
  assert.equal(calls.at(-1).opt.headers.Authorization, 'Bearer g');

  // fallback: gemini 400 -> groq answers
  calls.length = 0;
  stub((u) => (u.includes('generativelanguage') ? bad(400) : ok({ choices: [{ message: { content: 'from groq' } }] })));
  t = mk('POST', { 'x-app-token': 'tok' }, JSON.stringify({ messages: [{ role: 'user', content: 'x' }] }));
  await chat(t.req, t.res);
  assert.equal(t.out.json._amana.provider, 'groq');

  // everything down -> 502 (the app then falls back to offline mode)
  stub(() => bad(500));
  t = mk('POST', { 'x-app-token': 'tok' }, JSON.stringify({ messages: [{ role: 'user', content: 'x' }] }));
  await chat(t.req, t.res);
  assert.equal(t.out.code, 502);

  // stt via groq
  stub((u, o) => { assert.ok(u.includes('audio/transcriptions')); return ok({ text: ' salam ' }); });
  t = mk('POST', { 'x-app-token': 'tok', 'content-type': 'audio/wav', 'x-language': 'ur' }, 'RIFFxxxxxxxx');
  await stt(t.req, t.res);
  assert.equal(t.out.code, 200); assert.equal(t.out.json.text, 'salam');

  // stt falls back to gemini
  stub((u) => (u.includes('groq') ? bad(500) : ok({ candidates: [{ content: { parts: [{ text: 'aoa' }] } }] })));
  t = mk('POST', { 'x-app-token': 'tok', 'content-type': 'audio/wav' }, 'RIFFxxxxxxxx');
  await stt(t.req, t.res);
  assert.equal(t.out.json.provider, 'gemini');

  // health never leaks keys
  t = mk('GET', {}); health(t.req, t.res);
  assert.deepEqual(Object.keys(t.out.json).sort(), ['ai', 'ok', 'providers', 'token_required', 'voice']);
  assert.ok(!JSON.stringify(t.out.json).includes('"g"'));

  // rate limit
  stub(() => ok({ choices: [{ message: { content: 'x' } }] }));
  const hdr = { 'x-app-token': 'tok', 'x-forwarded-for': '9.9.9.9' };
  let last;
  for (let i = 0; i < 32; i++) { t = mk('POST', hdr, JSON.stringify({ messages: [{ role: 'user', content: 'x' }] })); t.req.headers['x-forwarded-for'] = '9.9.9.9'; await chat(t.req, t.res); last = t.out.code; }
  assert.equal(last, 429);
  console.log('proxy tests: all passed');
})().catch((e) => { console.error(e); process.exit(1); });

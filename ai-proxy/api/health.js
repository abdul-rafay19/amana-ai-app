const { order, cors } = require('./_lib');
// GET /api/health -> which providers are configured (never the keys).
module.exports = (req, res) => {
  if (cors(req, res)) return;
  const p = order();
  res.status(200).json({
    ok: true,
    ai: p.length > 0,
    providers: p,
    voice: Boolean(process.env.GROQ_API_KEY || process.env.GEMINI_API_KEY),
    token_required: Boolean(process.env.APP_TOKEN),
  });
};

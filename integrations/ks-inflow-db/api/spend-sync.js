// 퍼포먼스 DB 로 광고비 수동 동기화(과거 기간 채우기) — POST { since:'YYYY-MM-DD', until:'YYYY-MM-DD' } (최대 93일)
// 오류는 원인 메시지를 그대로 돌려줍니다 (로그인한 사용자만 호출 가능)
const wrap = require('./_util');
const A = require('../lib/auth');

module.exports = wrap(async (req, res) => {
  const s = A.requireSession(req, res); if (!s) return;
  let sync;
  try { sync = require('../lib/spend_sync'); }
  catch (e) { return res.status(500).json({ error: 'lib/spend_sync.js 를 불러오지 못했습니다: ' + e.message }); }
  if (req.method === 'GET') return res.json({ enabled: sync.enabled(), channels: sync.CHANNEL_MAP });
  if (req.method !== 'POST') return res.status(405).json({ error: '허용되지 않은 요청입니다.' });
  if (!sync.enabled()) return res.status(400).json({ error: '퍼포먼스 DB 연동이 설정되지 않았습니다 (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 환경 변수 → 재배포).' });
  const b = req.body || {};
  const since = String(b.since || ''), until = String(b.until || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(since) || !/^\d{4}-\d{2}-\d{2}$/.test(until) || since > until) return res.status(400).json({ error: '기간이 올바르지 않습니다.' });
  if ((new Date(until) - new Date(since)) / 864e5 > 92) return res.status(400).json({ error: '한 번에 93일까지만 보낼 수 있습니다.' });
  try {
    const r = await sync.sync({ since, until });
    res.json({ ok: true, ...r });
  } catch (e) {
    console.error('[spend-sync]', e);
    res.status(500).json({ error: e.message || String(e), step: e.step || '' });
  }
});

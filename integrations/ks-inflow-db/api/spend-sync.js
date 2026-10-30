// 퍼포먼스 DB 로 광고비 동기화 — POST { since:'YYYY-MM-DD', until:'YYYY-MM-DD' } (최대 93일)
// 인증 두 가지 중 하나:
//   1) 원장 로그인 세션 (이 사이트 콘솔·화면에서 호출)
//   2) 헤더 x-sync-token == 환경 변수 SPEND_SYNC_TOKEN (퍼포먼스 DB 화면의 [지금 가져오기] 버튼이 사용)
// CORS: 환경 변수 SPEND_SYNC_ORIGIN (기본 https://jisooh-ai.github.io) 에서 오는 요청만 허용
// 오류는 원인 메시지를 그대로 돌려줍니다.
const wrap = require('./_util');
const A = require('../lib/auth');

const ORIGIN = String(process.env.SPEND_SYNC_ORIGIN || 'https://jisooh-ai.github.io').trim();
function cors(req, res) {
  const o = String(req.headers.origin || '');
  if (o && o === ORIGIN) {
    res.setHeader('Access-Control-Allow-Origin', o);
    res.setHeader('Access-Control-Allow-Headers', 'content-type, x-sync-token');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Max-Age', '600');
  }
}
function tokenOk(req) {
  const t = String(process.env.SPEND_SYNC_TOKEN || '').trim();
  return !!t && String(req.headers['x-sync-token'] || '') === t;
}

module.exports = wrap(async (req, res) => {
  cors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (!tokenOk(req)) { const s = A.requireSession(req, res); if (!s) return; }
  let sync;
  try { sync = require('../lib/spend_sync'); }
  catch (e) { return res.status(500).json({ error: 'lib/spend_sync.js 를 불러오지 못했습니다: ' + e.message }); }
  if (req.method === 'GET') {
    const q = req.query || {};
    if (q.action === 'unassigned') {
      const since = String(q.since || ''), until = String(q.until || '');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(since) || !/^\d{4}-\d{2}-\d{2}$/.test(until) || since > until) return res.status(400).json({ error: '기간이 올바르지 않습니다.' });
      if ((new Date(until) - new Date(since)) / 864e5 > 92) return res.status(400).json({ error: '한 번에 93일까지만 조회할 수 있습니다.' });
      try { return res.json({ ok: true, since, until, rows: await sync.unassigned({ since, until }) }); }
      catch (e) { return res.status(500).json({ error: e.message || String(e) }); }
    }
    return res.json({ enabled: sync.enabled(), channels: sync.CHANNEL_MAP });
  }
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
    res.status(500).json({ error: e.message || String(e) });
  }
}, { skipIp: true });   // 토큰 또는 로그인 세션으로 보호 (퍼포먼스 DB 화면은 사무실 밖에서도 쓰므로 IP 제한 제외)

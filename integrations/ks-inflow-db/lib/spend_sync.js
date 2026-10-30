// 광고비 원장(광고비_YYYY-MM 탭) → 마케팅 퍼포먼스 DB(Supabase ad_spend) 동기화
//
// 필요한 설정 (Vercel → Settings → Environment Variables) — os_sync.js 와 같은 값을 그대로 씁니다
//   SUPABASE_URL              : https://qhlygfqetcfnoialihyc.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY : Supabase 비밀 키 (service_role)  ※ 절대 index.html 등 화면 코드에 넣지 않음
//   SPEND_SYNC                : 'off' 로 두면 동기화를 건너뜀 (기본: 켜짐)
//
// 동작
//   - 원장의 한 달 행(캠페인×일자)을 compute.js 의 resolveCost 로 브랜드·매체 구분을 판정한 뒤
//     일자 × 브랜드 × 채널로 합쳐 퍼포먼스 DB 의 채널 이름(12종)으로 바꿔 보냅니다.
//   - 제외 규칙(직원채용 등)에 걸린 행은 보내지 않습니다. '브랜드 미지정' 은 '(브랜드 없음)' 으로 보냅니다.
//   - 메타·구글·블로그 인플루언서는 대행 수수료 15% 행을 함께 만듭니다 (퍼포먼스 DB 월별 양식과 같은 규칙).
//   - 보내는 날짜 범위 안에서 같은 일자·브랜드·채널 행은 덮어씁니다 (여러 번 보내도 중복 없음).
//   - 실패해도 원장 저장·수집은 정상 처리됩니다 (cron 응답과 Mattermost 에 실패 내용만 남김).
const C = require('../public/compute.js');
const costs = require('./costs');

const TIMEOUT_MS = 25000;
const CHUNK = 2000;
const FEE_RATE = 0.15;

// 원장 '매체 구분' → 퍼포먼스 DB 채널. 빈 문자열이면 보내지 않음(엔카 세부처럼 광고비가 아닌 구분).
const CHANNEL_MAP = {
  '네이버': '네이버 파워링크',
  'GFA': '네이버 GFA',
  '다음': '카카오 키워드 광고',
  '모먼트': '카카오 모먼트',
  '친구톡': '카카오 친구톡',
  '구글(검색)': '구글 애즈',
  '구글(배너)': '구글 애즈',
  '구글(디멘드젠)': '구글 애즈',
  '메타': '메타 광고',
  '틱톡': '틱톡 광고',
  '당근': '당근 광고',
  '블로그인플': '블로그 인플루언서',
  '유튜브PPL': '유튜브 PPL',
  '엔카(nativead)': '기타',
  '엔카(photoview)': '기타',
  '기타': '기타',
};
const FEE_OF = { '구글 애즈': '구글 애즈 수수료', '메타 광고': '메타 광고 수수료', '블로그 인플루언서': '블로그 인플루언서 수수료' };
const UNBRANDED = '(브랜드 없음)';

function config() {
  if (String(process.env.SPEND_SYNC || '').trim().toLowerCase() === 'off') return null;
  const url = String(process.env.SUPABASE_URL || '').trim();
  const key = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
  if (!url || !key) return null;
  try { return { base: new URL(url).origin + '/rest/v1', key }; } catch { return null; }
}
const enabled = () => !!config();

async function rpc(cfg, fn, body) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(`${cfg.base}/rpc/${fn}`, {
      method: 'POST', signal: ctl.signal, redirect: 'manual',
      headers: { apikey: cfg.key, authorization: 'Bearer ' + cfg.key, 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    const text = await r.text();
    if (!r.ok) { let msg = text.slice(0, 200); try { const j = JSON.parse(text); msg = j.message || j.error || msg; } catch { /* 그대로 */ } throw new Error(`퍼포먼스 DB 저장 실패 (${r.status}): ${msg}`); }
    return text ? JSON.parse(text) : null;
  } catch (e) {
    if (e.name === 'AbortError') throw new Error('퍼포먼스 DB 응답이 없습니다 (시간 초과)');
    throw e;
  } finally { clearTimeout(timer); }
}

/** 원장 행 → ad_spend 행 (일자×브랜드×채널 합산 + 수수료 행) */
function toSpendRows(rows, cfg, since, until) {
  const agg = new Map();
  const add = (d, b, ch, v) => { const k = `${d}|${b}|${ch}`; agg.set(k, (agg.get(k) || 0) + v); };
  for (const r of rows) {
    if (!r.date || r.date < since || r.date > until) continue;
    const v = Number(r.cost) || 0; if (!v) continue;
    const z = C.resolveCost(r, cfg);
    if (z.excluded) continue;
    const ch = CHANNEL_MAP[z.bucket]; if (!ch) continue;
    const brand = (!z.brand || z.brand === C.UNASSIGNED) ? UNBRANDED : z.brand;
    add(r.date, brand, ch, v);
  }
  const out = [];
  for (const [k, v] of agg) {
    const [spend_date, brand, channel] = k.split('|');
    out.push({ spend_date, brand, channel, cost: Math.round(v) });
    if (FEE_OF[channel]) out.push({ spend_date, brand, channel: FEE_OF[channel], cost: Math.round(v * FEE_RATE) });
  }
  return out.sort((a, b) => a.spend_date.localeCompare(b.spend_date) || a.brand.localeCompare(b.brand) || a.channel.localeCompare(b.channel));
}

/** since~until 기간의 원장을 읽어 퍼포먼스 DB 로 보냄. 결과: { sent, months, skipped } */
async function sync({ since, until }) {
  const cfg0 = config();
  if (!cfg0) return { skipped: '설정 없음(SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)' };
  const cfg = C.cleanCostCfg(await costs.config());
  const months = new Set();
  for (let d = new Date(since + 'T00:00:00Z'); d <= new Date(until + 'T00:00:00Z'); d.setUTCMonth(d.getUTCMonth() + 1, 1)) months.add(d.toISOString().slice(0, 7));
  months.add(until.slice(0, 7));
  let rows = [];
  for (const m of months) rows = rows.concat(await costs.readMonth(m));
  const spend = toSpendRows(rows, cfg, since, until);
  let sent = 0;
  for (let i = 0; i < spend.length; i += CHUNK) {
    const r = await rpc(cfg0, 'fn_spend_upsert_api', { rows: spend.slice(i, i + CHUNK), p_source: 'api' });
    sent += Number((r && r.rows) || 0);
  }
  return { sent, rows: spend.length, months: [...months].sort(), since, until };
}

module.exports = { enabled, sync, toSpendRows, CHANNEL_MAP };

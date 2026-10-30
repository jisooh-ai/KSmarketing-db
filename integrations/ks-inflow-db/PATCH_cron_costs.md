# 기존 파일 수정 (2곳)

## api/cron.js — 자동 수집 뒤에 퍼포먼스 DB 동기화 추가
`const store = require('../lib/store');` 아래에 한 줄 추가:
```js
const spendSync = require('../lib/spend_sync');
```
`for (const m of r.months) ...writeSummary...` 줄 **다음**에 추가:
```js
  // 퍼포먼스 DB(ad_spend) 동기화 — 실패해도 수집 결과는 그대로
  let os = null;
  if (spendSync.enabled()) { try { os = await spendSync.sync({ since: r.since, until: r.until }); } catch (e) { os = { error: e.message }; } }
```
Mattermost 알림 블록의 `if (hook && bad.length)` 를 아래처럼 바꿔 동기화 실패도 알림:
```js
  const osBad = os && os.error ? `\n- 퍼포먼스 DB 동기화 실패: ${os.error}` : '';
  if (hook && (bad.length || osBad)) {
    const text = `#### 광고비 자동 수집 ${bad.length ? `실패 ${bad.length}건` : '완료'} (${r.since} ~ ${r.until})\n` + bad.map((a) => `- ${a.platform} ${a.account} (${a.brand || '브랜드 미지정'}): ${a.error}`).join('\n') + osBad;
```
마지막 `res.json({ ok: true, ...r });` → `res.json({ ok: true, ...r, spendSync: os });`

## api/costs.js — 수동 수집·업로드·보고서 저장 뒤에도 동기화
`const store = require('../lib/store');` 아래에:
```js
const spendSync = require('../lib/spend_sync');
```
`for (const m of r.months) ...writeSummary...` 줄 **다음**, `return res.json(...)` **앞**에:
```js
    let os = null;
    if (spendSync.enabled() && r.since && r.until) { try { os = await spendSync.sync({ since: r.since, until: r.until }); } catch (e) { os = { error: e.message }; } }
    else if (spendSync.enabled() && r.months && r.months.length) {   // 업로드·보고서: 해당 월 전체
      try { const m0 = r.months[0], m1 = r.months[r.months.length - 1]; const last = new Date(+m1.slice(0, 4), +m1.slice(5, 7), 0).toISOString().slice(0, 10);
            os = await spendSync.sync({ since: m0 + '-01', until: last }); } catch (e) { os = { error: e.message }; }
    }
```
그리고 `return res.json({ ok: true, ...r });` → `return res.json({ ok: true, ...r, spendSync: os });`

## 새 파일
- `lib/spend_sync.js` (동기화 모듈)
- `api/spend-sync.js` (과거 기간 수동 보내기: 로그인 상태에서 POST {since, until})

## Vercel 환경 변수
- `SPEND_SYNC_TOKEN` = 임의의 긴 비밀 문자열 (퍼포먼스 DB 화면 [지금 가져오기] 버튼용 — 같은 값을 그 화면 토큰 칸에 입력)
- `SPEND_SYNC_ORIGIN` = https://jisooh-ai.github.io (기본값이므로 생략 가능)
- `SUPABASE_URL` = https://qhlygfqetcfnoialihyc.supabase.co  (os_sync 와 같은 변수라면 이미 있음)
- `SUPABASE_SERVICE_ROLE_KEY` = Supabase → Settings → API → service_role (secret)
- (선택) `SPEND_SYNC=off` → 잠시 끄기

## 과거 데이터 한 번에 채우기 (배포 후, 브라우저 콘솔 또는 curl — 로그인 쿠키 필요)
```js
for (const [s,u] of [['2026-01-01','2026-03-31'],['2026-04-01','2026-06-30'],['2026-07-01','2026-09-30'],['2026-10-01','2026-10-31']])
  console.log(await (await fetch('/api/spend-sync',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({since:s,until:u})})).json());
```

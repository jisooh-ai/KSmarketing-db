# KS오토플랜 마케팅 퍼포먼스 DB — 작업 지침 (인수인계용)

엑셀 수작업 ROAS 시트를 대체하는 사내 도구. **Supabase(Postgres) + 단일 HTML(GitHub Pages)**.
운영 주소: https://jisooh-ai.github.io/KSmarketing-db/ · Supabase 프로젝트 ref `qhlygfqetcfnoialihyc`
사용자: 마케팅팀(비개발자). 대표·임원 보고에 쓰이므로 **숫자 정의가 바뀌면 반드시 사용자에게 먼저 확인**.

## 파일 구조
| 경로 | 역할 |
|---|---|
| `index.html` | 앱 전체(HTML+CSS+JS 한 파일). 상단 `<script>`에 SUPABASE_URL / ANON_KEY 가 박혀 있음(anon 키는 공개 가능, RLS 로 보호). 외부 라이브러리: supabase-js 2.45.4, SheetJS 0.18.5, Chart.js 4.4.1, ExcelJS 4.4.0(지연 로드) |
| `supabase_setup.sql` | 스키마·함수·RLS 전체본. **멱등** — 처음부터 끝까지 재실행 가능해야 함 |
| `supabase_seed.sql` | media_map 119 + car_map 10,451 초기 매핑 |
| `migrations/` | setup 에 반영된 변경분을 따로 뽑은 파일 + 적용 현황표(README). **새 SQL 변경은 setup 에도 넣고 migrations 에도 파일을 추가** |
| `docs/` | 적용가이드, 매뉴얼 PDF 3종, 진단용 SQL |
| `integrations/ks-inflow-db/` | 별도 저장소(인입 DB 원장, Vercel)에 넣는 광고비 API 동기화 패치. 이 저장소에서는 실행되지 않음 |

## 데이터 모델 (요점)
- `inquiries` — 유입 문의 raw 50열. PK `inquiry_no`(문의번호), 업로드는 **upsert(같은 번호 갱신, 새 번호 누적)**. 트리거: `inq_date`(문의일시→날짜), `ip_raw`→`ip_hash`(SHA-256, 사설 IP 제외; 원문 IP 는 저장 안 함), `is_ip_dup`(같은 IP 7일 이내)
- `sales` — 매출 raw 12열. **배치 단위 insert**, `upload_batches.is_active` 로 집계 포함 여부. 같은 기간 재업로드 시 이전 배치 비활성화
- `media_map` — `media_raw` PK → `media_std`, `media_type`(마케팅/내부/경비/미분류), `platform`, `brand`. **브랜드 의미 = coalesce(brand, media_std)** (브랜드 미지정 매체는 매체명 자체가 브랜드로 표시)
- `car_map` — 차량명 raw → `model_std`, `brand`
- `ad_spend` — (spend_date, brand, channel) PK. 채널 12종 + 수수료 채널 3종(구글 애즈·메타 광고·블로그 인플루언서 ×15%). `source` 수기/api
- 집계: `agg_inquiry_media`, `agg_inquiry_car`(PostgREST 1,000행 한도·타임아웃 회피). 갱신은 `fn_refresh_agg()`; 유입 업로드 끝에 자동 호출, 설정 탭 [집계 갱신]
- 조회 함수: `fn_dashboard`(화면 1회 호출로 status,P,M,S,C,L0,LM,LC,LB,LMB,LPL,LD,LDM,LT,LQ,LQT 반환), `fn_media_period`, `fn_spend_period`, `fn_car_summary`, `fn_leadtime*`, `fn_data_status`, `fn_activity_log`
- 권한: RLS 는 `authenticated` 전용. anon 은 읽기도 불가. 관리자(`admin_users`)만 로그 탭. service_role 키는 앱에 절대 넣지 않음(원장 Vercel 환경변수에만)

## 지표 정의 (바꾸지 말 것 — 임원 보고 기준)
- 실행매출 = 계약마진 합계 (차량가 아님) · ROAS = 실행매출 ÷ 광고비 × 100 · CPA = 광고비 ÷ DB수(DB당) · 계약당 비용 = 광고비 ÷ 계약수(CPA 라 부르지 않음) · 전환율 = 계약 ÷ DB
- 중복 제외는 화면 체크박스 2개: CRM(중복여부=Y), IP(7일). 고객명은 중복 기준이 아님
- 매출 기준일 2종: 계약일자(기본) / 문의일자(코호트). 당월은 계약 진행 중이라 ROAS·전환율이 낮게 보이는 것이 정상(월말 기준 성숙도 약 69%, +30일 ≈ 90%)
- 리드타임 = 계약일자 − 문의일자(달력일), 음수·1년 초과·경비 매체 제외. 대표값은 중앙값. '7일 이내 비율'은 계약 건 중 비율, '인입 DB 기준 7일/30일 전환율'(fn_leadtime_cohort)은 문의 DB 가 분모 — 둘을 혼용하지 말 것. 지인(팀)·추가계약 등은 당일 계약이 많아 전체 중앙값을 끌어내림
- 전월 대비는 **완료된 두 달**만 비교(진행 중인 달 제외). 해석 패널 규칙 임계값: 브랜드 비교 광고비 ≥ max(3천만, 중앙값 10%), CPA 변동 ±3% 미만은 안정, 리드타임 비교 표본 ≥ 50건

## 절대 규칙
1. raw 행을 수정·삭제하지 않는다(중복·오타 포함). 정제는 매핑 테이블과 뷰에서만
2. 고객명은 기본 저장 안 함, 고객IP 는 해시만. 새 컬럼을 추가할 때 PII 여부 확인
3. 수수료 15% 규칙과 채널 이름 12종은 `index.html` 의 `CHANNELS`/`FEE_OF` 와 원장 패치 `CHANNEL_MAP` 이 **같이** 바뀌어야 함
4. SQL 함수 시그니처(인자 이름)를 바꾸면 `index.html` 의 `rpc()` 호출 인자명도 함께 수정. PostgREST 는 **인자 이름**으로 함수를 찾음
5. 새 함수를 만들면 `grant execute … to authenticated` + `notify pgrst, 'reload schema'`

## 개발·검증 방법
- JS 문법: `<script>` 블록을 뽑아 `node --check`
- 로컬 검증 DB: 실데이터(2601~2609 유입 242,873건·매출 9,734건)를 올린 PostgreSQL 16 을 세션에 두고 `fn_dashboard('2026-01-01','2026-10-28','month','contract')` 결과(`dash.json`)로 화면을 Playwright 렌더링해 미리보기 png 생성 → 사용자에게 **적용 전 미리보기**를 보여주는 것이 관례. 샌드박스는 CDN 차단이므로 Chart.js 는 shim 으로 대체
- 배포: `main` push → GitHub Pages 자동. SQL 은 사람이 SQL Editor 에서 실행(`migrations/README.md` 갱신)
- 키 교체: `index.html` 상단 두 상수만

## 알려진 한계 / 다음 과제 (우선순위)
1. 백업 없음(무료 플랜) → 주 1회 xlsx 내려받기 또는 Pro 전환($25/월) — **최우선**
2. 광고비 자동 수집: 원장(ks-inflow-db) 패치 적용 중 (`integrations/`)
3. 미분류 매체 40종, 브랜드 미지정 차량명 6,399종 정리 루틴
4. 채널(utm/유입링크) 단위 ROAS, 미판정 접수 상태 처리, 임원 요약 전용 탭, 차량 로고(회사 자산 필요)

## 운영 계정 메모
- 관리자: jisoo.h@ksautoplan.com
- 아이디 로그인(이메일 아님) 은 `id-<sha256(id)[:20]>@id.ksautoplan.local`, 6자 미만 비밀번호는 `+'__ks'` 로 변환해 Supabase Auth 에 저장

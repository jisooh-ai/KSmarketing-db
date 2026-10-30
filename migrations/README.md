# Supabase 변경분(마이그레이션) 적용 현황

`supabase_setup.sql`은 항상 **최신 전체본**(멱등 — 여러 번 실행해도 안전)이고, 이 폴더의 파일은 그 뒤에 추가된 **변경분만** 따로 뽑은 것입니다.
Supabase 는 GitHub 과 자동 연결되어 있지 않으므로, 아래 표의 "적용" 칸은 **사람이 SQL Editor 에서 실행한 뒤** 직접 갱신합니다.

| 파일 | 내용 | 적용 여부 (Supabase 운영) | 확인 방법 |
|---|---|---|---|
| `2026-10-28_01_리드타임분포_구분별.sql` | `fn_leadtime_dist_by` 신설, `fn_dashboard` 에 LDM 포함 | **미적용** (2026-10-30 13:11 확인 시 함수 없음) | `select proname from pg_proc where proname='fn_leadtime_dist_by';` → 1행 |
| `2026-10-28_02_광고비API연동.sql` | `ad_spend.source/synced_at`, `fn_spend_upsert_api`, `v_spend_api_keys` | 적용 (2026-10-28 16:50 함수 확인) | `select proname from pg_proc where proname='fn_spend_upsert_api';` → 1행 |
| `2026-10-30_01_인입코호트_단기전환율.sql` | `fn_leadtime_cohort` 신설(인입 DB 기준 7일·30일 전환율), `fn_dashboard` 에 LQ/LQT 포함 | **미적용** | `select proname from pg_proc where proname='fn_leadtime_cohort';` → 1행 |
| `applied/2026-10-21_매체브랜드매핑_반영.sql` | media_map 브랜드·유형 일괄 갱신 (데이터 변경) | 적용 (2026-10-21) | 대시보드 브랜드 목록에 2팀 브랜드 표시 |

## 적용 절차
1. Supabase → SQL Editor → 파일 내용 전체 붙여넣기 → Run (오류 없이 끝나는지 확인)
2. 함수 추가가 있으면 `notify pgrst, 'reload schema';` 한 줄 추가 실행 (API 캐시 갱신)
3. 위 "확인 방법" 쿼리로 검증 → 이 표의 적용 칸 갱신 → 커밋
4. 대시보드에서 [조회] 다시 누르기 (화면은 조회 시점 데이터를 들고 있음)

## 주의
- `vacuum full` 류는 트랜잭션 안에서 못 돌므로 **한 문장만 단독 실행**
- 무료 플랜 용량(500MB) 초과 시 읽기 전용이 됨 → `vacuum full public.inquiries;` 단독 실행 후 Pro 전환 검토

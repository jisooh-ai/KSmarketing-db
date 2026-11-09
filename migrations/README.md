# Supabase 변경분(마이그레이션) 적용 현황

`supabase_setup.sql`은 항상 **최신 전체본**(멱등 — 여러 번 실행해도 안전)이고, 이 폴더의 파일은 그 뒤에 추가된 **변경분만** 따로 뽑은 것입니다.
Supabase 는 GitHub 과 자동 연결되어 있지 않으므로, 아래 표의 "적용" 칸은 **사람이 SQL Editor 에서 실행한 뒤** 직접 갱신합니다.

| 파일 | 내용 | 적용 여부 (Supabase 운영) | 확인 방법 |
|---|---|---|---|
| `2026-10-28_01_리드타임분포_구분별.sql` | `fn_leadtime_dist_by` 신설, `fn_dashboard` 에 LDM 포함 | 적용 (2026-10-30 15:36 화면 확인) | `select proname from pg_proc where proname='fn_leadtime_dist_by';` → 1행 |
| `2026-10-28_02_광고비API연동.sql` | `ad_spend.source/synced_at`, `fn_spend_upsert_api`, `v_spend_api_keys` | 적용 (2026-10-28 16:50 함수 확인) | `select proname from pg_proc where proname='fn_spend_upsert_api';` → 1행 |
| `2026-10-30_01_인입코호트_단기전환율.sql` | `fn_leadtime_cohort` 신설(인입 DB 기준 7일·30일 전환율), `fn_dashboard` 에 LQ/LQT 포함 | 적용 (2026-10-30 15:36 화면 확인) | `select proname from pg_proc where proname='fn_leadtime_cohort';` → 1행 |
| `2026-10-30_02_채널단위_ROAS.sql` | 유입링크→채널 매핑(`channel_map`, `fn_link_key`), `agg_inquiry_channel`, `fn_refresh_agg` 갱신, `fn_channel_period`, `fn_dashboard` 에 CH/CHT, 시드 60여 키 | 적용 (2026-10-30 화면 확인) | `select count(*) from channel_map;` → 60 이상 · `select proname from pg_proc where proname='fn_channel_period';` → 1행 |
| `2026-11-05_01_집계_구간갱신.sql` | `fn_refresh_agg_range(p_from,p_to)`, `fn_agg_months` — 월 단위 집계 갱신(90초 제한 회피). 화면은 이 함수를 월별 반복 호출 | 적용 (2026-11-06 16:21 사용자 확인) | `select proname from pg_proc where proname='fn_refresh_agg_range';` → 1행 |
| `2026-11-06_01_엔카_KS오토플랜_귀속.sql` | `media_map` 엔카 → 브랜드 KS오토플랜·플랫폼 엔카, `fn_channel_fallback` 에 엔카→'기타' 규칙 (수기 ROAS 시트와 귀속 기준 일치) | 적용 (2026-11-06 16:21 사용자 확인) | `select brand from media_map where media_raw='엔카';` → KS오토플랜 |
| `2026-11-06_02_매출배치_기간중복.sql` | `fn_sales_batch_overlap` — 매출 업로드 검증 때 계약일자 기간이 겹치는 활성 배치를 표시하고 업로드 후 자동 비활성화(체크 기본 켜짐) | 적용 (2026-11-06 16:21 사용자 확인) | `select proname from pg_proc where proname='fn_sales_batch_overlap';` → 1행 |
| `2026-11-09_01_매체별_유입키워드.sql` | `fn_media_keywords(p_medias)` — 매체 마스터에 매체별 상위 유입키워드·유입링크 열 표시 | **미적용** | `select proname from pg_proc where proname='fn_media_keywords';` → 1행 |
| `applied/2026-10-21_매체브랜드매핑_반영.sql` | media_map 브랜드·유형 일괄 갱신 (데이터 변경) | 적용 (2026-10-21) | 대시보드 브랜드 목록에 2팀 브랜드 표시 |

## 적용 절차
1. Supabase → SQL Editor → 파일 내용 전체 붙여넣기 → Run (오류 없이 끝나는지 확인)
2. 함수 추가가 있으면 `notify pgrst, 'reload schema';` 한 줄 추가 실행 (API 캐시 갱신)
3. 위 "확인 방법" 쿼리로 검증 → 이 표의 적용 칸 갱신 → 커밋
4. 대시보드에서 [조회] 다시 누르기 (화면은 조회 시점 데이터를 들고 있음)

## 주의
- `vacuum full` 류는 트랜잭션 안에서 못 돌므로 **한 문장만 단독 실행**
- 무료 플랜 용량(500MB) 초과 시 읽기 전용이 됨 → `vacuum full public.inquiries;` 단독 실행 후 Pro 전환 검토

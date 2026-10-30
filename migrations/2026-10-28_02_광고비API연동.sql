-- 광고비 API 자동 수집 연동 (인입 DB 원장 Vercel → ad_spend)
-- 1) 출처 컬럼: '수기'(웹 업로드·직접 입력) / 'api'(원장 자동 수집) / 'report'(GFA 보고서 업로드)
alter table public.ad_spend add column if not exists source text not null default '수기';
alter table public.ad_spend add column if not exists synced_at timestamptz;

-- 2) API 수집용 upsert 함수 (service_role 키로 Vercel 에서 호출)
--    같은 일자·브랜드·채널 행이 '수기'로 있어도 API 값으로 덮어씀 (API 가 매체 화면 금액이라 우선)
--    rows: [{spend_date, brand, channel, cost}]
create or replace function public.fn_spend_upsert_api(rows jsonb, p_source text default 'api')
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.ad_spend (spend_date, brand, channel, cost, source, synced_at, updated_at)
  select (r->>'spend_date')::date, r->>'brand', r->>'channel', coalesce((r->>'cost')::numeric,0), p_source, now(), now()
  from jsonb_array_elements(rows) r
  where r->>'spend_date' is not null and r->>'brand' is not null and r->>'channel' is not null
  on conflict (spend_date, brand, channel) do update
    set cost = excluded.cost, source = excluded.source, synced_at = excluded.synced_at, updated_at = now();
  get diagnostics n = row_count;
  insert into public.activity_log (action, target, detail) values ('spend_api_sync', 'ad_spend', jsonb_build_object('rows', n, 'source', p_source));
  return jsonb_build_object('rows', n);
end $$;
revoke execute on function public.fn_spend_upsert_api(jsonb, text) from public, anon, authenticated;
-- service_role 은 기본으로 실행 가능 (RLS 우회)

-- 3) 수기 업로드가 API 행을 덮어쓰지 않도록, 웹 업로드 전에 조회하는 뷰
create or replace view public.v_spend_api_keys with (security_invoker = true) as
  select spend_date, brand, channel from public.ad_spend where source <> '수기';

notify pgrst, 'reload schema';

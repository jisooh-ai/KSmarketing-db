-- 인입 DB 기준 단기 전환율 (코호트): 문의한 DB 중 7일 / 30일 안에 계약된 비율
-- p_dim   : 'all' | 'media' | 'media_brand' | 'platform'
-- p_grain : 'all'(기간 합계) | 'month' | 'week' | 'day'
-- 분모 = 문의일자가 p_from~p_to 인 DB (db_count / net_db / ip_db / both_db 모두 반환, 화면에서 중복 제외 기준 선택)
-- 분자 = 같은 문의일자 코호트에서 lead_days 0~7 / 0~30 인 정상 계약 (매출 활성 배치, 경비 매체 제외)
drop function if exists public.fn_leadtime_cohort(date, date, text, text, text[]);
create or replace function public.fn_leadtime_cohort(p_from date, p_to date, p_dim text, p_grain text, p_brands text[] default null)
returns jsonb language sql stable as $$
with inq as (
  select public.fn_period(p_grain, a.inq_date, p_from) as period,
         case p_dim when 'media' then coalesce(m.media_std, a.media) when 'media_brand' then coalesce(m.brand, m.media_std, a.media)
                    when 'platform' then coalesce(m.platform, '(플랫폼 미지정)') else '전체' end as dim_value,
         sum(a.db_count)::bigint as db_count, sum(a.net_db)::bigint as net_db, sum(a.ip_db)::bigint as ip_db, sum(a.both_db)::bigint as both_db
  from public.agg_inquiry_media a
  left join public.media_map m on m.media_raw = a.media
  where a.inq_date between p_from and p_to
    and coalesce(m.media_type, '미분류') <> '경비'
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(m.brand, m.media_std, a.media) = any(p_brands))
  group by 1, 2),
sal as (
  select public.fn_period(p_grain, inquiry_date, p_from) as period,
         case p_dim when 'media' then media_std when 'media_brand' then coalesce(media_brand, media_std)
                    when 'platform' then coalesce(platform, '(플랫폼 미지정)') else '전체' end as dim_value,
         count(*) filter (where lead_days between 0 and 7)  as c7,
         count(*) filter (where lead_days between 0 and 30) as c30,
         count(*) filter (where lead_flag = '정상')          as c_all
  from public.v_sales
  where is_active and media_matched and media_type <> '경비' and inquiry_date between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))
  group by 1, 2),
keys as (select period, dim_value from inq union select period, dim_value from sal),
t as (
  select k.period, k.dim_value,
         coalesce(i.db_count,0) db_count, coalesce(i.net_db,0) net_db, coalesce(i.ip_db,0) ip_db, coalesce(i.both_db,0) both_db,
         coalesce(s.c7,0) c7, coalesce(s.c30,0) c30, coalesce(s.c_all,0) c_all
  from keys k left join inq i using (period, dim_value) left join sal s using (period, dim_value)
  order by k.period, coalesce(i.db_count,0) desc)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;
grant execute on function public.fn_leadtime_cohort(date, date, text, text, text[]) to authenticated;

-- 대시보드 통합 호출에 코호트 전환율 포함 (LQ: 자사 브랜드별 합계, LQT: 전체 월별)
create or replace function public.fn_dashboard(p_from date, p_to date, p_grain text, p_basis text, p_brands text[] default null)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'status', public.fn_data_status(),
    'P',   (select coalesce(jsonb_agg(e - 'platform'), '[]'::jsonb)
            from jsonb_array_elements(public.fn_media_period(p_from, p_to, p_grain, p_basis)) e),
    'M',   public.fn_media_period(p_from, p_to, 'all',   p_basis),
    'S',   public.fn_spend_period(p_from, p_to, p_grain),
    'C',   public.fn_car_summary(p_from, p_to, p_basis, 300, p_brands),
    'L0',  public.fn_leadtime(p_from, p_to, p_basis, 'all', p_brands),
    'LM',  public.fn_leadtime(p_from, p_to, p_basis, 'media', p_brands),
    'LC',  public.fn_leadtime(p_from, p_to, p_basis, 'car', p_brands),
    'LB',  public.fn_leadtime(p_from, p_to, p_basis, 'car_brand', p_brands),
    'LMB', public.fn_leadtime(p_from, p_to, p_basis, 'media_brand', p_brands),
    'LPL', public.fn_leadtime(p_from, p_to, p_basis, 'platform', p_brands),
    'LD',  public.fn_leadtime_dist(p_from, p_to, p_basis, p_brands),
    'LDM', public.fn_leadtime_dist_by(p_from, p_to, p_basis, 'media_brand', p_brands),
    'LT',  public.fn_leadtime_trend(p_from, p_to, p_basis, 'month', p_brands),
    'LQ',  public.fn_leadtime_cohort(p_from, p_to, 'media_brand', 'all', p_brands),
    'LQT', public.fn_leadtime_cohort(p_from, p_to, 'all', 'month', p_brands)
  )
$$;
notify pgrst, 'reload schema';

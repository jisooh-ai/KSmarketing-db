-- 리드타임 분포를 구분(유입매체/자사 브랜드/플랫폼/매체유형)별로 반환
-- p_dim = 'media' | 'media_brand' | 'platform' | 'media_type'
drop function if exists public.fn_leadtime_dist_by(date, date, text, text, text[]);
create or replace function public.fn_leadtime_dist_by(p_from date, p_to date, p_basis text, p_dim text, p_brands text[] default null)
returns jsonb language sql stable as $$
with base as (
  select case p_dim when 'media' then media_std when 'media_brand' then coalesce(media_brand, media_std)
                    when 'platform' then coalesce(platform,'(플랫폼 미지정)') when 'media_type' then media_type else '전체' end as dim_value,
         lead_days
  from public.v_sales
  where is_active and media_matched and lead_flag = '정상' and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))),
t as (
  select dim_value,
         case when lead_days = 0 then '0일' when lead_days <= 3 then '1-3일'
              when lead_days <= 7 then '4-7일' when lead_days <= 14 then '8-14일'
              when lead_days <= 30 then '15-30일' when lead_days <= 60 then '31-60일'
              else '61일+' end as bucket,
         min(lead_days) as ord, count(*) as n
  from base group by 1,2 order by 1, ord)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

grant execute on function public.fn_leadtime_dist_by(date, date, text, text, text[]) to authenticated;

-- 대시보드 통합 호출에 매체별 분포(LDM) 포함
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
    'LT',  public.fn_leadtime_trend(p_from, p_to, p_basis, 'month', p_brands)
  )
$$;

-- =====================================================================
--  마케팅 퍼포먼스 DB  (Supabase / PostgreSQL)   v1.0
--  Supabase 대시보드 > SQL Editor 에 전체를 붙여넣고 Run 1회.
--  (seed 파일 supabase_seed.sql 은 이 파일 실행 후 별도로 Run)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. 테이블
-- ---------------------------------------------------------------------
create table if not exists public.upload_batches (
  id           bigserial primary key,
  kind         text not null check (kind in ('inquiry','sales','ad_spend')),
  filename     text,
  file_hash    text,
  row_count    integer not null default 0,
  note         text,
  is_active    boolean not null default true,      -- 매출: 집계 포함 여부
  uploaded_by  text,
  uploaded_at  timestamptz not null default now()
);

-- 유입 raw (문의번호 고유키 → 재업로드 시 upsert)
create table if not exists public.inquiries (
  inquiry_no      text primary key,
  src_no          integer,
  lock_state      text,
  status          text,
  inquired_at     timestamptz,
  inq_date        date,                 -- 문의일(KST), 트리거로 자동 계산
  car_name        text,
  grade           text,
  trim_name       text,
  options         text,
  car_color       text,
  interior_color  text,
  car_price       numeric,
  option_price    numeric,
  usage_method    text,
  term_months     text,
  annual_km       text,
  insurance_age   text,
  prepayment      numeric,
  deposit         numeric,
  monthly_pay     numeric,
  customer_type   text,
  alert_type      text,
  manager         text,
  team            text,
  assign_group    text,
  assign_type     text,
  assigned_at     timestamptz,
  is_duplicate    text,
  media           text,                 -- 광고매체 (조인 키)
  credit          text,
  registered_at   timestamptz,
  updated_at      timestamptz,
  inbound_link    text,
  inbound_keyword text,
  utm_source      text,
  utm_medium      text,
  utm_campaign    text,
  utm_term        text,
  utm_content     text,
  utm_creative    text,
  utm_network     text,
  consents        jsonb,                -- 동의 7개 컬럼
  raw             jsonb,                -- 원본 전체(개인정보 컬럼 제외) 보존
  batch_id        bigint references public.upload_batches(id) on delete set null,
  loaded_at       timestamptz not null default now()
);
create index if not exists inquiries_inquired_at_idx on public.inquiries (inquired_at);
create index if not exists inquiries_inq_date_idx    on public.inquiries (inq_date, media);
create index if not exists inquiries_media_idx       on public.inquiries (media);
create index if not exists inquiries_car_idx         on public.inquiries (car_name);
create index if not exists inquiries_batch_idx       on public.inquiries (batch_id);

-- 매출 raw (고유키 없음 → 업로드 배치 단위로 보존, 활성 배치만 집계)
create table if not exists public.sales (
  id              bigserial primary key,
  batch_id        bigint not null references public.upload_batches(id) on delete cascade,
  src_no          integer,
  status          text,
  registered_at   timestamptz,
  car_name        text,
  car_price       numeric,
  option_price    numeric,
  margin          numeric,
  media           text,                 -- 유입매체 (조인 키)
  inbound_link    text,
  inbound_keyword text,
  inquiry_date    date,
  contract_date   date,
  raw             jsonb
);
create index if not exists sales_contract_idx on public.sales (contract_date);
create index if not exists sales_inquiry_idx  on public.sales (inquiry_date);
create index if not exists sales_media_idx    on public.sales (media);
create index if not exists sales_batch_idx    on public.sales (batch_id);

-- 매체 마스터 (유입 raw의 광고매체가 기준. 유입 업로드 시 자동 추가)
create table if not exists public.media_map (
  media_raw   text primary key,
  media_std   text not null,
  media_type  text not null default '미분류'
              check (media_type in ('유료광고','오가닉','내부','경비','미분류')),
  platform    text,
  brand       text,                     -- 자사 브랜드(KS오토플랜, 저신용 신차장기렌트 …)
  memo        text,
  updated_at  timestamptz not null default now()
);

-- 차량 마스터 (유입·매출 업로드 시 자동 추가, 브랜드/표준모델은 수기·자동)
create table if not exists public.car_map (
  car_raw     text primary key,
  brand       text,
  model_std   text,
  segment     text,
  mapped_by   text,                     -- '자동' | '수기'
  updated_at  timestamptz not null default now()
);

-- 광고비 (표준매체명 기준, 일 단위)
create table if not exists public.ad_spend (
  spend_date  date not null,
  media_std   text not null,
  cost        numeric not null default 0,
  impressions bigint,
  clicks      bigint,
  memo        text,
  updated_at  timestamptz not null default now(),
  primary key (spend_date, media_std)
);

-- ---------------------------------------------------------------------
-- 1. 트리거: 업로드 시 매체·차량 마스터 자동 등록
-- ---------------------------------------------------------------------
create or replace function public.trg_inquiry_maps() returns trigger
language plpgsql as $$
begin
  new.inq_date := (new.inquired_at at time zone 'Asia/Seoul')::date;
  if new.media is not null and btrim(new.media) <> '' then
    insert into public.media_map (media_raw, media_std) values (new.media, new.media)
    on conflict do nothing;
  end if;
  if new.car_name is not null and btrim(new.car_name) <> '' then
    insert into public.car_map (car_raw) values (new.car_name) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists inquiries_maps on public.inquiries;
create trigger inquiries_maps before insert or update on public.inquiries
for each row execute function public.trg_inquiry_maps();

create or replace function public.trg_sales_maps() returns trigger
language plpgsql as $$
begin
  -- 매체는 유입 기준이므로 매출에서는 자동 등록하지 않음 (미매칭으로 분리)
  if new.car_name is not null and btrim(new.car_name) <> '' then
    insert into public.car_map (car_raw) values (new.car_name) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists sales_maps on public.sales;
create trigger sales_maps before insert on public.sales
for each row execute function public.trg_sales_maps();

-- ---------------------------------------------------------------------
-- 2. 뷰
-- ---------------------------------------------------------------------
create or replace view public.v_inquiries
with (security_invoker = true) as
select i.*,
       coalesce(m.media_std, i.media)        as media_std,
       coalesce(m.media_type, '미분류')       as media_type,
       m.platform,
       m.brand                                as media_brand,
       c.brand                                as car_brand,
       coalesce(c.model_std, i.car_name)      as model_std
from public.inquiries i
left join public.media_map m on m.media_raw = i.media
left join public.car_map   c on c.car_raw   = i.car_name;

create or replace view public.v_sales
with (security_invoker = true) as
select s.*,
       b.is_active,
       (s.contract_date - s.inquiry_date)      as lead_days,
       case when s.inquiry_date is null or s.contract_date is null then '날짜없음'
            when s.contract_date < s.inquiry_date                   then '음수'
            when s.contract_date - s.inquiry_date > 365             then '1년초과'
            else '정상' end                     as lead_flag,
       (m.media_raw is not null)               as media_matched,   -- 유입 기준 매칭 여부
       coalesce(m.media_std, s.media)          as media_std,
       coalesce(m.media_type, '미분류')         as media_type,
       m.platform,
       m.brand                                 as media_brand,
       c.brand                                 as car_brand,
       coalesce(c.model_std, s.car_name)       as model_std
from public.sales s
join public.upload_batches b on b.id = s.batch_id
left join public.media_map m on m.media_raw = s.media
left join public.car_map   c on c.car_raw   = s.car_name;

-- 매출 중 유입 매체와 매칭되지 않는 행 (별도 분리)
create or replace view public.v_sales_unmatched
with (security_invoker = true) as
select * from public.v_sales where is_active and not media_matched;

-- 차량명별 건수 (매핑 작업용)
create or replace view public.v_car_counts
with (security_invoker = true) as
select c.car_raw, c.brand, c.model_std, c.segment, c.mapped_by,
       coalesce(i.n,0) as inquiry_count, coalesce(s.n,0) as sales_count
from public.car_map c
left join (select car_name, count(*) n from public.inquiries group by 1) i on i.car_name = c.car_raw
left join (select car_name, count(*) n from public.sales    group by 1) s on s.car_name = c.car_raw;

-- 매체명별 건수 (매핑 작업용)
create or replace view public.v_media_counts
with (security_invoker = true) as
select m.*, coalesce(i.n,0) as inquiry_count, coalesce(s.n,0) as sales_count
from public.media_map m
left join (select media, count(*) n from public.inquiries group by 1) i on i.media = m.media_raw
left join (select media, count(*) n from public.sales s join public.upload_batches b on b.id=s.batch_id and b.is_active group by 1) s on s.media = m.media_raw;

-- ---------------------------------------------------------------------
-- 3. 집계 RPC (결과를 jsonb 하나로 반환 → PostgREST 행수 제한 무관)
--    p_grain : 'day' | 'week' | 'month' | 'year' | 'all'
--    p_basis : 'contract' (계약일자) | 'inquiry' (문의일자)
-- ---------------------------------------------------------------------
create or replace function public.fn_period(p_grain text, d date, p_from date)
returns date language sql immutable as $$
  select case when p_grain = 'all' then p_from
              else date_trunc(p_grain, d)::date end
$$;

-- 매체 × 기간 : DB수, 순DB수, 계약수, 매출, 마진, 광고비
create or replace function public.fn_media_period(p_from date, p_to date, p_grain text, p_basis text)
returns jsonb language sql stable as $$
with inq as (
  select public.fn_period(p_grain, inq_date, p_from) as period, media_std,
         count(*) as db_count,
         count(*) filter (where is_duplicate = 'N') as net_db
  from public.v_inquiries
  where inq_date between p_from and p_to
  group by 1,2),
sal as (
  select public.fn_period(p_grain, case when p_basis='inquiry' then inquiry_date else contract_date end, p_from) as period,
         media_std,
         count(*) as contracts,
         sum(coalesce(car_price,0)) as revenue,
         sum(coalesce(margin,0))    as margin
  from public.v_sales
  where is_active and media_matched
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
  group by 1,2),
sp as (
  select public.fn_period(p_grain, spend_date, p_from) as period, media_std, sum(cost) as cost,
         sum(impressions) as impressions, sum(clicks) as clicks
  from public.ad_spend where spend_date between p_from and p_to group by 1,2),
keys as (
  select period, media_std from inq union
  select period, media_std from sal union
  select period, media_std from sp),
mm as (
  select distinct on (media_std) media_std, media_type, platform, brand
  from public.media_map order by media_std, updated_at desc),
t as (
  select k.period, k.media_std,
         coalesce(mm.media_type,'미분류') as media_type, mm.platform, mm.brand,
         coalesce(inq.db_count,0)  as db_count,
         coalesce(inq.net_db,0)    as net_db,
         coalesce(sal.contracts,0) as contracts,
         coalesce(sal.revenue,0)   as revenue,
         coalesce(sal.margin,0)    as margin,
         coalesce(sp.cost,0)       as cost,
         coalesce(sp.impressions,0) as impressions,
         coalesce(sp.clicks,0)     as clicks
  from keys k
  left join inq using (period, media_std)
  left join sal using (period, media_std)
  left join sp  using (period, media_std)
  left join mm  on mm.media_std = k.media_std
  order by k.period, k.media_std)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 차량(표준모델) 기준 : 문의수, 순DB, 계약수, 매출
create or replace function public.fn_car_summary(p_from date, p_to date, p_basis text)
returns jsonb language sql stable as $$
with inq as (
  select model_std, mode() within group (order by car_brand) as car_brand,
         count(*) as db_count, count(*) filter (where is_duplicate='N') as net_db
  from public.v_inquiries where inq_date between p_from and p_to group by 1),
sal as (
  select model_std, mode() within group (order by car_brand) as car_brand,
         count(*) as contracts, sum(coalesce(car_price,0)) as revenue, sum(coalesce(margin,0)) as margin
  from public.v_sales
  where is_active and media_type not in ('경비')
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
  group by 1),
keys as (select model_std from inq union select model_std from sal),
t as (
  select k.model_std, coalesce(inq.car_brand, sal.car_brand) as car_brand,
         coalesce(inq.db_count,0) db_count, coalesce(inq.net_db,0) net_db,
         coalesce(sal.contracts,0) contracts, coalesce(sal.revenue,0) revenue, coalesce(sal.margin,0) margin
  from keys k left join inq using (model_std) left join sal using (model_std))
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 리드타임 : p_dim = 'all' | 'media' | 'media_brand' | 'car' | 'car_brand'
create or replace function public.fn_leadtime(p_from date, p_to date, p_basis text, p_dim text)
returns jsonb language sql stable as $$
with base as (
  select case p_dim when 'media' then media_std when 'media_brand' then media_brand
                    when 'car' then model_std   when 'car_brand' then car_brand else '전체' end as dim_value,
         lead_days
  from public.v_sales
  where is_active and media_matched and lead_flag = '정상' and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to),
t as (
  select dim_value, count(*) as n,
         round(avg(lead_days)::numeric, 1) as avg_days,
         percentile_cont(0.5) within group (order by lead_days) as median_days,
         percentile_cont(0.25) within group (order by lead_days) as p25,
         percentile_cont(0.75) within group (order by lead_days) as p75,
         round(100.0 * count(*) filter (where lead_days <= 7) / count(*), 1) as within7_pct
  from base group by 1 order by n desc)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 리드타임 분포(구간) + 제외 사유 집계
create or replace function public.fn_leadtime_dist(p_from date, p_to date, p_basis text)
returns jsonb language sql stable as $$
with base as (
  select lead_days, lead_flag from public.v_sales
  where is_active and media_matched and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to),
t as (
  select case when lead_flag <> '정상' then '제외(' || lead_flag || ')'
              when lead_days = 0 then '0일' when lead_days <= 3 then '1-3일'
              when lead_days <= 7 then '4-7일' when lead_days <= 14 then '8-14일'
              when lead_days <= 30 then '15-30일' when lead_days <= 60 then '31-60일'
              else '61일+' end as bucket,
         min(case when lead_flag <> '정상' then 999 else lead_days end) as ord,
         count(*) as n
  from base group by 1 order by ord)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 데이터 범위/상태 요약 (대시보드 상단)
create or replace function public.fn_data_status()
returns jsonb language sql stable as $$
select jsonb_build_object(
  'inquiries',        (select count(*) from public.inquiries),
  'inquiry_min',      (select min(inquired_at) from public.inquiries),
  'inquiry_max',      (select max(inquired_at) from public.inquiries),
  'sales_active',     (select count(*) from public.v_sales where is_active),
  'sales_unmatched',  (select count(*) from public.v_sales_unmatched),
  'contract_min',     (select min(contract_date) from public.v_sales where is_active),
  'contract_max',     (select max(contract_date) from public.v_sales where is_active),
  'media_unclassified',(select count(*) from public.media_map where media_type='미분류'),
  'car_unmapped',     (select count(*) from public.v_car_counts where brand is null and (inquiry_count>0 or sales_count>0)),
  'ad_spend_days',    (select count(distinct spend_date) from public.ad_spend),
  'ad_spend_max',     (select max(spend_date) from public.ad_spend)
)
$$;

-- ---------------------------------------------------------------------
-- 4. RLS : 로그인(authenticated) 사용자만 전체 권한, 익명 차단
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['upload_batches','inquiries','sales','media_map','car_map','ad_spend'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists auth_all on public.%I', t);
    execute format('create policy auth_all on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

grant usage on schema public to authenticated;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
revoke all on all tables in schema public from anon;
revoke execute on all functions in schema public from anon;

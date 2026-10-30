-- =====================================================================
--  마케팅 퍼포먼스 DB  (Supabase / PostgreSQL)   v1.0
--  Supabase 대시보드 > SQL Editor 에 전체를 붙여넣고 Run 1회.
--  (seed 파일 supabase_seed.sql 은 이 파일 실행 후 별도로 Run)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. 테이블
-- ---------------------------------------------------------------------
create extension if not exists pgcrypto;
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
  ip_raw          text,                 -- 업로드 시 잠시 받는 고객IP (트리거가 해시 후 즉시 비움, 저장 안 됨)
  ip_hash         text,                 -- 고객IP SHA-256 (사설IP·공란은 null) → IP 중복 판정용
  is_ip_dup       boolean not null default false, -- 같은 IP로 7일 내 재문의 (fn_refresh_agg 가 계산)
  raw             jsonb,                -- 원본 전체(개인정보 컬럼 제외) 보존
  batch_id        bigint references public.upload_batches(id) on delete set null,
  loaded_at       timestamptz not null default now()
);
create index if not exists inquiries_inquired_at_idx on public.inquiries (inquired_at);
create index if not exists inquiries_inq_date_idx    on public.inquiries (inq_date, media);
create index if not exists inquiries_media_idx       on public.inquiries (media);
create index if not exists inquiries_car_idx         on public.inquiries (car_name);
create index if not exists inquiries_batch_idx       on public.inquiries (batch_id);
-- 기존 테이블 업그레이드용 (이미 있으면 무시)
alter table public.inquiries add column if not exists ip_raw text;
alter table public.inquiries add column if not exists ip_hash text;
alter table public.inquiries add column if not exists is_ip_dup boolean not null default false;
create index if not exists inquiries_iphash_idx      on public.inquiries (ip_hash, inquired_at) where ip_hash is not null;
create index if not exists inquiries_ip_pending_idx  on public.inquiries (inquiry_no) where ip_hash is null and (raw ? '고객IP');

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
  media_type  text not null default '미분류',   -- 마케팅 | 내부 | 경비 | 미분류
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

-- 광고비 (브랜드 × 광고채널, 일 단위)
do $$ begin  -- 구버전(매체 기준) 테이블은 이름을 바꿔 보관
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='ad_spend' and column_name='media_std') then
    alter table public.ad_spend rename to ad_spend_old_by_media;
  end if;
end $$;
create table if not exists public.ad_spend (
  spend_date  date not null,
  brand       text not null,              -- media_map.brand 와 같은 값 ('(브랜드 없음)' 허용)
  channel     text not null,              -- 네이버 파워링크, 네이버 GFA, 카카오 키워드 광고, … , 기타
  cost        numeric not null default 0,
  impressions bigint,
  clicks      bigint,
  memo        text,
  updated_at  timestamptz not null default now(),
  primary key (spend_date, brand, channel)
);
create index if not exists ad_spend_brand_idx on public.ad_spend (brand, spend_date);

-- ---------------------------------------------------------------------
-- 1. 트리거: 업로드 시 매체·차량 마스터 자동 등록
-- ---------------------------------------------------------------------
create or replace function public.trg_inquiry_maps() returns trigger
language plpgsql as $$
begin
  new.inq_date := (new.inquired_at at time zone 'Asia/Seoul')::date;
  if new.ip_raw is not null then
    -- 사설 IP(서버 경유: 172.16~31.x, 10.x, 192.168.x)와 공란은 중복 판정에서 제외
    if btrim(new.ip_raw) = '' or new.ip_raw ~ '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.)' then
      new.ip_hash := null;
    else
      new.ip_hash := encode(digest(btrim(new.ip_raw), 'sha256'), 'hex');
    end if;
    new.ip_raw := null;   -- 원문 IP는 저장하지 않음
  end if;
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
-- 2. 뷰  (테이블 컬럼이 늘어나도 재생성되도록 drop 후 create)
-- ---------------------------------------------------------------------
drop view if exists public.v_sales_unmatched, public.v_media_counts, public.v_car_counts, public.v_sales, public.v_inquiries;
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
-- 2-1. 유입 일별 집계 테이블 (24만 행 매번 스캔 방지)
--      업로드 후 앱이 fn_refresh_agg() 를 자동 호출. 수동: select fn_refresh_agg();
-- ---------------------------------------------------------------------
create table if not exists public.agg_inquiry_media (
  inq_date date not null, media text not null,
  db_count integer not null, net_db integer not null,
  ip_db integer not null default 0, both_db integer not null default 0,
  primary key (inq_date, media)
);
create table if not exists public.agg_inquiry_car (
  inq_date date not null, media text not null default '(없음)', car_name text not null,
  db_count integer not null, net_db integer not null,
  ip_db integer not null default 0, both_db integer not null default 0,
  primary key (inq_date, media, car_name)
);
-- 이전 버전(media 없음) 업그레이드
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='agg_inquiry_car' and column_name='media') then
    drop table public.agg_inquiry_car;
    create table public.agg_inquiry_car (
      inq_date date not null, media text not null default '(없음)', car_name text not null,
      db_count integer not null, net_db integer not null,
      ip_db integer not null default 0, both_db integer not null default 0,
      primary key (inq_date, media, car_name));
  end if;
end $$;
alter table public.agg_inquiry_media add column if not exists ip_db integer not null default 0;
alter table public.agg_inquiry_media add column if not exists both_db integer not null default 0;
alter table public.agg_inquiry_car   add column if not exists ip_db integer not null default 0;
alter table public.agg_inquiry_car   add column if not exists both_db integer not null default 0;
create table if not exists public.agg_meta (k text primary key, v text);

create or replace function public.fn_refresh_agg() returns jsonb
language plpgsql as $$
declare n1 int; n2 int; n3 int; pending int;
begin
  select count(*) into pending from public.inquiries where ip_hash is null and (raw ? '고객IP');
  -- IP 중복: 같은 IP(해시)로 7일 이내에 먼저 들어온 문의가 있으면 중복
  update public.inquiries a set is_ip_dup = coalesce(d.dup,false)
  from (select inquiry_no,
               (lag(inquired_at) over (partition by ip_hash order by inquired_at, inquiry_no)
                  >= inquired_at - interval '7 days') as dup
        from public.inquiries where ip_hash is not null) d
  where a.inquiry_no = d.inquiry_no and a.is_ip_dup is distinct from coalesce(d.dup,false);
  get diagnostics n3 = row_count;
  truncate public.agg_inquiry_media;
  insert into public.agg_inquiry_media
    select inq_date, coalesce(media,'(없음)'), count(*), count(*) filter (where is_duplicate='N'),
           count(*) filter (where not is_ip_dup), count(*) filter (where is_duplicate='N' and not is_ip_dup)
    from public.inquiries where inq_date is not null group by 1,2;
  get diagnostics n1 = row_count;
  truncate public.agg_inquiry_car;
  insert into public.agg_inquiry_car
    select inq_date, coalesce(media,'(없음)'), coalesce(car_name,'(없음)'), count(*), count(*) filter (where is_duplicate='N'),
           count(*) filter (where not is_ip_dup), count(*) filter (where is_duplicate='N' and not is_ip_dup)
    from public.inquiries where inq_date is not null group by 1,2,3;
  get diagnostics n2 = row_count;
  insert into public.agg_meta values ('refreshed_at', now()::text)
    on conflict (k) do update set v = excluded.v;
  analyze public.inquiries; analyze public.sales; analyze public.agg_inquiry_media; analyze public.agg_inquiry_car;
  insert into public.activity_log (action, target, detail) values ('agg_refresh', 'agg', jsonb_build_object('media_rows', n1, 'car_rows', n2, 'ip_dup_changed', n3));
  return jsonb_build_object('media_rows', n1, 'car_rows', n2, 'ip_dup_changed', n3, 'ip_pending', pending, 'refreshed_at', now());
end $$;

-- 유형 체계 정리: (구) 유료광고/오가닉 → 마케팅
alter table public.media_map drop constraint if exists media_map_media_type_check;
update public.media_map set media_type='마케팅', updated_at=now() where media_type in ('유료광고','오가닉');
alter table public.media_map add constraint media_map_media_type_check check (media_type in ('마케팅','내부','경비','미분류'));

-- 이름상 명백한 정산/경비 매체는 기본 유형을 '경비'로 (미분류인 경우에만)
update public.media_map set media_type='경비', updated_at=now()
 where media_type='미분류' and media_raw like '%정산전용%';

-- (이전 버전에서 raw 에 남은 고객IP → 해시로 이관) : 호출당 p_n 행씩, 앱이 pending=0 까지 반복 호출
create or replace function public.fn_ip_migrate(p_n int default 10000) returns jsonb
language plpgsql as $$
declare done int; pending int;
begin
  with batch as (
    select inquiry_no from public.inquiries where ip_hash is null and (raw ? '고객IP') limit greatest(1, least(p_n, 50000)))
  update public.inquiries i set ip_raw = i.raw->>'고객IP', raw = (i.raw - '고객IP')
  from batch b where b.inquiry_no = i.inquiry_no;
  get diagnostics done = row_count;
  select count(*) into pending from public.inquiries where ip_hash is null and (raw ? '고객IP');
  return jsonb_build_object('done', done, 'ip_pending', pending);
end $$;

-- 쿼리 제한시간 완화 (Supabase 기본 8초 → 90초)
alter role authenticated set statement_timeout = '90s';

-- ---------------------------------------------------------------------
-- 5. 활동 로그 + 관리자 권한
--    관리자(admin_users)만 로그 조회 가능. 첫 관리자는 아래 insert 의 이메일 (수정 가능)
-- ---------------------------------------------------------------------
create table if not exists public.admin_users (
  email text primary key,
  added_by text, added_at timestamptz not null default now()
);
insert into public.admin_users (email, added_by) values ('jisoo.h@ksautoplan.com', 'setup')
on conflict do nothing;

create table if not exists public.activity_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor text,                -- 로그인 이메일 (DB가 JWT에서 자동 기입)
  action text not null,      -- login, logout, password_change, upload, batch_toggle, insert/update/delete, agg_refresh
  target text,               -- 테이블명 또는 대상
  target_key text,           -- 대상 키 (매체명, 차량명, 일자|매체, 배치# 등)
  detail jsonb
);
create index if not exists activity_log_at_idx on public.activity_log (at desc);
create index if not exists activity_log_actor_idx on public.activity_log (actor, at desc);

create or replace function public.fn_current_email() returns text
language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'email', '')
$$;
create or replace function public.fn_is_admin() returns boolean
language sql stable as $$
  select exists (select 1 from public.admin_users where email = public.fn_current_email())
$$;

-- 로그 행의 actor/at 는 서버가 강제 (클라이언트 값 무시)
create or replace function public.trg_log_stamp() returns trigger
language plpgsql as $$
begin
  new.actor := coalesce(public.fn_current_email(), new.actor, 'system');
  new.at := now();
  return new;
end $$;
drop trigger if exists activity_log_stamp on public.activity_log;
create trigger activity_log_stamp before insert on public.activity_log
for each row execute function public.trg_log_stamp();

-- 데이터 변경 자동 기록 (마스터·광고비·배치)
create or replace function public.trg_log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; d jsonb; o jsonb; n jsonb; act text;
begin
  o := case when TG_OP <> 'INSERT' then to_jsonb(old) - 'updated_at' else null end;
  n := case when TG_OP <> 'DELETE' then to_jsonb(new) - 'updated_at' else null end;
  if TG_OP = 'UPDATE' then
    select coalesce(jsonb_object_agg(key, jsonb_build_object('old', o->key, 'new', n->key)), '{}'::jsonb) into d
    from jsonb_each(n) where o->key is distinct from n->key;
    if d = '{}'::jsonb then return null; end if;   -- 실제 변경 없음
  else d := coalesce(n, o); end if;
  k := case TG_TABLE_NAME
         when 'media_map' then coalesce(n->>'media_raw', o->>'media_raw')
         when 'car_map'   then coalesce(n->>'car_raw',   o->>'car_raw')
         when 'ad_spend'  then coalesce(n->>'spend_date', o->>'spend_date') || ' | ' || coalesce(n->>'brand', o->>'brand') || ' | ' || coalesce(n->>'channel', o->>'channel')
         when 'upload_batches' then '#' || coalesce(n->>'id', o->>'id') || ' ' || coalesce(n->>'kind', o->>'kind') || ' ' || coalesce(n->>'filename', o->>'filename', '')
         when 'admin_users' then coalesce(n->>'email', o->>'email')
         else null end;
  act := case when TG_TABLE_NAME = 'upload_batches' and TG_OP = 'INSERT' then 'upload'
              when TG_TABLE_NAME = 'upload_batches' and TG_OP = 'UPDATE' and (d ? 'is_active') then 'batch_toggle'
              else lower(TG_OP) end;
  insert into public.activity_log (actor, action, target, target_key, detail)
  values (public.fn_current_email(), act, TG_TABLE_NAME, k, d);
  return null;
end $$;
do $$
declare t text;
begin
  foreach t in array array['media_map','car_map','ad_spend','upload_batches','admin_users'] loop
    execute format('drop trigger if exists %I_log on public.%I', t, t);
    execute format('create trigger %I_log after insert or update or delete on public.%I for each row execute function public.trg_log_change()', t, t);
  end loop;
end $$;

-- 조회용 (관리자만; RLS 로 보호)
create or replace function public.fn_activity_log(p_from timestamptz, p_to timestamptz, p_actor text, p_action text, p_limit int)
returns jsonb language sql stable as $$
  with t as (
    select id, at, actor, action, target, target_key, detail
    from public.activity_log
    where at >= p_from and at < p_to
      and (p_actor is null or p_actor = '' or actor ilike '%' || p_actor || '%')
      and (p_action is null or p_action = '' or action = p_action)
    order by at desc limit greatest(1, least(p_limit, 5000)))
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

alter table public.admin_users  enable row level security;
alter table public.activity_log enable row level security;
drop policy if exists admin_users_read   on public.admin_users;
drop policy if exists admin_users_write  on public.admin_users;
drop policy if exists log_read           on public.activity_log;
drop policy if exists log_insert         on public.activity_log;
create policy admin_users_read  on public.admin_users  for select to authenticated using (true);
create policy admin_users_write on public.admin_users  for all    to authenticated using (public.fn_is_admin()) with check (public.fn_is_admin());
create policy log_read   on public.activity_log for select to authenticated using (public.fn_is_admin());
create policy log_insert on public.activity_log for insert to authenticated with check (true);
grant select, insert on public.activity_log to authenticated;
grant all on public.admin_users to authenticated;
grant usage, select on sequence public.activity_log_id_seq to authenticated;


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

-- 매체 × 기간 : DB수, 순DB수, 계약수, 매출(=계약마진 합), 차량가 합계, 광고비
create or replace function public.fn_media_period(p_from date, p_to date, p_grain text, p_basis text)
returns jsonb language sql stable as $$
with inq as (
  select public.fn_period(p_grain, a.inq_date, p_from) as period,
         coalesce(m.media_std, a.media) as media_std,
         sum(a.db_count)::bigint as db_count,
         sum(a.net_db)::bigint   as net_db,
         sum(a.ip_db)::bigint    as ip_db,
         sum(a.both_db)::bigint  as both_db
  from public.agg_inquiry_media a
  left join public.media_map m on m.media_raw = a.media
  where a.inq_date between p_from and p_to
  group by 1,2),
sal as (
  select public.fn_period(p_grain, case when p_basis='inquiry' then inquiry_date else contract_date end, p_from) as period,
         media_std,
         count(*) as contracts,
         sum(coalesce(margin,0))    as revenue,        -- 매출 = 계약마진 합계
         sum(coalesce(car_price,0)) as car_price_sum   -- 참고: 차량가격 합계
  from public.v_sales
  where is_active and media_matched
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
  group by 1,2),
keys as (
  select period, media_std from inq union
  select period, media_std from sal),
mm as (
  select distinct on (media_std) media_std, media_type, platform, brand
  from public.media_map order by media_std, updated_at desc),
t as (
  select k.period, k.media_std,
         coalesce(mm.media_type,'미분류') as media_type, mm.platform, mm.brand,
         coalesce(inq.db_count,0)  as db_count,
         coalesce(inq.net_db,0)    as net_db,
         coalesce(inq.ip_db,0)     as ip_db,
         coalesce(inq.both_db,0)   as both_db,
         coalesce(sal.contracts,0) as contracts,
         coalesce(sal.revenue,0)       as revenue,
         coalesce(sal.car_price_sum,0) as car_price_sum
  from keys k
  left join inq using (period, media_std)
  left join sal using (period, media_std)
  left join mm  on mm.media_std = k.media_std
  order by k.period, k.media_std)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 광고비 × 기간 : 브랜드 × 채널
create or replace function public.fn_spend_period(p_from date, p_to date, p_grain text)
returns jsonb language sql stable as $$
  with t as (
    select public.fn_period(p_grain, spend_date, p_from) as period, brand, channel,
           sum(cost) as cost, sum(impressions) as impressions, sum(clicks) as clicks
    from public.ad_spend where spend_date between p_from and p_to group by 1,2,3 order by 1,2,3)
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 차량(표준모델) 기준 : 문의수, 순DB, 계약수, 매출  (p_limit: 문의/계약 상위 N개씩만, null=전체)
drop function if exists public.fn_car_summary(date, date, text);
drop function if exists public.fn_car_summary(date, date, text, int);
create or replace function public.fn_car_summary(p_from date, p_to date, p_basis text, p_limit int default null, p_brands text[] default null)
returns jsonb language sql stable as $$
with inq0 as (
  select coalesce(c.model_std, a.car_name) as model_std, c.brand as car_brand, a.db_count, a.net_db, a.ip_db, a.both_db
  from public.agg_inquiry_car a
  left join public.car_map c on c.car_raw = a.car_name
  left join public.media_map m on m.media_raw = a.media
  where a.inq_date between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(m.brand, m.media_std, a.media) = any(p_brands))),
inq as (
  select model_std, mode() within group (order by car_brand) as car_brand,
         sum(db_count)::bigint as db_count, sum(net_db)::bigint as net_db,
         sum(ip_db)::bigint as ip_db, sum(both_db)::bigint as both_db
  from inq0 group by 1),
sal as (
  select model_std, mode() within group (order by car_brand) as car_brand,
         count(*) as contracts, sum(coalesce(margin,0)) as revenue, sum(coalesce(car_price,0)) as car_price_sum
  from public.v_sales
  where is_active and media_type not in ('경비')
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))
  group by 1),
keys as (select model_std from inq union select model_std from sal),
t0 as (
  select k.model_std, coalesce(inq.car_brand, sal.car_brand) as car_brand,
         coalesce(inq.db_count,0) db_count, coalesce(inq.net_db,0) net_db,
         coalesce(inq.ip_db,0) ip_db, coalesce(inq.both_db,0) both_db,
         coalesce(sal.contracts,0) contracts, coalesce(sal.revenue,0) revenue, coalesce(sal.car_price_sum,0) car_price_sum
  from keys k left join inq using (model_std) left join sal using (model_std)),
t as (
  select * from t0 where p_limit is null
  union
  select * from (select * from t0 order by db_count desc limit coalesce(p_limit,0)) a
  union
  select * from (select * from t0 order by contracts desc limit coalesce(p_limit,0)) b)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 리드타임 : p_dim = 'all' | 'media' | 'media_brand' | 'platform' | 'car' | 'car_brand'
drop function if exists public.fn_leadtime(date, date, text, text);
create or replace function public.fn_leadtime(p_from date, p_to date, p_basis text, p_dim text, p_brands text[] default null)
returns jsonb language sql stable as $$
with base as (
  select case p_dim when 'media' then media_std when 'media_brand' then coalesce(media_brand, media_std) when 'platform' then platform
                    when 'car' then model_std   when 'car_brand' then car_brand else '전체' end as dim_value,
         lead_days
  from public.v_sales
  where is_active and media_matched and lead_flag = '정상' and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))),
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

-- 리드타임 기간별 추이 (p_grain: day|week|month|year)
create or replace function public.fn_leadtime_trend(p_from date, p_to date, p_basis text, p_grain text, p_brands text[] default null)
returns jsonb language sql stable as $$
with base as (
  select public.fn_period(p_grain, case when p_basis='inquiry' then inquiry_date else contract_date end, p_from) as period, lead_days
  from public.v_sales
  where is_active and media_matched and lead_flag = '정상' and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))),
t as (
  select period, count(*) as n,
         round(avg(lead_days)::numeric,1) as avg_days,
         percentile_cont(0.5) within group (order by lead_days) as median_days,
         percentile_cont(0.25) within group (order by lead_days) as p25,
         percentile_cont(0.75) within group (order by lead_days) as p75,
         round(100.0 * count(*) filter (where lead_days <= 7) / count(*), 1) as within7_pct
  from base group by 1 order by 1)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;

-- 리드타임 분포(구간) + 제외 사유 집계
drop function if exists public.fn_leadtime_dist(date, date, text);
create or replace function public.fn_leadtime_dist(p_from date, p_to date, p_basis text, p_brands text[] default null)
returns jsonb language sql stable as $$
with base as (
  select lead_days, lead_flag from public.v_sales
  where is_active and media_matched and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))),
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


-- 데이터 범위/상태 요약 (대시보드 상단)
create or replace function public.fn_data_status()
returns jsonb language sql stable as $$
select jsonb_build_object(
  'inquiries',        (select coalesce(sum(db_count),0) from public.agg_inquiry_media),
  'inquiry_min',      (select min(inq_date) from public.agg_inquiry_media),
  'inquiry_max',      (select max(inq_date) from public.agg_inquiry_media),
  'sales_active',     (select count(*) from public.v_sales where is_active),
  'sales_unmatched',  (select count(*) from public.v_sales_unmatched),
  'contract_min',     (select min(contract_date) from public.v_sales where is_active),
  'contract_max',     (select max(contract_date) from public.v_sales where is_active),
  'media_unclassified',(select count(*) from public.media_map where media_type='미분류'),
  'car_unmapped',     (select count(*) from public.car_map where brand is null),
  'ad_spend_days',    (select count(distinct spend_date) from public.ad_spend),
  'ad_spend_max',     (select max(spend_date) from public.ad_spend),
  'agg_refreshed_at', (select v from public.agg_meta where k='refreshed_at'),
  'agg_rows',         (select count(*) from public.agg_inquiry_media),
  'agg_car_rows',     (select count(*) from public.agg_inquiry_car),
  'ip_pending',       (select count(*) from public.inquiries where ip_hash is null and (raw ? '고객IP')),
  'is_admin',         public.fn_is_admin(),
  'ip_dups',          (select coalesce(sum(db_count - ip_db),0) from public.agg_inquiry_media),
  'crm_dups',         (select coalesce(sum(db_count - net_db),0) from public.agg_inquiry_media),
  'brands',           (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from (select distinct coalesce(brand, media_std) as x from public.media_map) t)
)
$$;

-- 대시보드 일괄 조회 (왕복 1회)
drop function if exists public.fn_dashboard(date, date, text, text);
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

-- 광고비 API 연동 (인입 DB 원장 → ad_spend)
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


-- ---------------------------------------------------------------------
-- 4. RLS : 로그인(authenticated) 사용자만 전체 권한, 익명 차단
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['upload_batches','inquiries','sales','media_map','car_map','ad_spend','agg_inquiry_media','agg_inquiry_car','agg_meta'] loop
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

-- ---------------------------------------------------------------------
-- 6. 마무리: 집계 테이블이 비어 있으면(구조 변경 직후 등) 자동 갱신
-- ---------------------------------------------------------------------
do $$ begin
  if exists (select 1 from public.inquiries limit 1)
     and (not exists (select 1 from public.agg_inquiry_media limit 1) or not exists (select 1 from public.agg_inquiry_car limit 1)) then
    perform public.fn_refresh_agg();
  end if;
end $$;

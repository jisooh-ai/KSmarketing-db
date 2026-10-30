-- 채널 단위 ROAS: 유입링크(inbound_link) → 광고채널 매핑, 브랜드×채널 집계
-- 1) 유입링크 정규화 키: '[M] google' → 'M:google', '[AD] clickchoice' → 'AD:clickchoice', '[SITE] naver' → 'SITE:naver',
--    '[APP] Naver' 만 있으면 'APP:naver', 태그 없으면 소문자 원문(도메인 등). 빈값은 ''.
create or replace function public.fn_link_key(p text) returns text language sql immutable as $$
  select case
    when p is null or btrim(p) = '' then ''
    when p ~* '\[M\]\s*\S+'    then 'M:'    || lower((regexp_match(p, '\[M\]\s*(\S+)',    'i'))[1])
    when p ~* '\[AD\]\s*\S+'   then 'AD:'   || lower((regexp_match(p, '\[AD\]\s*(\S+)',   'i'))[1])
    when p ~* '\[SITE\]\s*\S+' then 'SITE:' || lower((regexp_match(p, '\[SITE\]\s*(\S+)', 'i'))[1])
    when p ~* '\[APP\]\s*\S+'  then 'APP:'  || lower((regexp_match(p, '\[APP\]\s*(\S+)',  'i'))[1])
    else lower(btrim(p)) end
$$;

-- 2) 매핑표: 링크 키 → 채널 (광고비 채널 12종 + '자연유입' + '내부·직접' + '(미분류)'), 매핑 탭에서 편집
create table if not exists public.channel_map (
  link_key   text primary key,
  channel    text not null default '(미분류)',
  note       text,
  mapped_by  text default 'seed',
  updated_at timestamptz not null default now()
);
-- 링크가 비었을 때 매체 플랫폼으로 채널 추정
create or replace function public.fn_channel_fallback(p_platform text, p_media text) returns text language sql immutable as $$
  select case
    when p_platform = '메타' or p_media ilike '메타-%' then '메타 광고'
    when p_platform = '당근' or p_media ilike '당근-%' then '당근 광고'
    when p_platform = '틱톡' or p_media ilike '%틱톡%' then '틱톡 광고'
    when p_platform = '플친' or p_media ilike '플친-%' then '카카오 친구톡'
    when p_platform = '대표전화' or p_media ilike '대표전화-%' then '전화·오프라인'
    when p_platform = '사이트' or p_media ilike '사이트-%' then '사이트(링크 없음)'
    else '(미분류)' end
$$;

-- 3) 집계 테이블: 일자 × 매체 × 링크키
create table if not exists public.agg_inquiry_channel (
  inq_date date not null, media text not null default '(없음)', link_key text not null default '',
  db_count integer not null, net_db integer not null, ip_db integer not null default 0, both_db integer not null default 0,
  primary key (inq_date, media, link_key)
);
alter table public.agg_inquiry_channel enable row level security;
drop policy if exists auth_all on public.agg_inquiry_channel;
create policy auth_all on public.agg_inquiry_channel for all to authenticated using (true) with check (true);
alter table public.channel_map enable row level security;
drop policy if exists auth_all on public.channel_map;
create policy auth_all on public.channel_map for all to authenticated using (true) with check (true);
grant all on public.agg_inquiry_channel, public.channel_map to authenticated;

-- 4) fn_refresh_agg 에 채널 집계 추가 (기존 본문 유지 + 한 단락 추가)
create or replace function public.fn_refresh_agg() returns jsonb
language plpgsql as $$
declare n1 int; n2 int; n3 int; n4 int; pending int;
begin
  select count(*) into pending from public.inquiries where ip_hash is null and (raw ? '고객IP');
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
  truncate public.agg_inquiry_channel;
  insert into public.agg_inquiry_channel
    select inq_date, coalesce(media,'(없음)'), public.fn_link_key(inbound_link), count(*), count(*) filter (where is_duplicate='N'),
           count(*) filter (where not is_ip_dup), count(*) filter (where is_duplicate='N' and not is_ip_dup)
    from public.inquiries where inq_date is not null group by 1,2,3;
  get diagnostics n4 = row_count;
  -- 새로 나타난 링크 키는 매핑표에 (미분류) 로 자동 등록
  insert into public.channel_map (link_key, channel, mapped_by)
    select distinct link_key, '(미분류)', 'auto' from public.agg_inquiry_channel where link_key <> ''
    on conflict (link_key) do nothing;
  insert into public.agg_meta values ('refreshed_at', now()::text)
    on conflict (k) do update set v = excluded.v;
  analyze public.inquiries; analyze public.sales; analyze public.agg_inquiry_media; analyze public.agg_inquiry_car; analyze public.agg_inquiry_channel;
  insert into public.activity_log (action, target, detail) values ('agg_refresh', 'agg', jsonb_build_object('media_rows', n1, 'car_rows', n2, 'channel_rows', n4, 'ip_dup_changed', n3));
  return jsonb_build_object('media_rows', n1, 'car_rows', n2, 'channel_rows', n4, 'ip_dup_changed', n3, 'ip_pending', pending);
end $$;

-- 5) 매핑 작업용 뷰: 링크 키별 건수
create or replace view public.v_channel_counts with (security_invoker = true) as
select c.link_key, c.channel, c.note, c.mapped_by,
       coalesce(i.n,0) as inquiry_count, coalesce(s.n,0) as sales_count,
       i.sample
from public.channel_map c
left join (select link_key, sum(db_count) n, (array_agg(distinct media order by media))[1:3] as sample from public.agg_inquiry_channel group by 1) i on i.link_key = c.link_key
left join (select public.fn_link_key(inbound_link) link_key, count(*) n from public.sales group by 1) s on s.link_key = c.link_key;

-- 6) 브랜드 × 채널 × 기간 성과 (문의·계약·매출 + 광고비). 수수료 채널은 기본 채널에 합산.
drop function if exists public.fn_channel_period(date, date, text, text, text[]);
create or replace function public.fn_channel_period(p_from date, p_to date, p_grain text, p_basis text, p_brands text[] default null)
returns jsonb language sql stable as $$
with inq as (
  select public.fn_period(p_grain, a.inq_date, p_from) as period,
         coalesce(m.brand, m.media_std, a.media) as brand,
         case when a.link_key = '' then public.fn_channel_fallback(m.platform, a.media) else coalesce(c.channel, '(미분류)') end as channel,
         sum(a.db_count)::bigint db_count, sum(a.net_db)::bigint net_db, sum(a.ip_db)::bigint ip_db, sum(a.both_db)::bigint both_db
  from public.agg_inquiry_channel a
  left join public.media_map m on m.media_raw = a.media
  left join public.channel_map c on c.link_key = a.link_key
  where a.inq_date between p_from and p_to and coalesce(m.media_type,'미분류') <> '경비'
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(m.brand, m.media_std, a.media) = any(p_brands))
  group by 1,2,3),
sal as (
  select public.fn_period(p_grain, case when p_basis='inquiry' then inquiry_date else contract_date end, p_from) as period,
         coalesce(media_brand, media_std) as brand,
         case when public.fn_link_key(inbound_link) = '' then public.fn_channel_fallback(platform, media) else coalesce(c.channel, '(미분류)') end as channel,
         count(*) contracts, sum(coalesce(margin,0)) revenue
  from public.v_sales s
  left join public.channel_map c on c.link_key = public.fn_link_key(s.inbound_link)
  where is_active and media_matched and media_type <> '경비'
    and (case when p_basis='inquiry' then inquiry_date else contract_date end) between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or coalesce(media_brand, media_std) = any(p_brands))
  group by 1,2,3),
sp as (
  select public.fn_period(p_grain, spend_date, p_from) as period, brand,
         case channel when '구글 애즈 수수료' then '구글 애즈' when '메타 광고 수수료' then '메타 광고' when '블로그 인플루언서 수수료' then '블로그 인플루언서' else channel end as channel,
         sum(cost) cost, sum(cost) filter (where channel like '%수수료') fee
  from public.ad_spend where spend_date between p_from and p_to
    and (p_brands is null or cardinality(p_brands)=0 or brand = any(p_brands))
  group by 1,2,3),
keys as (select period, brand, channel from inq union select period, brand, channel from sal union select period, brand, channel from sp),
t as (
  select k.period, k.brand, k.channel,
         coalesce(i.db_count,0) db_count, coalesce(i.net_db,0) net_db, coalesce(i.ip_db,0) ip_db, coalesce(i.both_db,0) both_db,
         coalesce(s.contracts,0) contracts, coalesce(s.revenue,0) revenue,
         coalesce(p.cost,0) cost, coalesce(p.fee,0) fee
  from keys k left join inq i using (period, brand, channel) left join sal s using (period, brand, channel) left join sp p using (period, brand, channel)
  order by k.period, k.brand, coalesce(p.cost,0) desc)
select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from t
$$;
grant execute on function public.fn_link_key(text), public.fn_channel_fallback(text, text), public.fn_channel_period(date, date, text, text, text[]) to authenticated;

-- 7) 매핑 시드 (키 → 채널). 이미 있는 키는 건드리지 않음(사용자 편집 보존)
insert into public.channel_map (link_key, channel, note) values
  ('AD:clickchoice','네이버 파워링크','네이버 검색광고'),
  ('M:naver','네이버 파워링크',null), ('APP:naver','자연유입','네이버 앱(태그 없음)'),
  ('M:gfa','네이버 GFA',null),
  ('M:google','구글 애즈',null), ('AD:google','구글 애즈',null), ('googleads.g.doubleclick.net','구글 애즈',null),
  ('M:kakao','카카오 모먼트',null), ('kakao','카카오 모먼트',null),
  ('M:kakaotalk','카카오 친구톡',null), ('APP:kakaotalk','카카오 친구톡',null), ('plf','카카오 친구톡','플친'), ('plf_tik','카카오 친구톡','플친'),
  ('M:daangn','당근 광고',null), ('karrot','당근 광고',null), ('carrot','당근 광고',null),
  ('M:meta','메타 광고',null), ('AD:meta','메타 광고',null), ('ig','메타 광고','인스타그램'), ('fb','메타 광고','페이스북'),
  ('M:instagram','메타 광고',null), ('M:ig','메타 광고',null), ('lm.facebook.com','메타 광고',null), ('l.facebook.com','메타 광고',null), ('m.facebook.com','메타 광고',null), ('l.instagram.com','메타 광고',null),
  ('M:tiktok','틱톡 광고',null), ('tiktok','틱톡 광고',null), ('www.tiktok.com','틱톡 광고',null), ('encarz_tik','틱톡 광고','엔카 틱톡 소재'),
  ('M:naverblog','블로그 인플루언서',null), ('SITE:naverblog','블로그 인플루언서',null),
  ('M:youtube','유튜브 PPL',null), ('www.youtube.com','유튜브 PPL',null), ('youtube.com','유튜브 PPL',null),
  ('M:encar','기타','엔카'), ('encarz','기타','엔카'), ('encarz_g','기타','엔카'), ('M:danawa','기타','다나와'), ('ofw.adison.co','기타','애디슨 오퍼월'), ('taboola3','기타','타불라'), ('M:nosp','기타',null),
  ('SITE:naver','자연유입',null), ('SITE:google','자연유입',null), ('SITE:daum','자연유입',null), ('SITE:bing','자연유입',null), ('syndicatedsearch.goog','자연유입',null), ('chatgpt.com','자연유입',null),
  ('mini3','내부·직접','테스트·예외 IP'), ('M:mini1','내부·직접',null), ('M:mini5','내부·직접',null), ('m.xn--v92b25a2zv.com','내부·직접','자사 도메인'), ('www.ksautoplan.com','내부·직접',null), ('hub.ksautoplan.com','내부·직접',null), ('M:ksautoplan2022','내부·직접',null)
on conflict (link_key) do nothing;

-- 8) 대시보드 통합 호출에 채널 성과 포함
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
    'LQT', public.fn_leadtime_cohort(p_from, p_to, 'all', 'month', p_brands),
    'CH',  public.fn_channel_period(p_from, p_to, 'all', p_basis, p_brands),
    'CHT', public.fn_channel_period(p_from, p_to, 'month', p_basis, p_brands)
  )
$$;

-- 9) 채널 집계 생성은 SQL Editor 시간 제한 때문에 여기서 하지 않음 → 실행 후 웹 설정 탭 [집계 갱신] (또는 별도로 select public.fn_refresh_agg();)
notify pgrst, 'reload schema';

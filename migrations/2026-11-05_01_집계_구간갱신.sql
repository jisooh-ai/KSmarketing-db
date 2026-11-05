-- 집계 갱신을 기간 단위로 쪼갬 (전체 갱신이 Supabase 무료 플랜 90초 제한을 넘겨 롤백되던 문제)
-- fn_refresh_agg_range(p_from, p_to): 해당 기간의 IP 중복 플래그·집계 3종만 다시 만듦. 화면은 월 단위로 반복 호출.
create or replace function public.fn_refresh_agg_range(p_from date, p_to date) returns jsonb
language plpgsql as $$
declare n1 int; n2 int; n3 int; n4 int; t0 timestamptz := clock_timestamp();
begin
  -- IP 중복: 기간 시작 7일 전부터의 행만 다시 판정 (같은 IP 의 이전 행과 비교하므로 파티션 전체를 읽되 갱신은 기간 내로 제한)
  update public.inquiries a set is_ip_dup = coalesce(d.dup,false)
  from (select inquiry_no,
               (lag(inquired_at) over (partition by ip_hash order by inquired_at, inquiry_no) >= inquired_at - interval '7 days') as dup
        from public.inquiries
        where ip_hash is not null
          and ip_hash in (select distinct ip_hash from public.inquiries
                          where ip_hash is not null and inquired_at >= (p_from - 7)::timestamptz and inquired_at < (p_to + 1)::timestamptz)) d
  where a.inquiry_no = d.inquiry_no
    and a.inquired_at >= (p_from - 7)::timestamptz and a.inquired_at < (p_to + 1)::timestamptz
    and a.is_ip_dup is distinct from coalesce(d.dup,false);
  get diagnostics n3 = row_count;

  delete from public.agg_inquiry_media   where inq_date between p_from and p_to;
  insert into public.agg_inquiry_media
    select inq_date, coalesce(media,'(없음)'), count(*), count(*) filter (where is_duplicate='N'),
           count(*) filter (where not is_ip_dup), count(*) filter (where is_duplicate='N' and not is_ip_dup)
    from public.inquiries where inq_date between p_from and p_to group by 1,2;
  get diagnostics n1 = row_count;

  delete from public.agg_inquiry_car     where inq_date between p_from and p_to;
  insert into public.agg_inquiry_car
    select inq_date, coalesce(media,'(없음)'), coalesce(car_name,'(없음)'), count(*), count(*) filter (where is_duplicate='N'),
           count(*) filter (where not is_ip_dup), count(*) filter (where is_duplicate='N' and not is_ip_dup)
    from public.inquiries where inq_date between p_from and p_to group by 1,2,3;
  get diagnostics n2 = row_count;

  delete from public.agg_inquiry_channel where inq_date between p_from and p_to;
  insert into public.agg_inquiry_channel
    select inq_date, coalesce(media,'(없음)'), public.fn_link_key(inbound_link), count(*), count(*) filter (where is_duplicate='N'),
           count(*) filter (where not is_ip_dup), count(*) filter (where is_duplicate='N' and not is_ip_dup)
    from public.inquiries where inq_date between p_from and p_to group by 1,2,3;
  get diagnostics n4 = row_count;

  insert into public.channel_map (link_key, channel, mapped_by)
    select distinct link_key, '(미분류)', 'auto' from public.agg_inquiry_channel
    where inq_date between p_from and p_to and link_key <> ''
    on conflict (link_key) do nothing;

  insert into public.agg_meta values ('refreshed_at', now()::text) on conflict (k) do update set v = excluded.v;
  insert into public.activity_log (action, target, detail)
    values ('agg_refresh_range', 'agg', jsonb_build_object('from', p_from, 'to', p_to, 'media_rows', n1, 'car_rows', n2, 'channel_rows', n4, 'ip_dup_changed', n3, 'ms', round(extract(epoch from clock_timestamp()-t0)*1000)));
  return jsonb_build_object('from', p_from, 'to', p_to, 'media_rows', n1, 'car_rows', n2, 'channel_rows', n4, 'ip_dup_changed', n3,
                            'ms', round(extract(epoch from clock_timestamp()-t0)*1000));
end $$;
grant execute on function public.fn_refresh_agg_range(date, date) to authenticated;

-- 갱신해야 할 월 목록 (원본에 있는 월 전부). 화면이 이 목록을 돌며 fn_refresh_agg_range 를 호출
create or replace function public.fn_agg_months() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(m order by m), '[]'::jsonb)
  from (select distinct date_trunc('month', inq_date)::date as m from public.inquiries where inq_date is not null) x
$$;
grant execute on function public.fn_agg_months() to authenticated;

-- 상태 요약에 집계 최신 월 / 원본 최신 월을 함께 노출 (어긋나면 화면에서 경고)
-- (fn_data_status 는 기존 그대로 두고, 화면에서 fn_agg_months 와 status.inquiry_max 를 비교)
notify pgrst, 'reload schema';

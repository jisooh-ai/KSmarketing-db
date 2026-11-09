-- 매체 마스터(매핑 탭)에서 매체별 주요 유입키워드·유입링크를 보여주기 위한 조회 함수
-- 반환: { "<매체 원문>": [ {"k": 키워드, "l": 링크, "n": 건수}, ... 상위 6 ] }
create or replace function public.fn_media_keywords(p_medias text[]) returns jsonb language sql stable as $$
  with x as (
    select media, coalesce(nullif(trim(inbound_keyword),''),'') k, coalesce(nullif(trim(inbound_link),''),'') l, count(*) n
    from public.inquiries
    where media = any(p_medias)
    group by 1,2,3
  ), r as (
    select *, row_number() over (partition by media order by n desc) rn from x
  )
  select coalesce(jsonb_object_agg(media, items), '{}'::jsonb)
  from (select media, jsonb_agg(jsonb_build_object('k',k,'l',l,'n',n) order by n desc) items
        from r where rn <= 6 group by media) y
$$;
grant execute on function public.fn_media_keywords(text[]) to authenticated;
notify pgrst, 'reload schema';

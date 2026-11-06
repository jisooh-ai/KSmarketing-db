-- 엔카 매체를 브랜드 KS오토플랜에 귀속 (수기 ROAS 시트 기준: 엔카 광고비는 KS오토플랜 '기타' 열에 기입)
-- 1) 매핑: 브랜드 = KS오토플랜, 유형 = 마케팅 유지, 플랫폼 = 엔카
update public.media_map set brand = 'KS오토플랜', platform = '엔카', media_type = '마케팅'
 where media_raw = '엔카';

-- 2) 링크 없는 엔카 유입을 '기타' 채널로 추정 → KS오토플랜 × 기타 행에 엔카 광고비·계약이 같은 줄에 놓임
create or replace function public.fn_channel_fallback(p_platform text, p_media text) returns text language sql immutable as $$
  select case
    when p_platform = '메타' or p_media ilike '메타-%' then '메타 광고'
    when p_platform = '당근' or p_media ilike '당근-%' then '당근 광고'
    when p_platform = '틱톡' or p_media ilike '%틱톡%' then '틱톡 광고'
    when p_platform = '플친' or p_media ilike '플친-%' then '카카오 친구톡'
    when p_platform = '대표전화' or p_media ilike '대표전화-%' then '전화·오프라인'
    when p_platform = '사이트' or p_media ilike '사이트-%' then '사이트(링크 없음)'
    when p_platform = '엔카' or p_media = '엔카' then '기타'
    else '(미분류)' end
$$;
notify pgrst, 'reload schema';

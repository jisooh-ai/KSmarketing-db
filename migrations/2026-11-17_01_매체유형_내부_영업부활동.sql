-- 매체유형 '내부' → '영업부 활동' 으로 이름 변경 (값 자체를 바꿈. 화면 index.html 의 유형 목록과 함께 변경)
alter table public.media_map drop constraint if exists media_map_media_type_check;
update public.media_map set media_type = '영업부 활동', updated_at = now() where media_type = '내부';
alter table public.media_map add constraint media_map_media_type_check check (media_type in ('마케팅','영업부 활동','경비','미분류'));
-- 확인: select media_type, count(*) from public.media_map group by 1;

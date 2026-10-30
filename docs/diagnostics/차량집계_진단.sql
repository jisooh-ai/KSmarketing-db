-- 차량 집계 진단 (Supabase SQL Editor 에 붙여넣고 Run)
-- 결과 1행(jsonb). 이 결과를 그대로 복사해 주시면 원인을 바로 판정합니다.
select jsonb_pretty(jsonb_build_object(
  'agg_car_rows',        (select count(*) from public.agg_inquiry_car),
  'agg_car_db_sum',      (select coalesce(sum(db_count),0) from public.agg_inquiry_car),
  'agg_car_months',      (select jsonb_object_agg(m, n) from (select to_char(inq_date,'YYYY-MM') m, sum(db_count) n from public.agg_inquiry_car group by 1 order by 1) x),
  'agg_media_db_sum',    (select coalesce(sum(db_count),0) from public.agg_inquiry_media),
  'refreshed_at',        (select v from public.agg_meta where k='refreshed_at'),
  'car_map_rows',        (select count(*) from public.car_map),
  'car_map_blank_model', (select count(*) from public.car_map where model_std is null or btrim(model_std) in ('','-','(없음)')),
  'inq_car_top5_raw',    (select jsonb_agg(jsonb_build_object('car',car_name,'db',n)) from (select car_name, sum(db_count) n from public.agg_inquiry_car group by 1 order by 2 desc limit 5) x),
  'fn_car_top5',         (select jsonb_agg(e) from (select e from jsonb_array_elements(public.fn_car_summary('2026-01-01','2026-10-28','contract',300,null)) e order by (e->>'db_count')::int desc limit 5) x),
  'sales_car_top5',      (select jsonb_agg(jsonb_build_object('model',model_std,'n',n)) from (select model_std, count(*) n from public.v_sales where is_active group by 1 order by 2 desc limit 5) x)
));

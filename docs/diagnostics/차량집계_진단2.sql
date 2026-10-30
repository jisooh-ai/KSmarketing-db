-- 차량 집계 진단 2 : 대시보드가 실제로 받는 C 데이터 확인
with d as (select public.fn_dashboard('2026-01-01','2026-10-28','month','contract',null) as j)
select jsonb_pretty(jsonb_build_object(
  'C_len',      (select jsonb_array_length(j->'C') from d),
  'C_first3',   (select jsonb_agg(e) from (select e from d, jsonb_array_elements(j->'C') e limit 3) x),
  'C_top5_db',  (select jsonb_agg(e) from (select e from d, jsonb_array_elements(j->'C') e order by (e->>'db_count')::numeric desc nulls last limit 5) x),
  'C_top3_contracts', (select jsonb_agg(e) from (select e from d, jsonb_array_elements(j->'C') e order by (e->>'contracts')::numeric desc nulls last limit 3) x),
  'status_agg', (select j->'status'->'agg_car_rows' from d),
  'fn_dashboard_C_line', (select substring(pg_get_functiondef('public.fn_dashboard'::regproc) from '''C''[^\n]*')),
  'fn_car_summary_args', (select pg_get_function_arguments('public.fn_car_summary'::regproc))
));

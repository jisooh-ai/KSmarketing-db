-- 10월 업로드 후 1~9월 데이터 확인 (한 번에 실행)
select jsonb_pretty(jsonb_build_object(
  'inq_by_month',      (select jsonb_object_agg(m, n) from (select coalesce(to_char(inq_date,'YYYY-MM'),'(없음)') m, count(*) n from public.inquiries group by 1 order by 1) x),
  'inq_by_batch',      (select jsonb_object_agg(batch_id, n) from (select coalesce(batch_id::text,'(없음)') batch_id, count(*) n from public.inquiries group by 1 order by 1) x),
  'inq_total',         (select count(*) from public.inquiries),
  'inq_null_date',     (select count(*) from public.inquiries where inq_date is null),
  'agg_by_month',      (select jsonb_object_agg(m, n) from (select to_char(inq_date,'YYYY-MM') m, sum(db_count) n from public.agg_inquiry_media group by 1 order by 1) x),
  'agg_refreshed_at',  (select v from public.agg_meta where k='refreshed_at'),
  'sales_by_batch',    (select jsonb_agg(jsonb_build_object('batch',batch_id,'active',is_active,'n',n,'min',mn,'max',mx)) from (select s.batch_id, b.is_active, count(*) n, min(contract_date) mn, max(contract_date) mx from public.sales s join public.upload_batches b on b.id=s.batch_id group by 1,2 order by 1) x),
  'sales_active_by_month', (select jsonb_object_agg(m, n) from (select coalesce(to_char(contract_date,'YYYY-MM'),'(없음)') m, count(*) n from public.v_sales where is_active group by 1 order by 1) x),
  'batches',           (select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'file',filename,'rows',row_count,'active',is_active,'at',uploaded_at)) from (select * from public.upload_batches order by id) x)
));

-- 매출 업로드 검증 때 계약일자 범위가 겹치는 기존 활성 배치를 찾아 보여주고, 업로드 후 자동 비활성화하기 위한 조회 함수
create or replace function public.fn_sales_batch_overlap(p_from date, p_to date) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'filename', b.filename, 'uploaded_at', b.uploaded_at,
                                               'rows_in_range', x.n, 'row_count', b.row_count, 'min_date', x.d0, 'max_date', x.d1) order by b.id), '[]'::jsonb)
  from public.upload_batches b
  join (select batch_id, count(*) n, min(contract_date) d0, max(contract_date) d1
        from public.sales where contract_date between p_from and p_to group by batch_id) x on x.batch_id = b.id
  where b.kind = 'sales' and b.is_active
$$;
grant execute on function public.fn_sales_batch_overlap(date, date) to authenticated;
notify pgrst, 'reload schema';

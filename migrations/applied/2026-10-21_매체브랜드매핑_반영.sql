-- 매체 브랜드 분류 적용 (사용자 기준표 2026-10-21 + 동일 브랜드명 자동 확장). supabase_setup.sql 실행 후 Run. 재실행 안전.
-- 브랜드가 정해진 매체는 유형이 '미분류'인 경우 '마케팅'으로 설정됩니다.

update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-KS오토플랜';
update public.media_map set brand='저신용', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-저신용 신차장기렌트';
update public.media_map set brand='한국', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-한국신차장기렌트카';
update public.media_map set brand='하나신차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-하나캐피탈 신차 장기렌트 리스';
update public.media_map set brand='굿모닝', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-굿모닝 장기렌트카';
update public.media_map set brand='오케이', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-오케이 장기렌트';
update public.media_map set brand='무보증', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-무보증신차장기렌트';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-KS오토플랜';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='당근-KS오토플랜';
update public.media_map set brand='한국', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-한국신차장기렌트카';
update public.media_map set brand='저신용', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-저신용 신차장기렌트';
update public.media_map set brand='KS모빌리티', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-KS모빌리티';
update public.media_map set brand='차차차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-차차차 신차장기렌트';
update public.media_map set brand='승계플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-승계플랜';
update public.media_map set brand='신차픽', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-신차픽';
update public.media_map set brand='무보증', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-무보증 신차장기렌트카';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-KS오토플랜';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='KS오토플랜-틱톡';
update public.media_map set brand='저금리', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-저금리 신차장기렌트 다이렉트';
update public.media_map set brand='신차를 다루다', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-신차를 다루다';
update public.media_map set brand='저신용', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-저신용 신차장기렌트';
update public.media_map set brand='차올라', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-차올라';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-KS오토플랜';
update public.media_map set brand='굿모닝', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-굿모닝 장기렌트카';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-KS오토리스';
update public.media_map set brand='저신용', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-저신용신차장기렌트';
update public.media_map set brand='무보증', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-무보증신차장기렌트';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-KS오토리스';
update public.media_map set brand='하나신차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-하나캐피탈 신차 장기렌트 리스';
update public.media_map set brand='한국', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-한국신차장기렌트카';
update public.media_map set brand='저금리', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-저금리 신차장기렌트';
update public.media_map set brand='한국', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-한국신차장기렌트카';
update public.media_map set brand='하나신차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-하나신차장기렌트카';
update public.media_map set brand='차끗', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-차끗';
update public.media_map set brand='굿모닝', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-굿모닝장기렌트';
update public.media_map set brand='굿모닝', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-굿모닝 장기렌트카';
update public.media_map set brand='무보증', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-무보증';
update public.media_map set brand='차올라', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-차올라';
update public.media_map set brand='롯데오토리스', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-롯데오토리스';
update public.media_map set brand='차차차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-차차차 신차장기렌트';
update public.media_map set brand='오케이', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-오케이 장기렌트';
update public.media_map set brand='승계플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-승계플랜';
update public.media_map set brand='KS모빌리티', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-KS모빌리티';
update public.media_map set brand='KS모빌리티', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-KS모빌리티';
update public.media_map set brand='쏘카', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-쏘카';
update public.media_map set brand='오케이', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-오케이 장기렌트';
update public.media_map set brand='BNK', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-BNK';
update public.media_map set brand='저금리', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='메타-저금리';
update public.media_map set brand='롯데오토리스', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-롯데오토리스';
update public.media_map set brand='차끗', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-차끗';
update public.media_map set brand='카앤캐쉬', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-카앤캐쉬';
update public.media_map set brand='저금리', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-저금리 신차장기렌트';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-KS오토리스';
update public.media_map set brand='카앤캐쉬', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-카앤캐쉬';
update public.media_map set brand='차차차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='틱톡 - 차차차';
update public.media_map set brand='차끗', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-차끗 다이렉트';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-KS오토쇼핑';
update public.media_map set brand='차끗', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-차끗';
update public.media_map set brand='무보증', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-무보증신차장기렌트';
update public.media_map set brand='차차차', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-차차차 신차장기렌트';
update public.media_map set brand='신차를 다루다', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-신차를 다루다';
update public.media_map set brand='KS오토플랜', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='사이트-KS오토플랜 유튜브 PPL';
update public.media_map set brand='차끗', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-차끗';
update public.media_map set brand='차올라', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-차올라';
update public.media_map set brand='KS모빌리티', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-KS모빌리티';
update public.media_map set brand='저신용', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-저신용 장기렌트';
update public.media_map set brand='저금리', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-저금리신차장기렌트 KS오토플랜';
update public.media_map set brand='신차를 다루다', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='대표전화-신차를 다루다';
update public.media_map set brand='신차픽', media_type=case when media_type='미분류' then '마케팅' else media_type end, updated_at=now() where media_raw='플친-신차픽';

update public.media_map set media_type='내부', updated_at=now() where media_raw='개인광고(팀)' and media_type='미분류';
update public.media_map set media_type='내부', updated_at=now() where media_raw='기존계약 고객소개' and media_type='미분류';
update public.media_map set media_type='내부', updated_at=now() where media_raw='추가계약' and media_type='미분류';
update public.media_map set media_type='내부', updated_at=now() where media_raw='지인(팀)' and media_type='미분류';
update public.media_map set media_type='내부', updated_at=now() where media_raw='기존고객소개' and media_type='미분류';
update public.media_map set media_type='내부', updated_at=now() where media_raw='지인' and media_type='미분류';

-- 경비·내부 매체는 브랜드 없음
update public.media_map set brand=null, updated_at=now() where media_type in ('경비','내부');
-- 아직 판단 전인 매체는 시드의 자동분리 브랜드 제거 (매핑 탭에서 직접 지정)
update public.media_map set brand=null, updated_at=now() where media_raw in (
  '메타-KS오토플랜 승계',
  '엔카',
  '지인(팀)',
  '개인광고(팀)',
  '메타-화물다이렉트플랜',
  '이마트팝업행사',
  '추가계약',
  'KS오토플랜-정산전용💰 (경비)',
  '사이트-KS오토플랜 승계',
  '사이트-카플래너',
  '기존고객소개',
  '하나캐피탈 다이렉트DB',
  '대전 모빌리티쇼',
  '메타-대한법인차조합',
  '기타',
  '사이트-카비교',
  'KS오토플랜-정산전용💰 (지출)',
  '메타-잔존가치',
  '메타-수입차 할인',
  '승계 기타광고',
  '플친-신차장기렌트 비밀견적',
  'KS오토플랜-정산전용💰 (지급)',
  '지인',
  '사이트-대표전화',
  '플친-노마진 신차장기렌트카',
  '사이트-렌콕',
  '플친-1분견적 신차장기렌트카',
  '플친-KS신차장기렌트카',
  '오케이_토스애즈',
  '플친-땡처리 신차장기렌트카',
  '플친-KB신차장기렌트',
  '사이트-로드박스',
  'KS오토플랜-정산전용💰',
  '사이트-KB캐피탈 신차장기렌트',
  '플친-10초견적',
  '플친-장기렌트끝판왕',
  'SNS-하나',
  '렌다',
  '사이트-리스다이렉트',
  '플친-우먼신차장기렌트카',
  '롯데렌터카 승계',
  '플친-레이디 신차장기렌트카',
  '플친-굿모닝장기렌트카 쇼핑',
  '유튜브',
  '플친-리스다이렉트',
  '사이트 - 모터나우',
  'SNS-신한',
  '플친-신차장기렌트 맞춤견적',
  '플친-다나와 신차장기렌트',
  '플친-다이렉트장기렌트카'
) and media_type='미분류';

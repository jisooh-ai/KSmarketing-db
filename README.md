# KS오토플랜 마케팅 퍼포먼스 DB

유입 문의·매출·광고비를 한곳에 모아 브랜드·매체·차량별 ROAS, CPA, 전환율, 리드타임을 보는 사내 웹 도구입니다.
운영 주소: https://jisooh-ai.github.io/KSmarketing-db/

- 사용 방법: `docs/manual/` (보고받는 분용 · 실무자용 · ROAS 월간 업무)
- 설치·설정: `docs/적용가이드.md`
- DB 변경 적용 현황: `migrations/README.md`
- 구조·지표 정의·작업 규칙: `CLAUDE.md`

`main` 에 push 하면 GitHub Pages 로 자동 배포됩니다. Supabase SQL 은 자동 반영되지 않으므로 `migrations/README.md` 절차를 따릅니다.

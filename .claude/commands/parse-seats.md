# 좌석파싱 스킬

좌석배치도 엑셀(.xlsx/.xls)을 파싱하여 상품별좌석현황 엑셀을 생성합니다.

## 사용법

```
/parse-seats <엑셀파일경로> [출력파일경로]
```

## 실행 방법

1. 입력 파일 경로를 확인합니다
2. 다음 명령어를 실행합니다:

```bash
cd /Users/erwin_shin/Desktop/App./멜론티켓 && NODE_PATH=melon_ticket_app/functions/node_modules node scripts/seat-parser.js "$ARGUMENTS"
```

3. 결과를 확인하고 사용자에게 등급별 좌석 수를 보고합니다
4. 필요시 Firestore에 업로드할 수 있습니다

## 입력 형식

- 좌석배치도 엑셀: 컬러 그리드 (배경색으로 등급 구분)
- 지원 색상: 핑크/빨강=VIP, 파랑=R, 초록=S, 노랑=A, 보라=시야방해R, 밝은초록=시야방해S, 검정=미판매

## 출력 형식

상품별좌석현황 엑셀 (No | 이용일 | 회차 | 좌석등급 | 층 | 열 | 좌석수 | 좌석번호)

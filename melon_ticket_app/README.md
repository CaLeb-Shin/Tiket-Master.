# 멜론티켓 MVP

Flutter + Firebase 기반 모바일 티켓팅 시스템

## 핵심 기능

- **연속좌석 자동 배정**: 2장 이상 구매 시 같은 구역/층의 연속된 좌석으로 자동 배정
- **좌석 공개 정책**: 결제 시 좌석 배정, 공연 1시간 전 좌석 번호 공개
- **QR 입장 시스템**: JWT 서명 기반 위변조 방지 QR (2분 만료, 자동 갱신)
- **최대 1500석 지원**

## 프로젝트 구조

```
melon_ticket_app/
├── lib/
│   ├── app/                    # 앱 설정 (라우터, 테마)
│   ├── features/
│   │   ├── auth/               # 로그인
│   │   ├── events/             # 공연 목록/상세
│   │   ├── checkout/           # 결제
│   │   ├── tickets/            # 내 티켓
│   │   ├── staff_scanner/      # 입장 스캐너
│   │   └── admin/              # 관리자
│   ├── data/
│   │   ├── models/             # 데이터 모델
│   │   └── repositories/       # 리포지토리
│   └── services/               # Firebase 서비스
├── functions/                   # Cloud Functions (TypeScript)
├── firestore.rules             # 보안 규칙
└── firestore.indexes.json      # 인덱스
```

## Firestore 컬렉션

| 컬렉션 | 설명 |
|--------|------|
| `venues` | 공연장 메타데이터 |
| `events` | 공연 정보 |
| `seats` | 좌석 마스터 |
| `orders` | 주문 |
| `seatBlocks` | 연속좌석 묶음 |
| `tickets` | 티켓 |
| `checkins` | 입장 기록 |
| `users` | 사용자 |

## Cloud Functions

1. `createOrder` - 주문 생성
2. `confirmPaymentAndAssignSeats` - 결제 확정 + 연속좌석 배정 (핵심!)
3. `revealSeatsForEvent` - 좌석 공개
4. `issueQrToken` - QR 토큰 발급 (JWT, 2분 만료)
5. `verifyAndCheckIn` - 입장 검증
6. `scheduledRevealSeats` - 자동 좌석 공개 (10분마다)

## 시작하기

### 1. Firebase 프로젝트 설정

```bash
# Firebase CLI 설치
npm install -g firebase-tools

# 로그인
firebase login

# 프로젝트 연결
firebase use --add
```

### 2. Flutter 앱 설정

```bash
# 패키지 설치
flutter pub get

# Firebase 설정 (flutterfire CLI 사용)
flutterfire configure
```

### 3. Functions 설정

```bash
cd functions
npm install
npm run build
```

### 4. 로컬 실행 (에뮬레이터)

```bash
# 에뮬레이터 시작
firebase emulators:start

# 앱 실행
flutter run
```

### 5. Firebase 백엔드 배포 (DB + Functions)

```bash
# 프로젝트 루트: melon_ticket_app/
./scripts/deploy-firebase-backend.sh
```

수동 배포를 원하면 아래 명령을 사용하세요.

```bash
firebase deploy --project melon-ticket-mvp-2026 --only firestore:rules,firestore:indexes,functions
```

### 6. Vercel 프론트 배포 (Flutter Web)

`vercel.json`은 리포지토리 루트(`멜론티켓/`)에 추가되어 있으며, `melon_ticket_app`을 빌드해서 정적 파일을 배포하도록 설정되어 있습니다.

1. Vercel에서 Git 리포지토리를 Import
2. 별도 Framework Preset 없이 기본값 사용
3. Build/Output은 `vercel.json` 설정 자동 사용
4. Deploy 실행

직접 CLI로 배포할 때:

```bash
# 리포지토리 루트(멜론티켓/)에서
npx vercel --prod
```

### 6-1. GitHub Push 자동 배포

리포지토리에는 `/.github/workflows/vercel-prod-deploy.yml`이 추가되어 있습니다.  
`main` 브랜치에 푸시하면 Vercel 프로덕션 배포가 자동 실행됩니다.

GitHub 저장소 `Settings > Secrets and variables > Actions`에 아래 시크릿 1개를 추가하세요.

- `VERCEL_TOKEN`: Vercel Personal Token

### 7. 배포 후 필수 Firebase 설정

1. Firebase Console -> Authentication -> Settings -> Authorized domains에 Vercel 도메인 추가
2. Google 로그인 사용 시 Google Cloud Console OAuth Client의 Authorized JavaScript origins에 Vercel 도메인 추가

## 테스트 시나리오

### 연속좌석 배정

1. 공연 등록 → 좌석 CSV 업로드
2. 사용자가 3장 구매
3. `confirmPaymentAndAssignSeats` 호출
4. 같은 구역/층/열의 연속 3석 자동 배정
5. 연속 좌석 없으면 주문 실패 처리

### QR 입장

1. 사용자가 티켓 상세 화면에서 QR 표시
2. 스태프가 스캐너로 QR 스캔
3. `verifyAndCheckIn` 호출
4. JWT 서명/만료 검증 → 체크인 완료

## 권한 체계

| 역할 | 권한 |
|------|------|
| `user` | 공연 조회, 구매, 내 티켓 조회 |
| `staff` | 입장 스캔 |
| `admin` | 공연/좌석 관리, 배정 현황 확인 |

## 향후 확장

- [ ] 실제 PG사 연동 (토스페이먼츠, 아임포트 등)
- [ ] 좌석 배치도 이미지 + 좌표 매핑
- [ ] FCM 푸시 알림 구현
- [ ] 오프라인 QR 스캔 (백업)
- [ ] 환불 처리 로직

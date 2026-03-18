# 멜팅티켓 환경 설정 가이드

## 환경 구성

| 환경 | Firebase 프로젝트 | 용도 |
|------|-------------------|------|
| **Production** | `melon-ticket-mvp-2026` | 실서비스 |
| **Staging** | `melon-ticket-staging` | QA/테스트 (생성 필요) |

## 환경 전환

```bash
# 프로덕션 (기본)
firebase use default

# 스테이징
firebase use staging

# 현재 환경 확인
firebase use
```

## 스테이징 환경 생성 절차

### 1. Firebase 프로젝트 생성
```bash
# Firebase Console에서 "melon-ticket-staging" 프로젝트 생성
# https://console.firebase.google.com/
```

### 2. Firestore 규칙 배포
```bash
firebase use staging
firebase deploy --only firestore:rules
```

### 3. Cloud Functions 배포
```bash
firebase use staging
firebase deploy --only functions
```

### 4. Hosting 배포
```bash
firebase use staging
firebase deploy --only hosting:admin
```

### 5. Flutter 앱 환경 분리

`melon_ticket_app/lib/main.dart`에서 Firebase 초기화:
```dart
// 환경별 Firebase 옵션은 flutterfire configure로 생성
// firebase_options_staging.dart 별도 생성 필요
```

### 6. Vercel 환경 분리
- Production: `main` 브랜치 → `melonticket-web-20260216.vercel.app`
- Staging: `staging` 브랜치 → Preview URL 자동 생성

## 환경 변수

| 변수 | Production | Staging |
|------|------------|---------|
| `JWT_SECRET` | `melon-ticket-secret-...` | 별도 시크릿 |
| `NAVER_CLIENT_ID` | 실제 값 | 테스트 값 |
| Firebase Project | `melon-ticket-mvp-2026` | `melon-ticket-staging` |

## 데이터 격리

- Production과 Staging은 **완전 별도 Firestore**
- 테스트 데이터는 Staging에서만 생성
- Production 데이터는 절대 Staging에 복사하지 않음 (개인정보)

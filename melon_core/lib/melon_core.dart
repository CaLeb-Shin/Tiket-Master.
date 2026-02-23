/// 멜론티켓 공유 코어 패키지
/// 모델, 레포지토리, 서비스, 테마를 관리자 웹과 사용자 앱에서 공유
library melon_core;

// ─── Models ───
export 'data/models/models.dart';

// ─── Repositories ───
export 'data/repositories/event_repository.dart';
export 'data/repositories/order_repository.dart';
export 'data/repositories/ticket_repository.dart';
export 'data/repositories/seat_repository.dart';
export 'data/repositories/venue_repository.dart';
export 'data/repositories/venue_view_repository.dart';
export 'data/repositories/review_repository.dart';
export 'data/repositories/checkin_repository.dart';
export 'data/repositories/scanner_device_repository.dart';
export 'data/repositories/mileage_repository.dart';
export 'data/repositories/hall_repository.dart';
export 'data/repositories/settlement_repository.dart';
export 'data/repositories/seller_repository.dart';
export 'data/repositories/venue_request_repository.dart';

// ─── Services ───
export 'services/auth_service.dart';
export 'services/firestore_service.dart';
export 'services/functions_service.dart';
export 'services/storage_service.dart';
export 'services/fcm_service.dart';
export 'services/scanner_device_service.dart';
export 'services/kakao_postcode_service.dart';

// ─── App ───
export 'app/theme.dart';

// ─── Widgets ───
export 'widgets/premium_effects.dart';

// ─── Utils ───
export 'utils/platform_utils.dart';
export 'utils/referral_code.dart';

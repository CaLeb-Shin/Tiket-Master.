/// 멜론티켓 공유 코어 패키지
/// Domain-Driven Design 구조: domain/ → data/ → infrastructure/ → presentation/
library melon_core;

// ─── Domain: Catalog (공연/공연장/커뮤니티) ───
export 'domain/catalog/event.dart';
export 'domain/catalog/venue.dart';
export 'domain/catalog/hall.dart';
export 'domain/catalog/review.dart';
export 'domain/catalog/discount_policy.dart';
export 'domain/catalog/venue_request.dart';

// ─── Domain: Booking (주문/좌석/티켓) ───
export 'domain/booking/order.dart';
export 'domain/booking/seat.dart';
export 'domain/booking/ticket.dart';
export 'domain/booking/seat_block.dart';
export 'domain/booking/checkin.dart';

// ─── Domain: Identity (사용자/인증) ───
export 'domain/identity/app_user.dart';

// ─── Domain: Loyalty (마일리지) ───
export 'domain/loyalty/mileage.dart';
export 'domain/loyalty/mileage_history.dart';

// ─── Domain: Finance (정산/에스크로) ───
export 'domain/finance/settlement.dart';
export 'domain/finance/escrow.dart';

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

// ─── Infrastructure: Firebase ───
export 'infrastructure/firebase/firestore_service.dart';
export 'infrastructure/firebase/functions_service.dart';
export 'infrastructure/firebase/storage_service.dart';
export 'infrastructure/firebase/fcm_service.dart';

// ─── Infrastructure: Device ───
export 'infrastructure/device/scanner_device.dart';
export 'infrastructure/device/scanner_device_service.dart';

// ─── Infrastructure: External ───
export 'infrastructure/external/kakao_postcode_service.dart';

// ─── Services (Identity 경계) ───
export 'services/auth_service.dart';

// ─── Presentation ───
export 'presentation/theme.dart';
export 'presentation/widgets/premium_effects.dart';

// ─── Shared Utils ───
export 'shared/utils/platform_utils.dart';
export 'shared/utils/referral_code.dart';

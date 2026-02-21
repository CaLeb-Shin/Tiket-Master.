import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final functionsServiceProvider =
    Provider<FunctionsService>((ref) => FunctionsService());

class FunctionsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// 주문 생성
  Future<Map<String, dynamic>> createOrder({
    required String eventId,
    required int quantity,
    List<String>? preferredSeatIds,
    String? discountPolicyName,
    String? referralCode,
  }) async {
    final callable = _functions.httpsCallable('createOrder');
    final result = await callable.call({
      'eventId': eventId,
      'quantity': quantity,
      if (preferredSeatIds != null && preferredSeatIds.isNotEmpty)
        'preferredSeatIds': preferredSeatIds,
      if (discountPolicyName != null)
        'discountPolicyName': discountPolicyName,
      if (referralCode != null && referralCode.isNotEmpty)
        'referralCode': referralCode,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 결제 확정 및 좌석 배정
  Future<Map<String, dynamic>> confirmPaymentAndAssignSeats({
    required String orderId,
  }) async {
    final callable = _functions.httpsCallable('confirmPaymentAndAssignSeats');
    final result = await callable.call({
      'orderId': orderId,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 좌석 공개 (어드민용)
  Future<Map<String, dynamic>> revealSeatsForEvent({
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('revealSeatsForEvent');
    final result = await callable.call({
      'eventId': eventId,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// QR 토큰 발급
  Future<Map<String, dynamic>> issueQrToken({
    required String ticketId,
  }) async {
    final callable = _functions.httpsCallable('issueQrToken');
    final result = await callable.call({
      'ticketId': ticketId,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 입장 검증 및 체크인
  Future<Map<String, dynamic>> verifyAndCheckIn({
    required String ticketId,
    required String qrToken,
    required String staffId,
    required String scannerDeviceId,
    required String checkinStage,
  }) async {
    final callable = _functions.httpsCallable('verifyAndCheckIn');
    final result = await callable.call({
      'ticketId': ticketId,
      'qrToken': qrToken,
      'staffId': staffId,
      'scannerDeviceId': scannerDeviceId,
      'checkinStage': checkinStage,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 스캐너 기기 등록/승인상태 조회
  Future<Map<String, dynamic>> registerScannerDevice({
    required String deviceId,
    required String label,
    required String platform,
  }) async {
    final callable = _functions.httpsCallable('registerScannerDevice');
    final result = await callable.call({
      'deviceId': deviceId,
      'label': label,
      'platform': platform,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 스캐너 기기 승인/차단 상태 변경 (관리자)
  Future<Map<String, dynamic>> setScannerDeviceApproval({
    required String deviceId,
    required bool approved,
    bool blocked = false,
  }) async {
    final callable = _functions.httpsCallable('setScannerDeviceApproval');
    final result = await callable.call({
      'deviceId': deviceId,
      'approved': approved,
      'blocked': blocked,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 티켓 취소/환불 요청
  Future<Map<String, dynamic>> requestTicketCancellation({
    required String ticketId,
  }) async {
    final callable = _functions.httpsCallable('requestTicketCancellation');
    final result = await callable.call({
      'ticketId': ticketId,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 마일리지로 좌석 등급 업그레이드
  Future<Map<String, dynamic>> upgradeTicketSeat({
    required String ticketId,
  }) async {
    final callable = _functions.httpsCallable('upgradeTicketSeat');
    final result = await callable.call({
      'ticketId': ticketId,
    });
    return Map<String, dynamic>.from(result.data);
  }
}

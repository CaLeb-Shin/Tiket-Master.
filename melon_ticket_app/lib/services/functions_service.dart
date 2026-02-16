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
  }) async {
    final callable = _functions.httpsCallable('createOrder');
    final result = await callable.call({
      'eventId': eventId,
      'quantity': quantity,
      if (preferredSeatIds != null && preferredSeatIds.isNotEmpty)
        'preferredSeatIds': preferredSeatIds,
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
  }) async {
    final callable = _functions.httpsCallable('verifyAndCheckIn');
    final result = await callable.call({
      'ticketId': ticketId,
      'qrToken': qrToken,
      'staffId': staffId,
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
}

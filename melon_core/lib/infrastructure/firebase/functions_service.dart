import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final functionsServiceProvider = Provider<FunctionsService>(
  (ref) => FunctionsService(),
);

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
      if (discountPolicyName != null) 'discountPolicyName': discountPolicyName,
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
    final result = await callable.call({'orderId': orderId});
    return Map<String, dynamic>.from(result.data);
  }

  /// 좌석 공개 (어드민용)
  Future<Map<String, dynamic>> revealSeatsForEvent({
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('revealSeatsForEvent');
    final result = await callable.call({'eventId': eventId});
    return Map<String, dynamic>.from(result.data);
  }

  /// QR 토큰 발급
  Future<Map<String, dynamic>> issueQrToken({required String ticketId}) async {
    final callable = _functions.httpsCallable('issueQrToken');
    final result = await callable.call({'ticketId': ticketId});
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
    String? inviteToken,
  }) async {
    final callable = _functions.httpsCallable('registerScannerDevice');
    final result = await callable.call({
      'deviceId': deviceId,
      'label': label,
      'platform': platform,
      if (inviteToken != null && inviteToken.isNotEmpty)
        'inviteToken': inviteToken,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 스캐너 초대링크 생성 (관리자)
  Future<Map<String, dynamic>> createScannerInvite({
    String? eventId,
    int expiresInHours = 24,
  }) async {
    final callable = _functions.httpsCallable('createScannerInvite');
    final result = await callable.call({
      if (eventId != null && eventId.isNotEmpty) 'eventId': eventId,
      'expiresInHours': expiresInHours,
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
    final result = await callable.call({'ticketId': ticketId});
    return Map<String, dynamic>.from(result.data);
  }

  /// 마일리지로 좌석 등급 업그레이드
  Future<Map<String, dynamic>> upgradeTicketSeat({
    required String ticketId,
  }) async {
    final callable = _functions.httpsCallable('upgradeTicketSeat');
    final result = await callable.call({'ticketId': ticketId});
    return Map<String, dynamic>.from(result.data);
  }

  /// 통합 QR 토큰 발급 (같은 주문 다수 티켓)
  Future<Map<String, dynamic>> issueGroupQrToken({
    required String orderId,
  }) async {
    final callable = _functions.httpsCallable('issueGroupQrToken');
    final result = await callable.call({'orderId': orderId});
    return Map<String, dynamic>.from(result.data);
  }

  // ─── 네이버 티켓 ───────────────────────────────────

  /// 네이버 주문 생성 + 좌석 배정 + 티켓 발급
  Future<Map<String, dynamic>> createNaverOrder({
    required String eventId,
    required String naverOrderId,
    required String buyerName,
    required String buyerPhone,
    required String productName,
    required String seatGrade,
    required int quantity,
    required String orderDate,
    String? memo,
    bool dryRun = false,
  }) async {
    final callable = _functions.httpsCallable('createNaverOrder');
    final result = await callable.call({
      'eventId': eventId,
      'naverOrderId': naverOrderId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'productName': productName,
      'seatGrade': seatGrade,
      'quantity': quantity,
      'orderDate': orderDate,
      if (memo != null) 'memo': memo,
      if (dryRun) 'dryRun': true,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 네이버 주문 취소 + 좌석 해제 + 번호 땡김
  Future<Map<String, dynamic>> cancelNaverOrder({
    required String orderId,
  }) async {
    final callable = _functions.httpsCallable('cancelNaverOrder');
    final result = await callable.call({'orderId': orderId});
    return Map<String, dynamic>.from(result.data);
  }

  /// 로그인한 사용자 계정에 네이버 주문 연결
  Future<Map<String, dynamic>> claimNaverOrder({
    required String naverOrderId,
    required String buyerPhone,
  }) async {
    final callable = _functions.httpsCallable('claimNaverOrder');
    final result = await callable.call({
      'naverOrderId': naverOrderId,
      'buyerPhone': buyerPhone,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 모바일 티켓 QR 토큰 발급 (비로그인)
  Future<Map<String, dynamic>> issueMobileQrToken({
    required String ticketId,
    required String accessToken,
  }) async {
    final callable = _functions.httpsCallable('issueMobileQrToken');
    final result = await callable.call({
      'ticketId': ticketId,
      'accessToken': accessToken,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 모바일 티켓 공개 조회 (비로그인)
  Future<Map<String, dynamic>> getMobileTicketByToken({
    required String accessToken,
  }) async {
    final callable = _functions.httpsCallable('getMobileTicketByToken');
    final result = await callable.call({'accessToken': accessToken});
    return Map<String, dynamic>.from(result.data);
  }

  /// 티켓 수신자 이름 설정 (비로그인)
  Future<Map<String, dynamic>> setRecipientName({
    required String accessToken,
    required String recipientName,
  }) async {
    final callable = _functions.httpsCallable('setRecipientName');
    final result = await callable.call({
      'accessToken': accessToken,
      'recipientName': recipientName,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 좌석/QR 즉시 공개 (revealAt → now)
  Future<Map<String, dynamic>> revealSeatsNow({required String eventId}) async {
    final callable = _functions.httpsCallable('revealSeatsNow');
    final result = await callable.call({'eventId': eventId});
    return Map<String, dynamic>.from(result.data);
  }

  /// 좌석 재배정 (티켓의 좌석 변경)
  Future<Map<String, dynamic>> reassignTicketSeat({
    required String ticketId,
    required String newSeatId,
  }) async {
    final callable = _functions.httpsCallable('reassignTicketSeat');
    final result = await callable.call({
      'ticketId': ticketId,
      'newSeatId': newSeatId,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// HTTP CF 호출 (onRequest 엔드포인트용, Firebase Auth 토큰 사용)
  Future<Map<String, dynamic>> callHttpFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final uri = Uri.parse(
      'https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net/$functionName',
    );
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  /// 통합 QR 일괄 체크인
  Future<Map<String, dynamic>> verifyAndCheckInGroup({
    required String orderId,
    required String qrToken,
    required String staffId,
    required String scannerDeviceId,
    required String checkinStage,
  }) async {
    final callable = _functions.httpsCallable('verifyAndCheckInGroup');
    final result = await callable.call({
      'orderId': orderId,
      'qrToken': qrToken,
      'staffId': staffId,
      'scannerDeviceId': scannerDeviceId,
      'checkinStage': checkinStage,
    });
    return Map<String, dynamic>.from(result.data);
  }

  /// 공연 종료 (어드민 전용)
  Future<Map<String, dynamic>> completeEvent({
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('completeEvent');
    final result = await callable.call({'eventId': eventId});
    return Map<String, dynamic>.from(result.data);
  }

  /// 리뷰 제출 (공연종료 후 모바일 티켓에서)
  Future<Map<String, dynamic>> submitReview({
    required String ticketId,
    required String accessToken,
    required int rating,
    String comment = '',
  }) async {
    final callable = _functions.httpsCallable('submitReview');
    final result = await callable.call({
      'ticketId': ticketId,
      'accessToken': accessToken,
      'rating': rating,
      'comment': comment,
    });
    return Map<String, dynamic>.from(result.data);
  }
}

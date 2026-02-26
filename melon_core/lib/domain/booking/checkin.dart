import 'package:cloud_firestore/cloud_firestore.dart';

/// 입장 기록 모델
class Checkin {
  final String id;
  final String eventId;
  final String ticketId;
  final String staffId;
  final String scannerDeviceId;
  final CheckinStage stage;
  final CheckinResult result;
  final String? seatInfo;
  final String? errorMessage;
  final DateTime scannedAt;

  Checkin({
    required this.id,
    required this.eventId,
    required this.ticketId,
    required this.staffId,
    required this.scannerDeviceId,
    required this.stage,
    required this.result,
    this.seatInfo,
    this.errorMessage,
    required this.scannedAt,
  });

  factory Checkin.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Checkin(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      ticketId: data['ticketId'] ?? '',
      staffId: data['staffId'] ?? '',
      scannerDeviceId: data['scannerDeviceId'] ?? '',
      stage: CheckinStage.fromString(data['stage']),
      result: CheckinResult.fromString(data['result']),
      seatInfo: data['seatInfo'],
      errorMessage: data['errorMessage'],
      scannedAt: (data['scannedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'ticketId': ticketId,
      'staffId': staffId,
      'scannerDeviceId': scannerDeviceId,
      'stage': stage.name,
      'result': result.name,
      'seatInfo': seatInfo,
      'errorMessage': errorMessage,
      'scannedAt': Timestamp.fromDate(scannedAt),
    };
  }
}

enum CheckinStage {
  entry,
  intermission,
  unknown;

  static CheckinStage fromString(String? value) {
    return CheckinStage.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CheckinStage.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case CheckinStage.entry:
        return '초기 입장';
      case CheckinStage.intermission:
        return '인터미션 재입장';
      case CheckinStage.unknown:
        return '단계 미지정';
    }
  }
}

enum CheckinResult {
  success, // 입장 성공
  alreadyUsed, // 이미 사용됨
  canceled, // 취소된 티켓
  invalidTicket, // 잘못된 티켓
  expired, // 만료된 QR
  invalidSignature, // 서명 오류
  notAllowedDevice, // 승인되지 않은 기기
  missingEntryCheckin; // 1차 입장 미완료

  static CheckinResult fromString(String? value) {
    return CheckinResult.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CheckinResult.invalidTicket,
    );
  }

  String get displayName {
    switch (this) {
      case CheckinResult.success:
        return '입장 성공';
      case CheckinResult.alreadyUsed:
        return '이미 사용된 티켓';
      case CheckinResult.canceled:
        return '취소된 티켓';
      case CheckinResult.invalidTicket:
        return '잘못된 티켓';
      case CheckinResult.expired:
        return '만료된 QR';
      case CheckinResult.invalidSignature:
        return '서명 오류';
      case CheckinResult.notAllowedDevice:
        return '승인되지 않은 기기';
      case CheckinResult.missingEntryCheckin:
        return '1차 입장 미완료';
    }
  }

  bool get isSuccess => this == CheckinResult.success;
}

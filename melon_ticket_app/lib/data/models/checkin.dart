import 'package:cloud_firestore/cloud_firestore.dart';

/// 입장 기록 모델
class Checkin {
  final String id;
  final String eventId;
  final String ticketId;
  final String staffId;
  final CheckinResult result;
  final String? errorMessage;
  final DateTime scannedAt;

  Checkin({
    required this.id,
    required this.eventId,
    required this.ticketId,
    required this.staffId,
    required this.result,
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
      result: CheckinResult.fromString(data['result']),
      errorMessage: data['errorMessage'],
      scannedAt: (data['scannedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'ticketId': ticketId,
      'staffId': staffId,
      'result': result.name,
      'errorMessage': errorMessage,
      'scannedAt': Timestamp.fromDate(scannedAt),
    };
  }
}

enum CheckinResult {
  success, // 입장 성공
  alreadyUsed, // 이미 사용됨
  canceled, // 취소된 티켓
  invalidTicket, // 잘못된 티켓
  expired, // 만료된 QR
  invalidSignature; // 서명 오류

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
    }
  }

  bool get isSuccess => this == CheckinResult.success;
}

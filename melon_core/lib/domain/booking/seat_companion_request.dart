import 'package:cloud_firestore/cloud_firestore.dart';

class SeatCompanionRequest {
  final String id;
  final String eventId;
  final String requesterOrderId;
  final String requesterName;
  final String requesterPhone;
  final String companionIdentifier; // 이름 or 전화번호 뒷4자리
  final CompanionRequestStatus status;
  final String? matchedOrderId;
  final DateTime createdAt;

  SeatCompanionRequest({
    required this.id,
    required this.eventId,
    required this.requesterOrderId,
    required this.requesterName,
    required this.requesterPhone,
    required this.companionIdentifier,
    required this.status,
    this.matchedOrderId,
    required this.createdAt,
  });

  factory SeatCompanionRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SeatCompanionRequest(
      id: doc.id,
      eventId: d['eventId'] ?? '',
      requesterOrderId: d['requesterOrderId'] ?? '',
      requesterName: d['requesterName'] ?? '',
      requesterPhone: d['requesterPhone'] ?? '',
      companionIdentifier: d['companionIdentifier'] ?? '',
      status: CompanionRequestStatus.fromString(d['status']),
      matchedOrderId: d['matchedOrderId'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'requesterOrderId': requesterOrderId,
      'requesterName': requesterName,
      'requesterPhone': requesterPhone,
      'companionIdentifier': companionIdentifier,
      'status': status.name,
      if (matchedOrderId != null) 'matchedOrderId': matchedOrderId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

enum CompanionRequestStatus {
  pending,
  matched,
  assigned,
  failed;

  static CompanionRequestStatus fromString(String? value) {
    return CompanionRequestStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CompanionRequestStatus.pending,
    );
  }

  String get displayName {
    switch (this) {
      case CompanionRequestStatus.pending:
        return '대기 중';
      case CompanionRequestStatus.matched:
        return '매칭됨';
      case CompanionRequestStatus.assigned:
        return '배정 완료';
      case CompanionRequestStatus.failed:
        return '매칭 실패';
    }
  }
}

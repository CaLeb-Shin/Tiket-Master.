import 'package:cloud_firestore/cloud_firestore.dart';

class Referral {
  final String id;
  final String referrerUserId;
  final String? refereeUserId;
  final String? refereePhone;
  final String eventId;
  final String? orderId;
  final ReferralStatus status;
  final bool referrerMileageAwarded;
  final bool refereeMileageAwarded;
  final DateTime createdAt;

  Referral({
    required this.id,
    required this.referrerUserId,
    this.refereeUserId,
    this.refereePhone,
    required this.eventId,
    this.orderId,
    required this.status,
    this.referrerMileageAwarded = false,
    this.refereeMileageAwarded = false,
    required this.createdAt,
  });

  factory Referral.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Referral(
      id: doc.id,
      referrerUserId: d['referrerUserId'] ?? '',
      refereeUserId: d['refereeUserId'],
      refereePhone: d['refereePhone'],
      eventId: d['eventId'] ?? '',
      orderId: d['orderId'],
      status: ReferralStatus.fromString(d['status']),
      referrerMileageAwarded: d['referrerMileageAwarded'] ?? false,
      refereeMileageAwarded: d['refereeMileageAwarded'] ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'referrerUserId': referrerUserId,
      if (refereeUserId != null) 'refereeUserId': refereeUserId,
      if (refereePhone != null) 'refereePhone': refereePhone,
      'eventId': eventId,
      if (orderId != null) 'orderId': orderId,
      'status': status.name,
      'referrerMileageAwarded': referrerMileageAwarded,
      'refereeMileageAwarded': refereeMileageAwarded,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

enum ReferralStatus {
  pending,
  completed,
  expired;

  static ReferralStatus fromString(String? value) {
    return ReferralStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReferralStatus.pending,
    );
  }

  String get displayName {
    switch (this) {
      case ReferralStatus.pending:
        return '대기 중';
      case ReferralStatus.completed:
        return '완료';
      case ReferralStatus.expired:
        return '만료';
    }
  }
}

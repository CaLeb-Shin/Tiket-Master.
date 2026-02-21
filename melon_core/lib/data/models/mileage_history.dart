import 'package:cloud_firestore/cloud_firestore.dart';

/// 마일리지 적립/차감 내역
class MileageHistory {
  final String id;
  final String userId;
  final int amount; // 양수: 적립, 음수: 차감
  final MileageType type;
  final String reason;
  final DateTime createdAt;

  MileageHistory({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.reason,
    required this.createdAt,
  });

  factory MileageHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MileageHistory(
      id: doc.id,
      userId: data['userId'] ?? '',
      amount: data['amount'] ?? 0,
      type: MileageType.fromString(data['type']),
      reason: data['reason'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'amount': amount,
      'type': type.name,
      'reason': reason,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

/// 마일리지 유형
enum MileageType {
  purchase,  // 구매 적립
  referral,  // 추천 적립
  upgrade;   // 등급업 차감

  static MileageType fromString(String? value) {
    return MileageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MileageType.purchase,
    );
  }

  String get displayName {
    switch (this) {
      case MileageType.purchase:
        return '구매 적립';
      case MileageType.referral:
        return '추천 적립';
      case MileageType.upgrade:
        return '등급 업그레이드';
    }
  }
}

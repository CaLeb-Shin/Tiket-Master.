import 'package:cloud_firestore/cloud_firestore.dart';

class Subscription {
  final String id;
  final String userId;
  final SubscriptionPlan plan;
  final SubscriptionStatus status;
  final int entriesRemaining;
  final int guaranteesRemaining;
  final int consecutiveLosses; // 연속 미당첨 횟수 (보장 트리거용)
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;

  Subscription({
    required this.id,
    required this.userId,
    required this.plan,
    required this.status,
    required this.entriesRemaining,
    this.guaranteesRemaining = 0,
    this.consecutiveLosses = 0,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
  });

  factory Subscription.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Subscription(
      id: doc.id,
      userId: d['userId'] ?? '',
      plan: SubscriptionPlan.fromString(d['plan']),
      status: SubscriptionStatus.fromString(d['status']),
      entriesRemaining: d['entriesRemaining'] ?? 0,
      guaranteesRemaining: d['guaranteesRemaining'] ?? 0,
      consecutiveLosses: d['consecutiveLosses'] ?? 0,
      startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (d['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'plan': plan.name,
      'status': status.name,
      'entriesRemaining': entriesRemaining,
      'guaranteesRemaining': guaranteesRemaining,
      'consecutiveLosses': consecutiveLosses,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  bool get isActive =>
      status == SubscriptionStatus.active &&
      DateTime.now().isBefore(endDate);

  bool get hasEntries =>
      plan == SubscriptionPlan.premium || entriesRemaining > 0;
}

enum SubscriptionPlan {
  basic,
  standard,
  premium;

  static SubscriptionPlan fromString(String? value) {
    return SubscriptionPlan.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionPlan.basic,
    );
  }

  String get displayName {
    switch (this) {
      case SubscriptionPlan.basic:
        return 'Basic';
      case SubscriptionPlan.standard:
        return 'Standard';
      case SubscriptionPlan.premium:
        return 'Premium';
    }
  }

  int get monthlyPrice {
    switch (this) {
      case SubscriptionPlan.basic:
        return 9900;
      case SubscriptionPlan.standard:
        return 19900;
      case SubscriptionPlan.premium:
        return 39900;
    }
  }

  int get monthlyEntries {
    switch (this) {
      case SubscriptionPlan.basic:
        return 2;
      case SubscriptionPlan.standard:
        return 5;
      case SubscriptionPlan.premium:
        return 999; // 무제한
    }
  }

  int get monthlyGuarantees {
    switch (this) {
      case SubscriptionPlan.basic:
        return 0;
      case SubscriptionPlan.standard:
        return 1;
      case SubscriptionPlan.premium:
        return 2;
    }
  }

  String get tierGrant {
    switch (this) {
      case SubscriptionPlan.basic:
        return 'silver';
      case SubscriptionPlan.standard:
        return 'gold';
      case SubscriptionPlan.premium:
        return 'platinum';
    }
  }
}

enum SubscriptionStatus {
  active,
  expired,
  cancelled;

  static SubscriptionStatus fromString(String? value) {
    return SubscriptionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionStatus.expired,
    );
  }

  String get displayName {
    switch (this) {
      case SubscriptionStatus.active:
        return '구독 중';
      case SubscriptionStatus.expired:
        return '만료';
      case SubscriptionStatus.cancelled:
        return '해지';
    }
  }
}

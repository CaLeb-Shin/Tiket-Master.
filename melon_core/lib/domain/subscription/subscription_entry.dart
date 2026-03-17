import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionEntry {
  final String id;
  final String subscriptionId;
  final String userId;
  final String eventId;
  final String seatGrade;
  final SubscriptionEntryStatus status;
  final bool isGuaranteed; // 보장 당첨 여부
  final String? ticketId; // 당첨 시 발급된 티켓
  final DateTime createdAt;

  SubscriptionEntry({
    required this.id,
    required this.subscriptionId,
    required this.userId,
    required this.eventId,
    required this.seatGrade,
    required this.status,
    this.isGuaranteed = false,
    this.ticketId,
    required this.createdAt,
  });

  factory SubscriptionEntry.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SubscriptionEntry(
      id: doc.id,
      subscriptionId: d['subscriptionId'] ?? '',
      userId: d['userId'] ?? '',
      eventId: d['eventId'] ?? '',
      seatGrade: d['seatGrade'] ?? '',
      status: SubscriptionEntryStatus.fromString(d['status']),
      isGuaranteed: d['isGuaranteed'] ?? false,
      ticketId: d['ticketId'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subscriptionId': subscriptionId,
      'userId': userId,
      'eventId': eventId,
      'seatGrade': seatGrade,
      'status': status.name,
      'isGuaranteed': isGuaranteed,
      if (ticketId != null) 'ticketId': ticketId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

enum SubscriptionEntryStatus {
  pending,
  won,
  lost,
  refunded;

  static SubscriptionEntryStatus fromString(String? value) {
    return SubscriptionEntryStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SubscriptionEntryStatus.pending,
    );
  }

  String get displayName {
    switch (this) {
      case SubscriptionEntryStatus.pending:
        return '추첨 대기';
      case SubscriptionEntryStatus.won:
        return '당첨';
      case SubscriptionEntryStatus.lost:
        return '미당첨';
      case SubscriptionEntryStatus.refunded:
        return '응모권 반환';
    }
  }
}

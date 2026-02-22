import 'package:cloud_firestore/cloud_firestore.dart';

/// 정산 모델
class Settlement {
  final String id;
  final String sellerId; // 셀러 ID (현재는 단일 어드민)
  final String eventId;
  final int totalSales; // 총 매출
  final int refundAmount; // 환불 금액
  final double platformFeeRate; // 수수료율 (기본 10%)
  final int platformFeeAmount; // 수수료 금액
  final int settlementAmount; // 정산 금액 (매출 - 환불 - 수수료)
  final Map<String, String>? bankInfo; // {bankName, accountNumber, accountHolder}
  final SettlementStatus status;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final DateTime? transferredAt;

  Settlement({
    required this.id,
    required this.sellerId,
    required this.eventId,
    required this.totalSales,
    this.refundAmount = 0,
    this.platformFeeRate = 0.10,
    required this.platformFeeAmount,
    required this.settlementAmount,
    this.bankInfo,
    required this.status,
    required this.requestedAt,
    this.approvedAt,
    this.transferredAt,
  });

  factory Settlement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Settlement(
      id: doc.id,
      sellerId: data['sellerId'] ?? '',
      eventId: data['eventId'] ?? '',
      totalSales: data['totalSales'] ?? 0,
      refundAmount: data['refundAmount'] ?? 0,
      platformFeeRate: (data['platformFeeRate'] ?? 0.10).toDouble(),
      platformFeeAmount: data['platformFeeAmount'] ?? 0,
      settlementAmount: data['settlementAmount'] ?? 0,
      bankInfo: data['bankInfo'] != null
          ? Map<String, String>.from(data['bankInfo'])
          : null,
      status: SettlementStatus.fromString(data['status']),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      transferredAt: (data['transferredAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sellerId': sellerId,
      'eventId': eventId,
      'totalSales': totalSales,
      'refundAmount': refundAmount,
      'platformFeeRate': platformFeeRate,
      'platformFeeAmount': platformFeeAmount,
      'settlementAmount': settlementAmount,
      'bankInfo': bankInfo,
      'status': status.name,
      'requestedAt': Timestamp.fromDate(requestedAt),
      if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
      if (transferredAt != null) 'transferredAt': Timestamp.fromDate(transferredAt!),
    };
  }
}

enum SettlementStatus {
  pending,    // 정산 대기
  approved,   // 승인됨
  transferred; // 입금 완료

  static SettlementStatus fromString(String? value) {
    return SettlementStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SettlementStatus.pending,
    );
  }

  String get displayName {
    switch (this) {
      case SettlementStatus.pending:
        return '정산 대기';
      case SettlementStatus.approved:
        return '승인됨';
      case SettlementStatus.transferred:
        return '입금 완료';
    }
  }
}

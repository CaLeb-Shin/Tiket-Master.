import 'package:cloud_firestore/cloud_firestore.dart';

/// 주문 모델
class Order {
  final String id;
  final String eventId;
  final String userId;
  final int quantity; // 티켓 수량
  final int unitPrice; // 단가
  final int totalAmount; // 총 금액
  final OrderStatus status;
  final String? failReason; // 실패 사유
  final int canceledCount; // 취소된 티켓 수
  final int refundedAmount; // 환불된 총 금액
  final bool isDemo; // 체험 모드 주문
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? refundedAt;

  Order({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.status,
    this.failReason,
    this.canceledCount = 0,
    this.refundedAmount = 0,
    this.isDemo = false,
    required this.createdAt,
    this.paidAt,
    this.refundedAt,
  });

  factory Order.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Order(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      userId: data['userId'] ?? '',
      quantity: data['quantity'] ?? 0,
      unitPrice: data['unitPrice'] ?? 0,
      totalAmount: data['totalAmount'] ?? 0,
      status: OrderStatus.fromString(data['status']),
      failReason: data['failReason'],
      canceledCount: data['canceledCount'] ?? 0,
      refundedAmount: data['refundedAmount'] ?? 0,
      isDemo: data['isDemo'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      refundedAt: (data['refundedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'userId': userId,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'status': status.name,
      'failReason': failReason,
      'canceledCount': canceledCount,
      'refundedAmount': refundedAmount,
      'isDemo': isDemo,
      'createdAt': Timestamp.fromDate(createdAt),
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'refundedAt': refundedAt != null ? Timestamp.fromDate(refundedAt!) : null,
    };
  }
}

enum OrderStatus {
  pending, // 결제 대기
  paid, // 결제 완료
  failed, // 실패 (좌석 없음 등)
  refunded, // 환불됨
  canceled; // 취소됨

  static OrderStatus fromString(String? value) {
    return OrderStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => OrderStatus.pending,
    );
  }

  String get displayName {
    switch (this) {
      case OrderStatus.pending:
        return '결제 대기';
      case OrderStatus.paid:
        return '결제 완료';
      case OrderStatus.failed:
        return '결제 실패';
      case OrderStatus.refunded:
        return '환불 완료';
      case OrderStatus.canceled:
        return '취소됨';
    }
  }
}

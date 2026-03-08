import 'package:cloud_firestore/cloud_firestore.dart';

/// 네이버 스토어 주문 모델
class NaverOrder {
  final String id;
  final String naverOrderId; // 네이버 주문번호
  final String buyerName;
  final String buyerPhone;
  final String productName; // 공연명 + 등급
  final int quantity;
  final DateTime orderDate;
  final NaverOrderStatus status;
  final List<String> ticketIds; // MobileTicket doc IDs
  final String eventId;
  final String seatGrade; // VIP, R, S, A
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String? memo;
  final String? userId;
  final DateTime? linkedAt;
  final String? linkSource;

  NaverOrder({
    required this.id,
    required this.naverOrderId,
    required this.buyerName,
    required this.buyerPhone,
    required this.productName,
    required this.quantity,
    required this.orderDate,
    required this.status,
    this.ticketIds = const [],
    required this.eventId,
    required this.seatGrade,
    required this.createdAt,
    this.cancelledAt,
    this.cancelReason,
    this.memo,
    this.userId,
    this.linkedAt,
    this.linkSource,
  });

  factory NaverOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NaverOrder(
      id: doc.id,
      naverOrderId: data['naverOrderId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      buyerPhone: data['buyerPhone'] ?? '',
      productName: data['productName'] ?? '',
      quantity: data['quantity'] ?? 0,
      orderDate: (data['orderDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: NaverOrderStatus.fromString(data['status']),
      ticketIds: List<String>.from(data['ticketIds'] ?? []),
      eventId: data['eventId'] ?? '',
      seatGrade: data['seatGrade'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
      cancelReason: data['cancelReason'],
      memo: data['memo'],
      userId: data['userId'],
      linkedAt: (data['linkedAt'] as Timestamp?)?.toDate(),
      linkSource: data['linkSource'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'naverOrderId': naverOrderId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'productName': productName,
      'quantity': quantity,
      'orderDate': Timestamp.fromDate(orderDate),
      'status': status.name,
      'ticketIds': ticketIds,
      'eventId': eventId,
      'seatGrade': seatGrade,
      'createdAt': Timestamp.fromDate(createdAt),
      'cancelledAt': cancelledAt != null
          ? Timestamp.fromDate(cancelledAt!)
          : null,
      'cancelReason': cancelReason,
      'memo': memo,
      if (userId != null) 'userId': userId,
      if (linkedAt != null) 'linkedAt': Timestamp.fromDate(linkedAt!),
      if (linkSource != null) 'linkSource': linkSource,
    };
  }
}

enum NaverOrderStatus {
  confirmed, // 확정
  cancelled, // 취소
  refunded; // 환불

  static NaverOrderStatus fromString(String? value) {
    return NaverOrderStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NaverOrderStatus.confirmed,
    );
  }

  String get displayName {
    switch (this) {
      case NaverOrderStatus.confirmed:
        return '확정';
      case NaverOrderStatus.cancelled:
        return '취소';
      case NaverOrderStatus.refunded:
        return '환불';
    }
  }
}

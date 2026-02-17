import 'package:cloud_firestore/cloud_firestore.dart';

/// 좌석 블록 모델 - 주문 단위 연속좌석 묶음
class SeatBlock {
  final String id;
  final String eventId;
  final String orderId;
  final int quantity;
  final List<String> seatIds; // 배정된 좌석 ID 목록
  final bool hidden; // 공개 전: true, 공개 후: false
  final DateTime assignedAt;

  SeatBlock({
    required this.id,
    required this.eventId,
    required this.orderId,
    required this.quantity,
    required this.seatIds,
    required this.hidden,
    required this.assignedAt,
  });

  factory SeatBlock.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SeatBlock(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      orderId: data['orderId'] ?? '',
      quantity: data['quantity'] ?? 0,
      seatIds: List<String>.from(data['seatIds'] ?? []),
      hidden: data['hidden'] ?? true,
      assignedAt: (data['assignedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'orderId': orderId,
      'quantity': quantity,
      'seatIds': seatIds,
      'hidden': hidden,
      'assignedAt': Timestamp.fromDate(assignedAt),
    };
  }

  SeatBlock copyWith({bool? hidden}) {
    return SeatBlock(
      id: id,
      eventId: eventId,
      orderId: orderId,
      quantity: quantity,
      seatIds: seatIds,
      hidden: hidden ?? this.hidden,
      assignedAt: assignedAt,
    );
  }
}

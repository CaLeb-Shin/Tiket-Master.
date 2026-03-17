import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String? userId;
  final String? phone;
  final String type; // NotificationType.name
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    this.userId,
    this.phone,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.read = false,
    required this.createdAt,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      userId: d['userId'],
      phone: d['phone'],
      type: d['type'] ?? '',
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      data: d['data'] != null ? Map<String, dynamic>.from(d['data']) : {},
      read: d['read'] ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (userId != null) 'userId': userId,
      if (phone != null) 'phone': phone,
      'type': type,
      'title': title,
      'body': body,
      'data': data,
      'read': read,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  NotificationType get notificationType => NotificationType.fromString(type);
}

enum NotificationType {
  bookingConfirmed,
  seatsRevealed,
  seatAssigned,
  eventReminder,
  intermissionSurvey,
  reviewRequest,
  cancellation,
  seatChanged;

  static NotificationType fromString(String? value) {
    return NotificationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotificationType.bookingConfirmed,
    );
  }

  String get displayName {
    switch (this) {
      case NotificationType.bookingConfirmed:
        return '예매 확정';
      case NotificationType.seatsRevealed:
        return '좌석 공개';
      case NotificationType.seatAssigned:
        return '좌석 배정';
      case NotificationType.eventReminder:
        return '공연 임박';
      case NotificationType.intermissionSurvey:
        return '인터미션 설문';
      case NotificationType.reviewRequest:
        return '리뷰 요청';
      case NotificationType.cancellation:
        return '취소 안내';
      case NotificationType.seatChanged:
        return '좌석 변경';
    }
  }

  String get icon {
    switch (this) {
      case NotificationType.bookingConfirmed:
        return '🎫';
      case NotificationType.seatsRevealed:
        return '💺';
      case NotificationType.seatAssigned:
        return '📍';
      case NotificationType.eventReminder:
        return '⏰';
      case NotificationType.intermissionSurvey:
        return '📝';
      case NotificationType.reviewRequest:
        return '⭐';
      case NotificationType.cancellation:
        return '❌';
      case NotificationType.seatChanged:
        return '🔄';
    }
  }
}

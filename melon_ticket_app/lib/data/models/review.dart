import 'package:cloud_firestore/cloud_firestore.dart';

/// 공연 리뷰 모델
class Review {
  final String id;
  final String eventId;
  final String userId;
  final String userDisplayName;
  final String? userPhotoUrl;
  final double rating; // 1.0 ~ 5.0
  final String content;
  final String? seatInfo; // "VIP석 A구역 3열 12번"
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Review({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userDisplayName,
    this.userPhotoUrl,
    required this.rating,
    required this.content,
    this.seatInfo,
    required this.createdAt,
    this.updatedAt,
  });

  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Review(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? '익명',
      userPhotoUrl: data['userPhotoUrl'],
      rating: (data['rating'] as num?)?.toDouble() ?? 5.0,
      content: data['content'] ?? '',
      seatInfo: data['seatInfo'],
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userPhotoUrl': userPhotoUrl,
      'rating': rating,
      'content': content,
      'seatInfo': seatInfo,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}

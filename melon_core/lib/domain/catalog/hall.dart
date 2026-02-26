import 'package:cloud_firestore/cloud_firestore.dart';

/// Hall — 공연 커뮤니티 채널
class Hall {
  final String id;
  final String name; // 공연명 (예: "레미제라블")
  final String? description;
  final String? coverImageUrl;
  final String createdBy; // 셀러 ID
  final List<String> tags;
  final int followerCount;
  final double averageRating; // 캐시 (트리거 갱신)
  final int reviewCount; // 캐시
  final DateTime createdAt;

  const Hall({
    required this.id,
    required this.name,
    this.description,
    this.coverImageUrl,
    required this.createdBy,
    this.tags = const [],
    this.followerCount = 0,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    required this.createdAt,
  });

  factory Hall.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Hall(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      coverImageUrl: data['coverImageUrl'],
      createdBy: data['createdBy'] ?? '',
      tags: data['tags'] != null ? List<String>.from(data['tags']) : const [],
      followerCount: data['followerCount'] ?? 0,
      averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: data['reviewCount'] ?? 0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'createdBy': createdBy,
      if (tags.isNotEmpty) 'tags': tags,
      'followerCount': followerCount,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

/// Hall 게시글
class HallPost {
  final String id;
  final String hallId;
  final String userId;
  final String userDisplayName;
  final String? userPhotoUrl;
  final String? eventId; // 어느 이벤트에서 작성했는지
  final String? eventTitle; // 표시용 (예: "서울 4/30 공연")
  final HallPostType type;
  final String content;
  final double? rating; // 리뷰일 때 1~5
  final List<String> imageUrls;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;

  const HallPost({
    required this.id,
    required this.hallId,
    required this.userId,
    required this.userDisplayName,
    this.userPhotoUrl,
    this.eventId,
    this.eventTitle,
    required this.type,
    required this.content,
    this.rating,
    this.imageUrls = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
  });

  factory HallPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return HallPost(
      id: doc.id,
      hallId: data['hallId'] ?? '',
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? '익명',
      userPhotoUrl: data['userPhotoUrl'],
      eventId: data['eventId'],
      eventTitle: data['eventTitle'],
      type: HallPostType.fromString(data['type']),
      content: data['content'] ?? '',
      rating: (data['rating'] as num?)?.toDouble(),
      imageUrls: data['imageUrls'] != null
          ? List<String>.from(data['imageUrls'])
          : const [],
      likeCount: data['likeCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hallId': hallId,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userPhotoUrl': userPhotoUrl,
      if (eventId != null) 'eventId': eventId,
      if (eventTitle != null) 'eventTitle': eventTitle,
      'type': type.name,
      'content': content,
      if (rating != null) 'rating': rating,
      if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

/// Hall 댓글
class HallComment {
  final String id;
  final String postId;
  final String userId;
  final String userDisplayName;
  final String? userPhotoUrl;
  final String content;
  final DateTime createdAt;

  const HallComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userDisplayName,
    this.userPhotoUrl,
    required this.content,
    required this.createdAt,
  });

  factory HallComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return HallComment(
      id: doc.id,
      postId: data['postId'] ?? '',
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? '익명',
      userPhotoUrl: data['userPhotoUrl'],
      content: data['content'] ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userPhotoUrl': userPhotoUrl,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

enum HallPostType {
  review,     // 관람 후기 (별점 포함)
  discussion, // 자유 토론
  photo,      // 사진
  notice;     // 공지 (셀러만)

  static HallPostType fromString(String? value) {
    return HallPostType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HallPostType.discussion,
    );
  }

  String get displayName {
    switch (this) {
      case HallPostType.review:
        return '리뷰';
      case HallPostType.discussion:
        return '토론';
      case HallPostType.photo:
        return '사진';
      case HallPostType.notice:
        return '공지';
    }
  }

  String get emoji {
    switch (this) {
      case HallPostType.review:
        return '⭐';
      case HallPostType.discussion:
        return '💬';
      case HallPostType.photo:
        return '📷';
      case HallPostType.notice:
        return '📢';
    }
  }
}

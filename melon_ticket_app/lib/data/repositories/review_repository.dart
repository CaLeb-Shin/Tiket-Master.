import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/review.dart';
import '../../services/firestore_service.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(firestoreServiceProvider));
});

/// 특정 이벤트의 리뷰 스트림
final eventReviewsProvider =
    StreamProvider.family<List<Review>, String>((ref, eventId) {
  return ref.watch(reviewRepositoryProvider).getReviewsByEvent(eventId);
});

/// 특정 이벤트의 평균 별점
final eventRatingProvider =
    StreamProvider.family<double, String>((ref, eventId) {
  return ref
      .watch(reviewRepositoryProvider)
      .getReviewsByEvent(eventId)
      .map((reviews) {
    if (reviews.isEmpty) return 0.0;
    return reviews.map((r) => r.rating).reduce((a, b) => a + b) /
        reviews.length;
  });
});

class ReviewRepository {
  final FirestoreService _firestoreService;

  ReviewRepository(this._firestoreService);

  CollectionReference get _reviews =>
      _firestoreService.instance.collection('reviews');

  /// 이벤트별 리뷰 조회 (최신순)
  Stream<List<Review>> getReviewsByEvent(String eventId) {
    return _reviews
        .where('eventId', isEqualTo: eventId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(Review.fromFirestore).toList());
  }

  /// 사용자별 리뷰 조회
  Stream<List<Review>> getReviewsByUser(String userId) {
    return _reviews
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Review.fromFirestore).toList());
  }

  /// 사용자가 해당 이벤트에 이미 리뷰를 작성했는지 확인
  Future<Review?> getUserReviewForEvent(
      String userId, String eventId) async {
    final snap = await _reviews
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Review.fromFirestore(snap.docs.first);
  }

  /// 리뷰 작성
  Future<String> createReview(Review review) async {
    final doc = await _reviews.add(review.toMap());
    return doc.id;
  }

  /// 리뷰 수정
  Future<void> updateReview(String reviewId, String content, double rating) async {
    await _reviews.doc(reviewId).update({
      'content': content,
      'rating': rating,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 리뷰 삭제
  Future<void> deleteReview(String reviewId) async {
    await _reviews.doc(reviewId).delete();
  }
}

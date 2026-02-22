import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/hall.dart';

final hallRepositoryProvider = Provider<HallRepository>((ref) {
  return HallRepository(ref.watch(firestoreServiceProvider));
});

/// Hall 상세 스트림
final hallStreamProvider =
    StreamProvider.family<Hall?, String>((ref, hallId) {
  return ref.watch(hallRepositoryProvider).getHall(hallId);
});

/// Hall 게시글 스트림 (유형별)
final hallPostsProvider =
    StreamProvider.family<List<HallPost>, ({String hallId, String? type})>(
        (ref, params) {
  return ref
      .watch(hallRepositoryProvider)
      .getPosts(params.hallId, type: params.type);
});

/// Hall 댓글 스트림
final hallCommentsProvider =
    StreamProvider.family<List<HallComment>, ({String hallId, String postId})>(
        (ref, params) {
  return ref
      .watch(hallRepositoryProvider)
      .getComments(params.hallId, params.postId);
});

/// 전체 Hall 목록
final allHallsProvider = StreamProvider<List<Hall>>((ref) {
  return ref.watch(hallRepositoryProvider).getAllHalls();
});

class HallRepository {
  final FirestoreService _fs;

  HallRepository(this._fs);

  CollectionReference get _halls => _fs.instance.collection('halls');

  // ── Hall CRUD ──

  Stream<Hall?> getHall(String hallId) {
    return _halls.doc(hallId).snapshots().map(
          (doc) => doc.exists ? Hall.fromFirestore(doc) : null,
        );
  }

  Stream<List<Hall>> getAllHalls() {
    return _halls
        .orderBy('followerCount', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Hall.fromFirestore(d)).toList());
  }

  Future<String> createHall(Hall hall) async {
    final ref = await _halls.add(hall.toMap());
    return ref.id;
  }

  Future<void> updateHall(String hallId, Map<String, dynamic> data) async {
    await _halls.doc(hallId).update(data);
  }

  // ── Posts ──

  CollectionReference _postsRef(String hallId) =>
      _halls.doc(hallId).collection('posts');

  Stream<List<HallPost>> getPosts(String hallId, {String? type}) {
    Query query = _postsRef(hallId).orderBy('createdAt', descending: true);
    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }
    return query.limit(50).snapshots().map(
        (s) => s.docs.map((d) => HallPost.fromFirestore(d)).toList());
  }

  Stream<List<HallPost>> getReviews(String hallId, {String? sortBy}) {
    Query query =
        _postsRef(hallId).where('type', isEqualTo: 'review');

    switch (sortBy) {
      case 'rating_high':
        query = query.orderBy('rating', descending: true);
        break;
      case 'rating_low':
        query = query.orderBy('rating', descending: false);
        break;
      case 'likes':
        query = query.orderBy('likeCount', descending: true);
        break;
      default:
        query = query.orderBy('createdAt', descending: true);
    }

    return query.limit(50).snapshots().map(
        (s) => s.docs.map((d) => HallPost.fromFirestore(d)).toList());
  }

  Future<String> createPost(String hallId, HallPost post) async {
    final ref = await _postsRef(hallId).add(post.toMap());

    // 리뷰인 경우 Hall 평균 별점 갱신
    if (post.type == HallPostType.review && post.rating != null) {
      await _updateHallRating(hallId);
    }

    return ref.id;
  }

  Future<void> deletePost(String hallId, String postId) async {
    // 댓글 먼저 삭제
    final comments = await _postsRef(hallId)
        .doc(postId)
        .collection('comments')
        .get();
    final batch = _fs.instance.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    batch.delete(_postsRef(hallId).doc(postId));
    await batch.commit();

    await _updateHallRating(hallId);
  }

  /// 중복 리뷰 확인 (같은 사용자 + 같은 eventId)
  Future<bool> hasUserReviewedEvent(
      String hallId, String userId, String eventId) async {
    final snap = await _postsRef(hallId)
        .where('type', isEqualTo: 'review')
        .where('userId', isEqualTo: userId)
        .where('eventId', isEqualTo: eventId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ── Comments ──

  CollectionReference _commentsRef(String hallId, String postId) =>
      _postsRef(hallId).doc(postId).collection('comments');

  Stream<List<HallComment>> getComments(String hallId, String postId) {
    return _commentsRef(hallId, postId)
        .orderBy('createdAt', descending: false)
        .limit(100)
        .snapshots()
        .map(
            (s) => s.docs.map((d) => HallComment.fromFirestore(d)).toList());
  }

  Future<void> addComment(
      String hallId, String postId, HallComment comment) async {
    await _commentsRef(hallId, postId).add(comment.toMap());
    // commentCount 증가
    await _postsRef(hallId)
        .doc(postId)
        .update({'commentCount': FieldValue.increment(1)});
  }

  // ── Likes ──

  Future<void> toggleLike(
      String hallId, String postId, String userId) async {
    final likeRef =
        _postsRef(hallId).doc(postId).collection('likes').doc(userId);
    final doc = await likeRef.get();

    if (doc.exists) {
      await likeRef.delete();
      await _postsRef(hallId)
          .doc(postId)
          .update({'likeCount': FieldValue.increment(-1)});
    } else {
      await likeRef.set({'createdAt': FieldValue.serverTimestamp()});
      await _postsRef(hallId)
          .doc(postId)
          .update({'likeCount': FieldValue.increment(1)});
    }
  }

  Future<bool> hasUserLiked(
      String hallId, String postId, String userId) async {
    final doc = await _postsRef(hallId)
        .doc(postId)
        .collection('likes')
        .doc(userId)
        .get();
    return doc.exists;
  }

  // ── Follow ──

  Future<void> toggleFollow(String hallId, String userId) async {
    final followerRef =
        _halls.doc(hallId).collection('followers').doc(userId);
    final doc = await followerRef.get();

    if (doc.exists) {
      await followerRef.delete();
      await _halls
          .doc(hallId)
          .update({'followerCount': FieldValue.increment(-1)});
    } else {
      await followerRef.set({'followedAt': FieldValue.serverTimestamp()});
      await _halls
          .doc(hallId)
          .update({'followerCount': FieldValue.increment(1)});
    }
  }

  Future<bool> isFollowing(String hallId, String userId) async {
    final doc =
        await _halls.doc(hallId).collection('followers').doc(userId).get();
    return doc.exists;
  }

  Stream<List<String>> getFollowedHallIds(String userId) {
    // 역방향 쿼리: 모든 hall의 followers 서브컬렉션을 조회하기 어려우므로
    // collectionGroup 사용
    return _fs.instance
        .collectionGroup('followers')
        .where(FieldPath.documentId, isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map((d) {
              // 경로: halls/{hallId}/followers/{userId}
              final path = d.reference.path;
              final parts = path.split('/');
              return parts[1]; // hallId
            }).toList());
  }

  // ── Rating 갱신 ──

  Future<void> _updateHallRating(String hallId) async {
    final reviews = await _postsRef(hallId)
        .where('type', isEqualTo: 'review')
        .get();

    if (reviews.docs.isEmpty) {
      await _halls.doc(hallId).update({
        'averageRating': 0.0,
        'reviewCount': 0,
      });
      return;
    }

    double sum = 0;
    int count = 0;
    for (final doc in reviews.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final rating = (data['rating'] as num?)?.toDouble();
      if (rating != null) {
        sum += rating;
        count++;
      }
    }

    await _halls.doc(hallId).update({
      'averageRating': count > 0 ? sum / count : 0.0,
      'reviewCount': count,
    });
  }

  /// Hall 검색 (이름 prefix 매칭)
  Future<List<Hall>> searchHalls(String query) async {
    if (query.isEmpty) return [];
    final snap = await _halls
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(20)
        .get();
    return snap.docs.map((d) => Hall.fromFirestore(d)).toList();
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/subscription.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(firestoreServiceProvider));
});

/// 로그인 유저의 활성 구독 스트림
final activeSubscriptionProvider =
    StreamProvider.family<Subscription?, String>((ref, userId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.subscriptions
      .where('userId', isEqualTo: userId)
      .where('status', isEqualTo: 'active')
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isEmpty
          ? null
          : Subscription.fromFirestore(snap.docs.first));
});

/// 유저의 응모 내역 스트림
final userEntriesProvider =
    StreamProvider.family<List<SubscriptionEntry>, String>((ref, userId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.subscriptionEntries
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => SubscriptionEntry.fromFirestore(d)).toList());
});

class SubscriptionRepository {
  final FirestoreService _fs;

  SubscriptionRepository(this._fs);

  Future<Subscription?> getActiveSubscription(String userId) async {
    final snap = await _fs.subscriptions
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Subscription.fromFirestore(snap.docs.first);
  }

  Future<List<SubscriptionEntry>> getEntriesByEvent(
      String userId, String eventId) async {
    final snap = await _fs.subscriptionEntries
        .where('userId', isEqualTo: userId)
        .where('eventId', isEqualTo: eventId)
        .get();
    return snap.docs.map((d) => SubscriptionEntry.fromFirestore(d)).toList();
  }

  Future<LotteryResult?> getLotteryResult(
      String eventId, String seatGrade) async {
    final snap = await _fs.lotteryResults
        .where('eventId', isEqualTo: eventId)
        .where('seatGrade', isEqualTo: seatGrade)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return LotteryResult.fromFirestore(snap.docs.first);
  }
}

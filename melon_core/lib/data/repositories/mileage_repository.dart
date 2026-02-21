import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/mileage_history.dart';

final mileageRepositoryProvider = Provider<MileageRepository>((ref) {
  return MileageRepository(ref.watch(firestoreServiceProvider));
});

/// 마일리지 내역 스트림 (최근 N건)
final mileageHistoryStreamProvider =
    StreamProvider.family<List<MileageHistory>, ({String userId, int limit})>(
        (ref, params) {
  return ref
      .watch(mileageRepositoryProvider)
      .getMileageHistory(params.userId, limit: params.limit);
});

class MileageRepository {
  final FirestoreService _firestoreService;

  MileageRepository(this._firestoreService);

  /// 사용자별 마일리지 내역
  Stream<List<MileageHistory>> getMileageHistory(String userId,
      {int limit = 10}) {
    return _firestoreService.instance
        .collection('mileageHistory')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => MileageHistory.fromFirestore(doc)).toList());
  }
}

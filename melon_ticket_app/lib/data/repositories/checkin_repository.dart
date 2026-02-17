import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/checkin.dart';

final checkinRepositoryProvider = Provider<CheckinRepository>((ref) {
  return CheckinRepository(ref.watch(firestoreServiceProvider));
});

class CheckinRepository {
  final FirestoreService _firestoreService;

  CheckinRepository(this._firestoreService);

  Stream<List<Checkin>> getCheckinsByEvent(
    String eventId, {
    int limit = 400,
  }) {
    return _firestoreService.checkins
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map((snapshot) {
      final all = snapshot.docs.map((doc) => Checkin.fromFirestore(doc)).toList();
      all.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      if (all.length > limit) {
        return all.sublist(0, limit);
      }
      return all;
    });
  }
}


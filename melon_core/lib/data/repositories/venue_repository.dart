import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/venue.dart';

final venueRepositoryProvider = Provider<VenueRepository>((ref) {
  return VenueRepository(ref.watch(firestoreServiceProvider));
});

/// 전체 공연장 목록 스트림
final venuesStreamProvider = StreamProvider<List<Venue>>((ref) {
  return ref.watch(venueRepositoryProvider).getVenuesStream();
});

/// 특정 공연장 스트림
final venueStreamProvider =
    StreamProvider.family<Venue?, String>((ref, venueId) {
  return ref.watch(venueRepositoryProvider).getVenueStream(venueId);
});

class VenueRepository {
  final FirestoreService _firestoreService;

  VenueRepository(this._firestoreService);

  /// 전체 공연장 목록 스트림
  Stream<List<Venue>> getVenuesStream() {
    return _firestoreService.venues
        .orderBy('name')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Venue.fromFirestore(doc)).toList());
  }

  /// 특정 공연장 스트림
  Stream<Venue?> getVenueStream(String venueId) {
    return _firestoreService.venues.doc(venueId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Venue.fromFirestore(doc);
    });
  }

  /// 특정 공연장 조회
  Future<Venue?> getVenue(String venueId) async {
    final doc = await _firestoreService.venues.doc(venueId).get();
    if (!doc.exists) return null;
    return Venue.fromFirestore(doc);
  }

  /// 공연장 생성
  Future<String> createVenue(Venue venue) async {
    final docRef = await _firestoreService.venues.add(venue.toMap());
    return docRef.id;
  }

  /// 공연장 업데이트
  Future<void> updateVenue(
      String venueId, Map<String, dynamic> data) async {
    await _firestoreService.venues.doc(venueId).update(data);
  }

  /// 공연장 삭제
  Future<void> deleteVenue(String venueId) async {
    await _firestoreService.venues.doc(venueId).delete();
  }
}

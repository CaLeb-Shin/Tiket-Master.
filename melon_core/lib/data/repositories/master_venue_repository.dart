import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/firebase/firestore_service.dart';
import '../../domain/catalog/master_venue.dart';

final masterVenueRepositoryProvider = Provider<MasterVenueRepository>((ref) {
  return MasterVenueRepository(ref.watch(firestoreServiceProvider));
});

/// 마스터 공연장 전체 목록 스트림
final masterVenuesStreamProvider = StreamProvider<List<MasterVenue>>((ref) {
  return ref.watch(masterVenueRepositoryProvider).getMasterVenuesStream();
});

/// 특정 마스터 공연장 스트림
final masterVenueStreamProvider =
    StreamProvider.family<MasterVenue?, String>((ref, id) {
  return ref.watch(masterVenueRepositoryProvider).getMasterVenueStream(id);
});

class MasterVenueRepository {
  final FirestoreService _firestoreService;

  MasterVenueRepository(this._firestoreService);

  Stream<List<MasterVenue>> getMasterVenuesStream() {
    return _firestoreService.masterVenues
        .orderBy('name')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => MasterVenue.fromFirestore(d)).toList());
  }

  Stream<MasterVenue?> getMasterVenueStream(String id) {
    return _firestoreService.masterVenues.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return MasterVenue.fromFirestore(doc);
    });
  }

  Future<MasterVenue?> getMasterVenue(String id) async {
    final doc = await _firestoreService.masterVenues.doc(id).get();
    if (!doc.exists) return null;
    return MasterVenue.fromFirestore(doc);
  }

  Future<String> createMasterVenue(MasterVenue mv) async {
    final ref = await _firestoreService.masterVenues.add(mv.toMap());
    return ref.id;
  }

  Future<void> updateMasterVenue(
      String id, Map<String, dynamic> data) async {
    await _firestoreService.masterVenues.doc(id).update(data);
  }

  Future<void> deleteMasterVenue(String id) async {
    await _firestoreService.masterVenues.doc(id).delete();
  }

  /// 마스터에서 새 Venue 생성 (복사 + 링크)
  Future<String> createVenueFromMaster(String masterVenueId) async {
    final mv = await getMasterVenue(masterVenueId);
    if (mv == null) throw Exception('마스터 공연장을 찾을 수 없습니다');

    final venueData = <String, dynamic>{
      'name': mv.name,
      'address': mv.address,
      'floors': mv.floors.map((f) => f.toMap()).toList(),
      'totalSeats': mv.totalSeats,
      'hasSeatView': mv.hasSeatView,
      'stagePosition': mv.seatLayout?.stagePosition ?? 'top',
      'masterVenueId': masterVenueId,
      'createdAt': DateTime.now(),
    };
    if (mv.seatLayout != null) {
      venueData['seatLayout'] = mv.seatLayout!.toMap();
    }

    final venueRef = await _firestoreService.venues.add(venueData);

    // 마스터에 linkedVenueIds 추가
    await _firestoreService.masterVenues.doc(masterVenueId).update({
      'linkedVenueIds': [...mv.linkedVenueIds, venueRef.id],
    });

    return venueRef.id;
  }
}

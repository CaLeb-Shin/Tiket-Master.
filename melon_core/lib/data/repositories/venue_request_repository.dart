import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/venue_request.dart';

final venueRequestRepositoryProvider = Provider<VenueRequestRepository>((ref) {
  return VenueRequestRepository(ref.watch(firestoreServiceProvider));
});

/// 대기중 공연장 요청 스트림
final pendingVenueRequestsProvider =
    StreamProvider<List<VenueRequest>>((ref) {
  return ref
      .watch(venueRequestRepositoryProvider)
      .getRequestsStream(status: 'pending');
});

/// 전체 공연장 요청 스트림
final allVenueRequestsProvider = StreamProvider<List<VenueRequest>>((ref) {
  return ref.watch(venueRequestRepositoryProvider).getRequestsStream();
});

/// 특정 셀러의 공연장 요청 스트림
final sellerVenueRequestsProvider =
    StreamProvider.family<List<VenueRequest>, String>((ref, sellerId) {
  return ref
      .watch(venueRequestRepositoryProvider)
      .getRequestsStream(sellerId: sellerId);
});

class VenueRequestRepository {
  final FirestoreService _firestoreService;

  VenueRequestRepository(this._firestoreService);

  CollectionReference get _collection =>
      _firestoreService.instance.collection('venueRequests');

  /// 공연장 요청 생성
  Future<String> createRequest(VenueRequest request) async {
    final docRef = await _collection.add(request.toMap());
    return docRef.id;
  }

  /// 공연장 요청 목록 스트림 (status, sellerId 필터 가능)
  Stream<List<VenueRequest>> getRequestsStream({
    String? status,
    String? sellerId,
  }) {
    Query query = _collection.orderBy('requestedAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    if (sellerId != null) {
      query = query.where('sellerId', isEqualTo: sellerId);
    }

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => VenueRequest.fromFirestore(doc))
        .toList());
  }

  /// 공연장 요청 승인 → 공연장 문서 생성
  Future<String> approveRequest({
    required String requestId,
    required String approvedBy,
  }) async {
    final requestDoc = await _collection.doc(requestId).get();
    if (!requestDoc.exists) throw StateError('요청을 찾을 수 없습니다.');

    final request = VenueRequest.fromFirestore(requestDoc);
    if (!request.isPending) throw StateError('이미 처리된 요청입니다.');

    final batch = _firestoreService.instance.batch();

    // 1. 요청 상태 업데이트
    batch.update(_collection.doc(requestId), {
      'status': 'approved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': approvedBy,
    });

    // 2. 공연장 문서 생성
    final venueRef = _firestoreService.venues.doc();
    batch.set(venueRef, {
      'name': request.venueName,
      'address': request.address,
      'totalSeats': request.seatCount,
      'floors': [],
      'stagePosition': 'top',
      'hasSeatView': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdFromRequest': requestId,
      'createdBySeller': request.sellerId,
    });

    await batch.commit();
    return venueRef.id;
  }

  /// 공연장 요청 거절
  Future<void> rejectRequest({
    required String requestId,
    required String rejectedBy,
    String? reason,
  }) async {
    final requestDoc = await _collection.doc(requestId).get();
    if (!requestDoc.exists) throw StateError('요청을 찾을 수 없습니다.');

    final request = VenueRequest.fromFirestore(requestDoc);
    if (!request.isPending) throw StateError('이미 처리된 요청입니다.');

    await _collection.doc(requestId).update({
      'status': 'rejected',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': rejectedBy,
      if (reason != null) 'rejectReason': reason,
    });
  }
}

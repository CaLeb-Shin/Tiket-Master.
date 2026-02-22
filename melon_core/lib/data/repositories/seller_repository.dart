import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/app_user.dart';

final sellerRepositoryProvider = Provider<SellerRepository>((ref) {
  return SellerRepository(ref.watch(firestoreServiceProvider));
});

/// 셀러 목록 스트림 (role=seller)
final sellersStreamProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(sellerRepositoryProvider).getAllSellers();
});

class SellerRepository {
  final FirestoreService _fs;

  SellerRepository(this._fs);

  CollectionReference get _users => _fs.instance.collection('users');

  /// 전체 셀러 목록
  Stream<List<AppUser>> getAllSellers() {
    return _users
        .where('role', isEqualTo: 'seller')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => AppUser.fromFirestore(d)).toList());
  }

  /// 셀러 상태별 조회 (pending / active / suspended)
  Stream<List<AppUser>> getSellersByStatus(String sellerStatus) {
    return _users
        .where('role', isEqualTo: 'seller')
        .where('sellerProfile.sellerStatus', isEqualTo: sellerStatus)
        .snapshots()
        .map((s) => s.docs.map((d) => AppUser.fromFirestore(d)).toList());
  }

  /// 셀러 승인
  Future<void> approveSeller(String userId) async {
    await _users.doc(userId).update({
      'sellerProfile.sellerStatus': 'active',
    });
  }

  /// 셀러 정지
  Future<void> suspendSeller(String userId) async {
    await _users.doc(userId).update({
      'sellerProfile.sellerStatus': 'suspended',
    });
  }

  /// 셀러 정지 해제
  Future<void> reactivateSeller(String userId) async {
    await _users.doc(userId).update({
      'sellerProfile.sellerStatus': 'active',
    });
  }

  /// 셀러 탈퇴 처리 (role → user로 변경)
  Future<void> removeSeller(String userId) async {
    await _users.doc(userId).update({
      'role': 'user',
      'sellerProfile.sellerStatus': 'deactivated',
    });
  }

  /// 셀러의 이벤트 수 조회
  Future<int> getSellerEventCount(String sellerId) async {
    final snap = await _fs.instance
        .collection('events')
        .where('sellerId', isEqualTo: sellerId)
        .count()
        .get();
    return snap.count ?? 0;
  }
}

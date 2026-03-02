import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/naver_order.dart';

final naverOrderRepositoryProvider = Provider<NaverOrderRepository>((ref) {
  return NaverOrderRepository(ref.watch(firestoreServiceProvider));
});

/// 이벤트별 네이버 주문 스트림
final naverOrdersStreamProvider =
    StreamProvider.family<List<NaverOrder>, String>((ref, eventId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.naverOrders
      .where('eventId', isEqualTo: eventId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => NaverOrder.fromFirestore(d)).toList());
});

class NaverOrderRepository {
  final FirestoreService _fs;

  NaverOrderRepository(this._fs);

  /// 이벤트별 주문 목록
  Future<List<NaverOrder>> getOrdersByEvent(String eventId) async {
    final snap = await _fs.naverOrders
        .where('eventId', isEqualTo: eventId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => NaverOrder.fromFirestore(d)).toList();
  }

  /// 네이버 주문번호로 조회
  Future<NaverOrder?> getByNaverOrderId(String naverOrderId) async {
    final snap = await _fs.naverOrders
        .where('naverOrderId', isEqualTo: naverOrderId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return NaverOrder.fromFirestore(snap.docs.first);
  }

  /// 단일 주문 조회
  Future<NaverOrder?> getOrder(String orderId) async {
    final doc = await _fs.naverOrders.doc(orderId).get();
    if (!doc.exists) return null;
    return NaverOrder.fromFirestore(doc);
  }

  /// 주문 스트림
  Stream<NaverOrder?> orderStream(String orderId) {
    return _fs.naverOrders.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return NaverOrder.fromFirestore(doc);
    });
  }
}

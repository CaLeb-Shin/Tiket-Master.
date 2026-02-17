import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/order.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(ref.watch(firestoreServiceProvider));
});

/// 내 주문 목록
final myOrdersStreamProvider = StreamProvider.family<List<Order>, String>((ref, userId) {
  return ref.watch(orderRepositoryProvider).getOrdersByUser(userId);
});

class OrderRepository {
  final FirestoreService _firestoreService;

  OrderRepository(this._firestoreService);

  /// 사용자별 주문 목록
  Stream<List<Order>> getOrdersByUser(String userId) {
    return _firestoreService.orders
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc)).toList());
  }

  /// 특정 주문 가져오기
  Future<Order?> getOrder(String orderId) async {
    final doc = await _firestoreService.orders.doc(orderId).get();
    if (!doc.exists) return null;
    return Order.fromFirestore(doc);
  }

  /// 이벤트별 주문 목록 (어드민)
  Stream<List<Order>> getOrdersByEvent(String eventId) {
    return _firestoreService.orders
        .where('eventId', isEqualTo: eventId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc)).toList());
  }

  /// 결제 완료된 주문 목록 (어드민)
  Stream<List<Order>> getPaidOrdersByEvent(String eventId) {
    return _firestoreService.orders
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'paid')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc)).toList());
  }
}

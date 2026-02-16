import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/ticket.dart';

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  return TicketRepository(ref.watch(firestoreServiceProvider));
});

/// 내 티켓 목록
final myTicketsStreamProvider =
    StreamProvider.family<List<Ticket>, String>((ref, userId) {
  return ref.watch(ticketRepositoryProvider).getTicketsByUser(userId);
});

class TicketRepository {
  final FirestoreService _firestoreService;

  TicketRepository(this._firestoreService);

  /// 사용자별 티켓 목록
  Stream<List<Ticket>> getTicketsByUser(String userId) {
    return _firestoreService.tickets
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final tickets =
          snapshot.docs.map((doc) => Ticket.fromFirestore(doc)).toList();
      tickets.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      return tickets;
    });
  }

  /// 특정 티켓 가져오기
  Future<Ticket?> getTicket(String ticketId) async {
    final doc = await _firestoreService.tickets.doc(ticketId).get();
    if (!doc.exists) return null;
    return Ticket.fromFirestore(doc);
  }

  /// 특정 티켓 스트림
  Stream<Ticket?> getTicketStream(String ticketId) {
    return _firestoreService.tickets.doc(ticketId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Ticket.fromFirestore(doc);
    });
  }

  /// 주문별 티켓 목록
  Future<List<Ticket>> getTicketsByOrder(String orderId) async {
    final snapshot = await _firestoreService.tickets
        .where('orderId', isEqualTo: orderId)
        .get();
    return snapshot.docs.map((doc) => Ticket.fromFirestore(doc)).toList();
  }

  /// 이벤트별 티켓 목록 (어드민)
  Stream<List<Ticket>> getTicketsByEvent(String eventId) {
    return _firestoreService.tickets
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Ticket.fromFirestore(doc)).toList());
  }
}

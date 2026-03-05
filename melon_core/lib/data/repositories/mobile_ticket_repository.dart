import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/mobile_ticket.dart';

final mobileTicketRepositoryProvider =
    Provider<MobileTicketRepository>((ref) {
  return MobileTicketRepository(ref.watch(firestoreServiceProvider));
});

/// 이벤트별 모바일 티켓 스트림
final mobileTicketsStreamProvider =
    StreamProvider.family<List<MobileTicket>, String>((ref, eventId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.mobileTickets
      .where('eventId', isEqualTo: eventId)
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((d) => MobileTicket.fromFirestore(d)).toList();
        list.sort((a, b) => a.entryNumber.compareTo(b.entryNumber));
        return list;
      });
});

/// 네이버 주문별 모바일 티켓 스트림
final mobileTicketsByOrderProvider =
    StreamProvider.family<List<MobileTicket>, String>((ref, naverOrderId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.mobileTickets
      .where('naverOrderId', isEqualTo: naverOrderId)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => MobileTicket.fromFirestore(d)).toList());
});

class MobileTicketRepository {
  final FirestoreService _fs;

  MobileTicketRepository(this._fs);

  /// 이벤트별 티켓 목록
  Future<List<MobileTicket>> getTicketsByEvent(String eventId) async {
    final snap = await _fs.mobileTickets
        .where('eventId', isEqualTo: eventId)
        .get();
    final list = snap.docs.map((d) => MobileTicket.fromFirestore(d)).toList();
    list.sort((a, b) => a.entryNumber.compareTo(b.entryNumber));
    return list;
  }

  /// 네이버 주문별 티켓 목록
  Future<List<MobileTicket>> getTicketsByOrder(String naverOrderId) async {
    final snap = await _fs.mobileTickets
        .where('naverOrderId', isEqualTo: naverOrderId)
        .get();
    return snap.docs.map((d) => MobileTicket.fromFirestore(d)).toList();
  }

  /// accessToken으로 티켓 조회
  Future<MobileTicket?> getByAccessToken(String accessToken) async {
    final snap = await _fs.mobileTickets
        .where('accessToken', isEqualTo: accessToken)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return MobileTicket.fromFirestore(snap.docs.first);
  }

  /// 단일 티켓 조회
  Future<MobileTicket?> getTicket(String ticketId) async {
    final doc = await _fs.mobileTickets.doc(ticketId).get();
    if (!doc.exists) return null;
    return MobileTicket.fromFirestore(doc);
  }

  /// 티켓 스트림
  Stream<MobileTicket?> ticketStream(String ticketId) {
    return _fs.mobileTickets.doc(ticketId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return MobileTicket.fromFirestore(doc);
    });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/event.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.watch(firestoreServiceProvider));
});

/// 공연 목록 스트림
final eventsStreamProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(eventRepositoryProvider).getActiveEvents();
});

/// 특정 공연 스트림
final eventStreamProvider = StreamProvider.family<Event?, String>((ref, eventId) {
  return ref.watch(eventRepositoryProvider).getEventStream(eventId);
});

/// 전체 공연 스트림 (통계용 – 상태 무관)
final allEventsStreamProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(eventRepositoryProvider).getAllEvents();
});

class EventRepository {
  final FirestoreService _firestoreService;

  EventRepository(this._firestoreService);

  /// 전체 공연 목록 (상태 무관, 통계용)
  Stream<List<Event>> getAllEvents() {
    return _firestoreService.events
        .orderBy('startAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList());
  }

  /// 활성 공연 목록 (판매중/예정)
  Stream<List<Event>> getActiveEvents() {
    return _firestoreService.events
        .where('status', whereIn: ['active', 'draft'])
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList());
  }

  /// 특정 공연 스트림
  Stream<Event?> getEventStream(String eventId) {
    return _firestoreService.events.doc(eventId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Event.fromFirestore(doc);
    });
  }

  /// 특정 공연 가져오기
  Future<Event?> getEvent(String eventId) async {
    final doc = await _firestoreService.events.doc(eventId).get();
    if (!doc.exists) return null;
    return Event.fromFirestore(doc);
  }

  /// 공연 생성 (어드민)
  Future<String> createEvent(Event event) async {
    final docRef = await _firestoreService.events.add(event.toMap());
    return docRef.id;
  }

  /// 공연 업데이트 (어드민)
  Future<void> updateEvent(String eventId, Map<String, dynamic> data) async {
    await _firestoreService.events.doc(eventId).update(data);
  }

  /// 남은 좌석 수 감소
  Future<void> decreaseAvailableSeats(String eventId, int count) async {
    await _firestoreService.events.doc(eventId).update({
      'availableSeats': FieldValue.increment(-count),
    });
  }
}

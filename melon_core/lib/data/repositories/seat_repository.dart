import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/seat.dart';
import '../models/seat_block.dart';

final seatRepositoryProvider = Provider<SeatRepository>((ref) {
  return SeatRepository(ref.watch(firestoreServiceProvider));
});

/// 이벤트별 좌석 스트림 프로바이더
final seatsStreamProvider =
    StreamProvider.family<List<Seat>, String>((ref, eventId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.seats
      .where('eventId', isEqualTo: eventId)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map((doc) => Seat.fromFirestore(doc)).toList());
});

class SeatRepository {
  final FirestoreService _firestoreService;

  SeatRepository(this._firestoreService);

  /// 특정 좌석 가져오기
  Future<Seat?> getSeat(String seatId) async {
    final doc = await _firestoreService.seats.doc(seatId).get();
    if (!doc.exists) return null;
    return Seat.fromFirestore(doc);
  }

  /// 이벤트별 좌석 목록
  Future<List<Seat>> getSeatsByEvent(String eventId) async {
    final snapshot = await _firestoreService.seats
        .where('eventId', isEqualTo: eventId)
        .get();
    return snapshot.docs.map((doc) => Seat.fromFirestore(doc)).toList();
  }

  /// 이벤트별 좌석 블록 목록 (어드민)
  Stream<List<SeatBlock>> getSeatBlocksByEvent(String eventId) {
    return _firestoreService.seatBlocks
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => SeatBlock.fromFirestore(doc)).toList());
  }

  /// 특정 좌석 블록
  Future<SeatBlock?> getSeatBlock(String seatBlockId) async {
    final doc = await _firestoreService.seatBlocks.doc(seatBlockId).get();
    if (!doc.exists) return null;
    return SeatBlock.fromFirestore(doc);
  }

  /// 주문별 좌석 블록
  Future<SeatBlock?> getSeatBlockByOrder(String orderId) async {
    final snapshot = await _firestoreService.seatBlocks
        .where('orderId', isEqualTo: orderId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return SeatBlock.fromFirestore(snapshot.docs.first);
  }

  /// 여러 좌석 가져오기
  Future<List<Seat>> getSeatsByIds(List<String> seatIds) async {
    if (seatIds.isEmpty) return [];

    // Firestore where in 쿼리는 10개 제한이 있으므로 분할
    final List<Seat> allSeats = [];
    for (var i = 0; i < seatIds.length; i += 10) {
      final chunk =
          seatIds.sublist(i, i + 10 > seatIds.length ? seatIds.length : i + 10);
      final snapshot =
          await _firestoreService.seats.where('__name__', whereIn: chunk).get();
      allSeats.addAll(snapshot.docs.map((doc) => Seat.fromFirestore(doc)));
    }
    return allSeats;
  }

  /// Layout 기반 좌석 일괄 생성 (도트맵 좌표 포함)
  Future<int> createSeatsFromLayout(
      String eventId, List<Map<String, dynamic>> seatData) async {
    var batch = _firestoreService.batch();
    var pending = 0;
    int count = 0;

    for (final data in seatData) {
      final block = data['block'] as String;
      final floor = data['floor'] as String;
      final row = data['row'] as String?;
      final number = data['number'] as int;
      final grade = data['grade'] as String?;
      final gridX = data['gridX'] as int?;
      final gridY = data['gridY'] as int?;
      final seatType = data['seatType'] as String? ?? 'normal';

      final seatKey = row != null && row.isNotEmpty
          ? '$block-$floor-$row-$number'
          : '$block-$floor-$number';

      final docRef = _firestoreService.seats.doc();
      batch.set(docRef, {
        'eventId': eventId,
        'block': block,
        'floor': floor,
        'row': row,
        'number': number,
        'seatKey': seatKey,
        'grade': grade,
        'status': SeatStatus.available.name,
        if (gridX != null) 'gridX': gridX,
        if (gridY != null) 'gridY': gridY,
        'seatType': seatType,
      });
      count++;
      pending++;

      if (pending == 500) {
        await batch.commit();
        batch = _firestoreService.batch();
        pending = 0;
      }
    }
    if (pending > 0) {
      await batch.commit();
    }
    return count;
  }

  /// CSV로 좌석 일괄 생성 (어드민)
  Future<int> createSeatsFromCsv(
      String eventId, List<Map<String, dynamic>> seatData) async {
    var batch = _firestoreService.batch();
    var pending = 0;
    int count = 0;

    for (final data in seatData) {
      final block = data['block'] as String;
      final floor = data['floor'] as String;
      final row = data['row'] as String?;
      final number = data['number'] as int;
      final grade = data['grade'] as String?;

      final seatKey = row != null && row.isNotEmpty
          ? '$block-$floor-$row-$number'
          : '$block-$floor-$number';

      final docRef = _firestoreService.seats.doc();
      batch.set(docRef, {
        'eventId': eventId,
        'block': block,
        'floor': floor,
        'row': row,
        'number': number,
        'seatKey': seatKey,
        'grade': grade,
        'status': SeatStatus.available.name,
      });
      count++;
      pending++;

      // 500개마다 커밋 (Firestore 배치 제한)
      if (pending == 500) {
        await batch.commit();
        batch = _firestoreService.batch();
        pending = 0;
      }
    }

    // 남은 것 커밋
    if (pending > 0) {
      await batch.commit();
    }

    return count;
  }
}

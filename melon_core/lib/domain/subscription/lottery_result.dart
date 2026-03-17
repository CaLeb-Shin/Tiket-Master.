import 'package:cloud_firestore/cloud_firestore.dart';

class LotteryResult {
  final String id;
  final String eventId;
  final String seatGrade;
  final int totalEntries;
  final int totalSeats;
  final List<String> winnerUserIds;
  final List<String> winnerEntryIds;
  final int guaranteedWinners;
  final int remainingSeatsReleased; // 잔여석 → 일반 판매 전환 수
  final DateTime runAt;

  LotteryResult({
    required this.id,
    required this.eventId,
    required this.seatGrade,
    required this.totalEntries,
    required this.totalSeats,
    required this.winnerUserIds,
    required this.winnerEntryIds,
    this.guaranteedWinners = 0,
    this.remainingSeatsReleased = 0,
    required this.runAt,
  });

  factory LotteryResult.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return LotteryResult(
      id: doc.id,
      eventId: d['eventId'] ?? '',
      seatGrade: d['seatGrade'] ?? '',
      totalEntries: d['totalEntries'] ?? 0,
      totalSeats: d['totalSeats'] ?? 0,
      winnerUserIds: d['winnerUserIds'] != null
          ? List<String>.from(d['winnerUserIds'])
          : [],
      winnerEntryIds: d['winnerEntryIds'] != null
          ? List<String>.from(d['winnerEntryIds'])
          : [],
      guaranteedWinners: d['guaranteedWinners'] ?? 0,
      remainingSeatsReleased: d['remainingSeatsReleased'] ?? 0,
      runAt: (d['runAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'seatGrade': seatGrade,
      'totalEntries': totalEntries,
      'totalSeats': totalSeats,
      'winnerUserIds': winnerUserIds,
      'winnerEntryIds': winnerEntryIds,
      'guaranteedWinners': guaranteedWinners,
      'remainingSeatsReleased': remainingSeatsReleased,
      'runAt': Timestamp.fromDate(runAt),
    };
  }

  double get winRate =>
      totalEntries > 0 ? winnerUserIds.length / totalEntries : 0;
}

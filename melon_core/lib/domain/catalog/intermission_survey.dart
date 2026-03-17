import 'package:cloud_firestore/cloud_firestore.dart';

class IntermissionSurvey {
  final String id;
  final String ticketId;
  final String eventId;
  final int rating; // 1~5
  final String bestMoment; // 객관식 선택
  final String? comment; // 한줄평 (선택)
  final bool mileageAwarded;
  final DateTime createdAt;

  IntermissionSurvey({
    required this.id,
    required this.ticketId,
    required this.eventId,
    required this.rating,
    required this.bestMoment,
    this.comment,
    this.mileageAwarded = false,
    required this.createdAt,
  });

  factory IntermissionSurvey.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return IntermissionSurvey(
      id: doc.id,
      ticketId: d['ticketId'] ?? '',
      eventId: d['eventId'] ?? '',
      rating: d['rating'] ?? 3,
      bestMoment: d['bestMoment'] ?? '',
      comment: d['comment'],
      mileageAwarded: d['mileageAwarded'] ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ticketId': ticketId,
      'eventId': eventId,
      'rating': rating,
      'bestMoment': bestMoment,
      if (comment != null) 'comment': comment,
      'mileageAwarded': mileageAwarded,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

/// 인터미션 설문 - 가장 좋았던 순간 선택지
class BestMomentOption {
  final String value;
  final String label;
  final String emoji;

  const BestMomentOption(this.value, this.label, this.emoji);

  static const List<BestMomentOption> options = [
    BestMomentOption('performance', '연주/공연', '🎵'),
    BestMomentOption('atmosphere', '분위기/무대', '✨'),
    BestMomentOption('emotion', '감동적인 순간', '💫'),
    BestMomentOption('overall', '전체적으로 좋았어요', '👏'),
  ];
}

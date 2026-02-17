import 'package:cloud_firestore/cloud_firestore.dart';

/// 티켓 모델
class Ticket {
  final String id;
  final String eventId;
  final String orderId;
  final String userId;
  final String seatId;
  final String seatBlockId;
  final TicketStatus status;
  final int qrVersion; // QR 버전 (재발급 시 증가)
  final DateTime issuedAt;
  final DateTime? entryCheckedInAt;
  final DateTime? intermissionCheckedInAt;
  final DateTime? usedAt;
  final DateTime? canceledAt;
  final String? lastCheckInStage;

  Ticket({
    required this.id,
    required this.eventId,
    required this.orderId,
    required this.userId,
    required this.seatId,
    required this.seatBlockId,
    required this.status,
    required this.qrVersion,
    required this.issuedAt,
    this.entryCheckedInAt,
    this.intermissionCheckedInAt,
    this.usedAt,
    this.canceledAt,
    this.lastCheckInStage,
  });

  factory Ticket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Ticket(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      orderId: data['orderId'] ?? '',
      userId: data['userId'] ?? '',
      seatId: data['seatId'] ?? '',
      seatBlockId: data['seatBlockId'] ?? '',
      status: TicketStatus.fromString(data['status']),
      qrVersion: data['qrVersion'] ?? 1,
      issuedAt: (data['issuedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      entryCheckedInAt: (data['entryCheckedInAt'] as Timestamp?)?.toDate(),
      intermissionCheckedInAt:
          (data['intermissionCheckedInAt'] as Timestamp?)?.toDate(),
      usedAt: (data['usedAt'] as Timestamp?)?.toDate(),
      canceledAt: (data['canceledAt'] as Timestamp?)?.toDate(),
      lastCheckInStage: data['lastCheckInStage'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'orderId': orderId,
      'userId': userId,
      'seatId': seatId,
      'seatBlockId': seatBlockId,
      'status': status.name,
      'qrVersion': qrVersion,
      'issuedAt': Timestamp.fromDate(issuedAt),
      'entryCheckedInAt': entryCheckedInAt != null
          ? Timestamp.fromDate(entryCheckedInAt!)
          : null,
      'intermissionCheckedInAt': intermissionCheckedInAt != null
          ? Timestamp.fromDate(intermissionCheckedInAt!)
          : null,
      'usedAt': usedAt != null ? Timestamp.fromDate(usedAt!) : null,
      'canceledAt': canceledAt != null ? Timestamp.fromDate(canceledAt!) : null,
      'lastCheckInStage': lastCheckInStage,
    };
  }

  bool get isEntryCheckedIn => entryCheckedInAt != null;
  bool get isIntermissionCheckedIn => intermissionCheckedInAt != null;
  bool get hasAnyCheckin => isEntryCheckedIn || isIntermissionCheckedIn;
}

enum TicketStatus {
  issued, // 발급됨
  used, // 사용됨 (입장 완료)
  canceled; // 취소됨

  static TicketStatus fromString(String? value) {
    return TicketStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TicketStatus.issued,
    );
  }

  String get displayName {
    switch (this) {
      case TicketStatus.issued:
        return '사용 가능';
      case TicketStatus.used:
        return '입장 완료';
      case TicketStatus.canceled:
        return '취소됨';
    }
  }
}

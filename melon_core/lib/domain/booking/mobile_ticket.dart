import 'package:cloud_firestore/cloud_firestore.dart';

/// 네이버 구매자용 모바일 티켓 모델
class MobileTicket {
  final String id;
  final String naverOrderId; // NaverOrder doc ID
  final String eventId;
  final String seatGrade; // VIP, R, S, A
  final String? seatId; // Firestore seat doc ID (공개 전 null)
  final String? seatNumber; // 표시용 좌석번호 (공개 전 null)
  final String? seatInfo; // "1층 B블록 3열 15번" 등
  final String? userId; // 연결된 사용자 (NaverOrder claim 시 설정)
  final String buyerName;
  final String buyerPhone;
  final MobileTicketStatus status;
  final DateTime issuedAt;
  final DateTime? usedAt;
  final DateTime? cancelledAt;
  final int qrVersion; // QR 재발급 시 증가
  final String accessToken; // UUID v4 — URL 접근용
  final int entryNumber; // 등급 내 선착순 번호
  final DateTime? entryCheckedInAt;
  final DateTime? intermissionCheckedInAt;
  final String? lastCheckInStage;
  final String? recipientName; // 전달받은 사람 이름
  final DateTime? seatSelectionDeadline; // 지정석 좌석 선택 마감 (designated 모드)
  final int seatChangeCount; // 좌석 변경 횟수 (최대 1회)

  MobileTicket({
    required this.id,
    required this.naverOrderId,
    required this.eventId,
    required this.seatGrade,
    this.seatId,
    this.seatNumber,
    this.seatInfo,
    this.userId,
    required this.buyerName,
    required this.buyerPhone,
    required this.status,
    required this.issuedAt,
    this.usedAt,
    this.cancelledAt,
    this.qrVersion = 1,
    required this.accessToken,
    required this.entryNumber,
    this.entryCheckedInAt,
    this.intermissionCheckedInAt,
    this.lastCheckInStage,
    this.recipientName,
    this.seatSelectionDeadline,
    this.seatChangeCount = 0,
  });

  factory MobileTicket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MobileTicket(
      id: doc.id,
      naverOrderId: data['naverOrderId'] ?? '',
      eventId: data['eventId'] ?? '',
      seatGrade: data['seatGrade'] ?? '',
      seatId: data['seatId'],
      seatNumber: data['seatNumber'],
      seatInfo: data['seatInfo'],
      userId: data['userId'],
      buyerName: data['buyerName'] ?? '',
      buyerPhone: data['buyerPhone'] ?? '',
      status: MobileTicketStatus.fromString(data['status']),
      issuedAt:
          (data['issuedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      usedAt: (data['usedAt'] as Timestamp?)?.toDate(),
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
      qrVersion: data['qrVersion'] ?? 1,
      accessToken: data['accessToken'] ?? '',
      entryNumber: data['entryNumber'] ?? 0,
      entryCheckedInAt:
          (data['entryCheckedInAt'] as Timestamp?)?.toDate(),
      intermissionCheckedInAt:
          (data['intermissionCheckedInAt'] as Timestamp?)?.toDate(),
      lastCheckInStage: data['lastCheckInStage'],
      recipientName: data['recipientName'],
      seatSelectionDeadline:
          (data['seatSelectionDeadline'] as Timestamp?)?.toDate(),
      seatChangeCount: data['seatChangeCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'naverOrderId': naverOrderId,
      'eventId': eventId,
      'seatGrade': seatGrade,
      'seatId': seatId,
      'seatNumber': seatNumber,
      'seatInfo': seatInfo,
      if (userId != null) 'userId': userId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'status': status.name,
      'issuedAt': Timestamp.fromDate(issuedAt),
      'usedAt': usedAt != null ? Timestamp.fromDate(usedAt!) : null,
      'cancelledAt':
          cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      'qrVersion': qrVersion,
      'accessToken': accessToken,
      'entryNumber': entryNumber,
      'entryCheckedInAt': entryCheckedInAt != null
          ? Timestamp.fromDate(entryCheckedInAt!)
          : null,
      'intermissionCheckedInAt': intermissionCheckedInAt != null
          ? Timestamp.fromDate(intermissionCheckedInAt!)
          : null,
      'lastCheckInStage': lastCheckInStage,
      if (recipientName != null) 'recipientName': recipientName,
      if (seatSelectionDeadline != null)
        'seatSelectionDeadline':
            Timestamp.fromDate(seatSelectionDeadline!),
      'seatChangeCount': seatChangeCount,
    };
  }

  bool get isCheckedIn => entryCheckedInAt != null;
  bool get isIntermissionCheckedIn => intermissionCheckedInAt != null;

  /// 좌석 선택 가능 여부 (designated 모드)
  bool get canSelectSeat =>
      seatId == null &&
      status == MobileTicketStatus.active &&
      seatSelectionDeadline != null &&
      DateTime.now().isBefore(seatSelectionDeadline!);

  /// 좌석 변경 가능 여부 (1회 제한)
  bool get canChangeSeat =>
      seatId != null &&
      status == MobileTicketStatus.active &&
      seatChangeCount < 1;
}

enum MobileTicketStatus {
  active, // 사용 가능
  cancelled, // 취소됨
  used; // 입장 완료

  static MobileTicketStatus fromString(String? value) {
    return MobileTicketStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MobileTicketStatus.active,
    );
  }

  String get displayName {
    switch (this) {
      case MobileTicketStatus.active:
        return '사용 가능';
      case MobileTicketStatus.cancelled:
        return '취소됨';
      case MobileTicketStatus.used:
        return '입장 완료';
    }
  }
}

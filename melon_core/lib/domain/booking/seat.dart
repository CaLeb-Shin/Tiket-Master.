import 'package:cloud_firestore/cloud_firestore.dart';

/// 좌석 모델 - 개별 좌석 정보
class Seat {
  final String id;
  final String eventId;
  final String block; // 구역 (A, B, VIP 등)
  final String floor; // 층 (1층, 2층 등)
  final String? row; // 열 (선택, A, B, 1, 2 등)
  final int number; // 좌석 번호
  final String seatKey; // 유니크 키: "block-floor-row-number"
  final String? grade; // 좌석 등급 (VIP, R, S, A 등)
  final SeatStatus status;
  final String? orderId; // 예약된 경우 주문 ID
  final DateTime? reservedAt;
  final double? dotX; // 도트맵 X 좌표 (자유 좌표 px)
  final double? dotY; // 도트맵 Y 좌표 (자유 좌표 px)
  final String seatType; // 좌석 유형 (normal/wheelchair/reserved_hold)
  final String? heldBy; // 선점 유저 UID (5분 홀드)
  final DateTime? heldUntil; // 선점 만료 시각

  Seat({
    required this.id,
    required this.eventId,
    required this.block,
    required this.floor,
    this.row,
    required this.number,
    required this.seatKey,
    this.grade,
    required this.status,
    this.orderId,
    this.reservedAt,
    this.dotX,
    this.dotY,
    this.seatType = 'normal',
    this.heldBy,
    this.heldUntil,
  });

  /// 현재 다른 유저에 의해 선점(hold) 중인지 확인
  bool isHeldByOther(String? currentUserId) {
    if (heldBy == null || heldUntil == null) return false;
    if (heldBy == currentUserId) return false;
    return heldUntil!.isAfter(DateTime.now());
  }

  /// 현재 유저가 선점 중인지 확인
  bool isHeldByMe(String? currentUserId) {
    if (heldBy == null || heldUntil == null || currentUserId == null) return false;
    if (heldBy != currentUserId) return false;
    return heldUntil!.isAfter(DateTime.now());
  }

  /// 좌석 표시 문자열
  String get displayName {
    if (row != null && row!.isNotEmpty) {
      return '$block구역 $floor $row열 $number번';
    }
    return '$block구역 $floor $number번';
  }

  /// 짧은 표시
  String get shortName {
    if (row != null && row!.isNotEmpty) {
      return '$block-$floor-$row-$number';
    }
    return '$block-$floor-$number';
  }

  factory Seat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Seat(
      id: doc.id,
      eventId: data['eventId'] ?? '',
      block: data['block'] ?? '',
      floor: data['floor'] ?? '',
      row: data['row'],
      number: data['number'] ?? 0,
      seatKey: data['seatKey'] ?? '',
      grade: data['grade'],
      status: SeatStatus.fromString(data['status']),
      orderId: data['orderId'],
      reservedAt: (data['reservedAt'] as Timestamp?)?.toDate(),
      dotX: (data['dotX'] ?? data['gridX'])?.toDouble(),
      dotY: (data['dotY'] ?? data['gridY'])?.toDouble(),
      seatType: data['seatType'] ?? 'normal',
      heldBy: data['heldBy'],
      heldUntil: (data['heldUntil'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'block': block,
      'floor': floor,
      'row': row,
      'number': number,
      'seatKey': seatKey,
      'grade': grade,
      'status': status.name,
      'orderId': orderId,
      'reservedAt': reservedAt != null ? Timestamp.fromDate(reservedAt!) : null,
      if (dotX != null) 'dotX': dotX,
      if (dotY != null) 'dotY': dotY,
      if (dotX != null) 'gridX': dotX!.toInt(), // 레거시 호환
      if (dotY != null) 'gridY': dotY!.toInt(), // 레거시 호환
      'seatType': seatType,
      if (heldBy != null) 'heldBy': heldBy,
      if (heldUntil != null) 'heldUntil': Timestamp.fromDate(heldUntil!),
    };
  }

  Seat copyWith({
    SeatStatus? status,
    String? orderId,
    DateTime? reservedAt,
    String? grade,
    double? dotX,
    double? dotY,
    String? seatType,
    String? heldBy,
    DateTime? heldUntil,
  }) {
    return Seat(
      id: id,
      eventId: eventId,
      block: block,
      floor: floor,
      row: row,
      number: number,
      seatKey: seatKey,
      grade: grade ?? this.grade,
      status: status ?? this.status,
      orderId: orderId ?? this.orderId,
      reservedAt: reservedAt ?? this.reservedAt,
      dotX: dotX ?? this.dotX,
      dotY: dotY ?? this.dotY,
      seatType: seatType ?? this.seatType,
      heldBy: heldBy ?? this.heldBy,
      heldUntil: heldUntil ?? this.heldUntil,
    );
  }
}

enum SeatStatus {
  available, // 구매 가능
  reserved, // 예약됨 (결제 완료)
  used, // 입장 완료
  blocked; // 판매 불가 (운영 차단)

  static SeatStatus fromString(String? value) {
    return SeatStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SeatStatus.available,
    );
  }
}

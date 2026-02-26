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
  final int? gridX; // 도트맵 X 좌표
  final int? gridY; // 도트맵 Y 좌표
  final String seatType; // 좌석 유형 (normal/wheelchair/reserved_hold)

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
    this.gridX,
    this.gridY,
    this.seatType = 'normal',
  });

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
      gridX: data['gridX'],
      gridY: data['gridY'],
      seatType: data['seatType'] ?? 'normal',
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
      if (gridX != null) 'gridX': gridX,
      if (gridY != null) 'gridY': gridY,
      'seatType': seatType,
    };
  }

  Seat copyWith({
    SeatStatus? status,
    String? orderId,
    DateTime? reservedAt,
    String? grade,
    int? gridX,
    int? gridY,
    String? seatType,
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
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      seatType: seatType ?? this.seatType,
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

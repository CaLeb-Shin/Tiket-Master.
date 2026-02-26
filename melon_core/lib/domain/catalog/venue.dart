import 'package:cloud_firestore/cloud_firestore.dart';

/// 공연장 모델
class Venue {
  final String id;
  final String name;
  final String? address;
  final String? seatMapImageUrl; // 좌석배치도 이미지
  final String? thumbnailUrl; // 공연장 대표 이미지
  final String stagePosition; // 무대 위치 (top | bottom)
  final List<VenueFloor> floors; // 층별 정보
  final int totalSeats;
  final bool hasSeatView; // 시점 이미지 등록 여부
  final VenueSeatLayout? seatLayout; // 도트맵 좌석 배치도
  final DateTime createdAt;

  Venue({
    required this.id,
    required this.name,
    this.address,
    this.seatMapImageUrl,
    this.thumbnailUrl,
    this.stagePosition = 'top',
    required this.floors,
    required this.totalSeats,
    this.hasSeatView = false,
    this.seatLayout,
    required this.createdAt,
  });

  factory Venue.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawStagePosition =
        (data['stagePosition'] as String?)?.toLowerCase().trim();
    final stagePosition = rawStagePosition == 'bottom' ? 'bottom' : 'top';
    return Venue(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'],
      seatMapImageUrl: data['seatMapImageUrl'],
      thumbnailUrl: data['thumbnailUrl'],
      stagePosition: stagePosition,
      floors: (data['floors'] as List<dynamic>?)
              ?.map((f) => VenueFloor.fromMap(f))
              .toList() ??
          [],
      totalSeats: data['totalSeats'] ?? 0,
      hasSeatView: data['hasSeatView'] ?? false,
      seatLayout: data['seatLayout'] != null
          ? VenueSeatLayout.fromMap(data['seatLayout'] as Map<String, dynamic>)
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'seatMapImageUrl': seatMapImageUrl,
      'thumbnailUrl': thumbnailUrl,
      'stagePosition': stagePosition,
      'floors': floors.map((f) => f.toMap()).toList(),
      'totalSeats': totalSeats,
      'hasSeatView': hasSeatView,
      if (seatLayout != null) 'seatLayout': seatLayout!.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 모든 블록에서 사용되는 등급 목록 추출
  Set<String> get availableGrades {
    final grades = <String>{};
    for (final floor in floors) {
      for (final block in floor.blocks) {
        if (block.grade != null) grades.add(block.grade!);
      }
    }
    return grades;
  }
}

/// 층 정보
class VenueFloor {
  final String name; // 1층, 2층 등
  final List<VenueBlock> blocks;
  final int totalSeats;

  VenueFloor({
    required this.name,
    required this.blocks,
    required this.totalSeats,
  });

  factory VenueFloor.fromMap(Map<String, dynamic> map) {
    return VenueFloor(
      name: map['name'] ?? '',
      blocks: (map['blocks'] as List<dynamic>?)
              ?.map((b) => VenueBlock.fromMap(b))
              .toList() ??
          [],
      totalSeats: map['totalSeats'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'blocks': blocks.map((b) => b.toMap()).toList(),
      'totalSeats': totalSeats,
    };
  }
}

/// 구역 정보
class VenueBlockCustomRow {
  final String name; // 표시용 행 이름
  final int seatCount; // 해당 행 좌석 수
  final int offset; // 배치도 미리보기 오프셋(음수: 왼쪽, 양수: 오른쪽)

  const VenueBlockCustomRow({
    required this.name,
    required this.seatCount,
    this.offset = 0,
  });

  factory VenueBlockCustomRow.fromMap(Map<String, dynamic> map) {
    return VenueBlockCustomRow(
      name: (map['name'] ?? '').toString(),
      seatCount: map['seatCount'] ?? 0,
      offset: map['offset'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'seatCount': seatCount,
      'offset': offset,
    };
  }
}

/// 구역 정보
class VenueBlock {
  final String name; // A, B, C 등
  final int rows; // 총 열 수
  final int seatsPerRow; // 열당 좌석 수
  final int totalSeats;
  final String? grade; // 좌석 등급 (VIP, R, S, A 등)
  final int? price; // 가격
  final int layoutRow; // 무대 기준 배치 줄 (0부터 시작)
  final int layoutOffset; // 좌우 배치 오프셋 (음수: 좌, 양수: 우)
  final String layoutDirection; // 배치도 렌더링 방향 (horizontal | vertical)
  final List<VenueBlockCustomRow> customRows; // 자유 편집 행 데이터

  VenueBlock({
    required this.name,
    required this.rows,
    required this.seatsPerRow,
    required this.totalSeats,
    this.grade,
    this.price,
    this.layoutRow = 0,
    this.layoutOffset = 0,
    this.layoutDirection = 'horizontal',
    this.customRows = const [],
  });

  factory VenueBlock.fromMap(Map<String, dynamic> map) {
    final rawDirection =
        (map['layoutDirection'] as String?)?.toLowerCase().trim();
    final layoutDirection =
        rawDirection == 'vertical' ? 'vertical' : 'horizontal';
    final layoutRow = (map['layoutRow'] as num?)?.toInt() ?? 0;
    final layoutOffset = (map['layoutOffset'] as num?)?.toInt() ?? 0;
    final customRows = (map['customRows'] as List<dynamic>?)
            ?.map(
              (row) => VenueBlockCustomRow.fromMap(
                row as Map<String, dynamic>,
              ),
            )
            .toList() ??
        const <VenueBlockCustomRow>[];
    return VenueBlock(
      name: map['name'] ?? '',
      rows: map['rows'] ?? 0,
      seatsPerRow: map['seatsPerRow'] ?? 0,
      totalSeats: map['totalSeats'] ?? 0,
      grade: map['grade'],
      price: map['price'],
      layoutRow: layoutRow,
      layoutOffset: layoutOffset,
      layoutDirection: layoutDirection,
      customRows: customRows,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'rows': rows,
      'seatsPerRow': seatsPerRow,
      'totalSeats': totalSeats,
      'grade': grade,
      'price': price,
      'layoutRow': layoutRow,
      'layoutOffset': layoutOffset,
      'layoutDirection': layoutDirection,
      'customRows': customRows.map((row) => row.toMap()).toList(),
    };
  }
}

// ─── 도트맵 좌석 배치도 ───

/// 좌석 유형
enum SeatType {
  normal,       // 일반석
  wheelchair,   // 장애인석
  reservedHold; // 유보석 (판매 보류)

  static SeatType fromString(String? value) {
    return SeatType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SeatType.normal,
    );
  }

  String get displayName {
    switch (this) {
      case SeatType.normal:
        return '일반석';
      case SeatType.wheelchair:
        return '장애인석';
      case SeatType.reservedHold:
        return '유보석';
    }
  }
}

/// 좌석 배치도에서의 개별 좌석 위치
class LayoutSeat {
  final int gridX;
  final int gridY;
  final String zone;       // 구역 (A, B, C 등)
  final String floor;      // 층 (1층, 2층 등)
  final String row;        // 열 이름 (1, 2, A, B 등)
  final int number;        // 좌석 번호
  final String grade;      // 등급 (VIP, R, S, A)
  final SeatType seatType; // 좌석 유형

  LayoutSeat({
    required this.gridX,
    required this.gridY,
    this.zone = '',
    this.floor = '1층',
    this.row = '',
    this.number = 0,
    required this.grade,
    this.seatType = SeatType.normal,
  });

  String get key => '$gridX,$gridY';

  factory LayoutSeat.fromMap(Map<String, dynamic> map) {
    return LayoutSeat(
      gridX: map['x'] ?? 0,
      gridY: map['y'] ?? 0,
      zone: map['zone'] ?? '',
      floor: map['floor'] ?? '1층',
      row: map['row'] ?? '',
      number: map['number'] ?? 0,
      grade: map['grade'] ?? 'A',
      seatType: SeatType.fromString(map['type']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': gridX,
      'y': gridY,
      'zone': zone,
      'floor': floor,
      'row': row,
      'number': number,
      'grade': grade,
      'type': seatType.name,
    };
  }

  LayoutSeat copyWith({
    int? gridX,
    int? gridY,
    String? zone,
    String? floor,
    String? row,
    int? number,
    String? grade,
    SeatType? seatType,
  }) {
    return LayoutSeat(
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      zone: zone ?? this.zone,
      floor: floor ?? this.floor,
      row: row ?? this.row,
      number: number ?? this.number,
      grade: grade ?? this.grade,
      seatType: seatType ?? this.seatType,
    );
  }
}

/// 공연장 좌석 배치도 (도트 그리드 기반)
class VenueSeatLayout {
  final int gridCols;
  final int gridRows;
  final String stagePosition; // top / bottom
  final List<LayoutSeat> seats;
  final Map<String, int> gradePrice; // 등급별 가격

  VenueSeatLayout({
    this.gridCols = 60,
    this.gridRows = 40,
    this.stagePosition = 'top',
    this.seats = const [],
    this.gradePrice = const {},
  });

  int get totalSeats => seats.length;

  Map<String, int> get seatCountByGrade {
    final counts = <String, int>{};
    for (final seat in seats) {
      counts[seat.grade] = (counts[seat.grade] ?? 0) + 1;
    }
    return counts;
  }

  factory VenueSeatLayout.fromMap(Map<String, dynamic>? data) {
    if (data == null) return VenueSeatLayout();
    return VenueSeatLayout(
      gridCols: data['gridCols'] ?? 60,
      gridRows: data['gridRows'] ?? 40,
      stagePosition: data['stagePosition'] ?? 'top',
      seats: (data['seats'] as List<dynamic>?)
              ?.map((s) => LayoutSeat.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      gradePrice: Map<String, int>.from(data['gradePrice'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'gridCols': gridCols,
      'gridRows': gridRows,
      'stagePosition': stagePosition,
      'seats': seats.map((s) => s.toMap()).toList(),
      'gradePrice': gradePrice,
    };
  }
}

/// 좌석 등급
class SeatGrade {
  final String name; // VIP, R, S, A 등
  final int price;
  final String colorHex; // 색상 코드

  SeatGrade({
    required this.name,
    required this.price,
    required this.colorHex,
  });

  factory SeatGrade.fromMap(Map<String, dynamic> map) {
    return SeatGrade(
      name: map['name'] ?? '',
      price: map['price'] ?? 0,
      colorHex: map['colorHex'] ?? '#808080',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'colorHex': colorHex,
    };
  }
}

/// 부산시민회관 대극장 프리셋
class BusanCivicHallPreset {
  static Venue get venue => Venue(
        id: 'busan_civic_hall',
        name: '부산시민회관 대극장',
        address: '부산광역시 동구 자성로133번길 16',
        floors: [floor1, floor2],
        totalSeats: 1606,
        createdAt: DateTime.now(),
      );

  static VenueFloor get floor1 => VenueFloor(
        name: '1층',
        blocks: [
          VenueBlock(
              name: 'A', rows: 22, seatsPerRow: 8, totalSeats: 157, grade: 'S'),
          VenueBlock(
              name: 'B',
              rows: 22,
              seatsPerRow: 10,
              totalSeats: 220,
              grade: 'R'),
          VenueBlock(
              name: 'C',
              rows: 22,
              seatsPerRow: 14,
              totalSeats: 308,
              grade: 'VIP'),
          VenueBlock(
              name: 'D',
              rows: 22,
              seatsPerRow: 10,
              totalSeats: 220,
              grade: 'R'),
          VenueBlock(
              name: 'E', rows: 22, seatsPerRow: 8, totalSeats: 157, grade: 'S'),
        ],
        totalSeats: 1062,
      );

  static VenueFloor get floor2 => VenueFloor(
        name: '2층',
        blocks: [
          VenueBlock(
              name: 'A',
              rows: 13,
              seatsPerRow: 10,
              totalSeats: 122,
              grade: 'A'),
          VenueBlock(
              name: 'B',
              rows: 10,
              seatsPerRow: 10,
              totalSeats: 100,
              grade: 'A'),
          VenueBlock(
              name: 'C',
              rows: 10,
              seatsPerRow: 10,
              totalSeats: 100,
              grade: 'S'),
          VenueBlock(
              name: 'D',
              rows: 10,
              seatsPerRow: 10,
              totalSeats: 100,
              grade: 'A'),
          VenueBlock(
              name: 'E',
              rows: 13,
              seatsPerRow: 10,
              totalSeats: 122,
              grade: 'A'),
        ],
        totalSeats: 544,
      );

  static List<SeatGrade> get grades => [
        SeatGrade(name: 'VIP', price: 100000, colorHex: '#9C27B0'),
        SeatGrade(name: 'R', price: 80000, colorHex: '#F44336'),
        SeatGrade(name: 'S', price: 60000, colorHex: '#FF9800'),
        SeatGrade(name: 'A', price: 40000, colorHex: '#2196F3'),
        SeatGrade(name: '시야방해R', price: 65000, colorHex: '#E57373'),
        SeatGrade(name: '시야방해S', price: 55000, colorHex: '#FFB74D'),
      ];
}

/// 스카이아트홀 (서울 등촌) 프리셋
/// 좌석배치도 기준 - 지하2층, 삼면 객석
class SkyArtHallPreset {
  static Venue get venue => Venue(
        id: 'sky_art_hall',
        name: '스카이아트홀',
        address: '서울특별시 강서구 등촌동',
        floors: [floorB1, floorB2],
        totalSeats: 409,
        createdAt: DateTime.now(),
      );

  // 지하1층 (메인) - A구역(좌측), B구역(정면좌), C구역(정면우), D구역(우측)
  static VenueFloor get floorB1 => VenueFloor(
        name: '지하1층',
        blocks: [
          // A구역 (좌측 사이드) - A1~A8
          VenueBlock(
              name: 'A', rows: 8, seatsPerRow: 5, totalSeats: 36, grade: 'A'),
          // B구역 (정면 좌) - B1~B18 (1~12 메인 + 14~18 후석)
          VenueBlock(
              name: 'B',
              rows: 18,
              seatsPerRow: 10,
              totalSeats: 135,
              grade: 'R'),
          // C구역 (정면 우) - C1~C18
          VenueBlock(
              name: 'C', rows: 18, seatsPerRow: 8, totalSeats: 120, grade: 'R'),
          // D구역 (우측 사이드) - D1~D15
          VenueBlock(
              name: 'D', rows: 15, seatsPerRow: 6, totalSeats: 78, grade: 'S'),
        ],
        totalSeats: 369,
      );

  // 지하2층 (후면) - B2구역
  static VenueFloor get floorB2 => VenueFloor(
        name: '지하2층',
        blocks: [
          VenueBlock(
              name: 'B2-1',
              rows: 4,
              seatsPerRow: 5,
              totalSeats: 15,
              grade: 'S'),
          VenueBlock(
              name: 'B2-2',
              rows: 3,
              seatsPerRow: 5,
              totalSeats: 10,
              grade: 'A'),
          VenueBlock(
              name: 'B2-3',
              rows: 3,
              seatsPerRow: 5,
              totalSeats: 15,
              grade: 'A'),
        ],
        totalSeats: 40,
      );

  static List<SeatGrade> get grades => [
        SeatGrade(name: 'VIP', price: 110000, colorHex: '#C9A84C'),
        SeatGrade(name: 'R', price: 88000, colorHex: '#F06292'),
        SeatGrade(name: 'A', price: 66000, colorHex: '#FFB74D'),
        SeatGrade(name: 'S', price: 55000, colorHex: '#64B5F6'),
      ];
}

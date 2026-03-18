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
  final String? masterVenueId; // 마스터 공연장 ID (연결된 경우)
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
    this.masterVenueId,
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
      masterVenueId: data['masterVenueId'],
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
      if (masterVenueId != null) 'masterVenueId': masterVenueId,
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
  normal,          // 일반석
  wheelchair,      // 장애인석
  reservedHold,    // 유보석 (판매 보류)
  obstructedView,  // 시야장애석
  houseReserved;   // 하우스유보석 (운영 보류)

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
      case SeatType.obstructedView:
        return '시야장애석';
      case SeatType.houseReserved:
        return '하우스유보석';
    }
  }

  String get shortLabel {
    switch (this) {
      case SeatType.normal:
        return '';
      case SeatType.wheelchair:
        return '♿';
      case SeatType.reservedHold:
        return '보류';
      case SeatType.obstructedView:
        return '시야';
      case SeatType.houseReserved:
        return 'H';
    }
  }
}

/// 좌석 배치도에서의 개별 좌석 위치
/// v1: gridX/gridY (int, 60x40 그리드)
/// v2: x/y (double, 자유 좌표 px)
class LayoutSeat {
  final double x;  // 캔버스 X 좌표 (px)
  final double y;  // 캔버스 Y 좌표 (px)
  final String zone;       // 구역 (A, B, C 등)
  final String floor;      // 층 (1층, 2층 등)
  final String row;        // 열 이름 (1, 2, A, B 등)
  final int number;        // 좌석 번호
  final String grade;      // 등급 (VIP, R, S, A)
  final SeatType seatType; // 좌석 유형

  LayoutSeat({
    required this.x,
    required this.y,
    this.zone = '',
    this.floor = '1층',
    this.row = '',
    this.number = 0,
    required this.grade,
    this.seatType = SeatType.normal,
  });

  /// 레거시 호환 생성자 (그리드 좌표 → 픽셀 변환)
  factory LayoutSeat.fromGrid({
    required int gridX,
    required int gridY,
    String zone = '',
    String floor = '1층',
    String row = '',
    int number = 0,
    required String grade,
    SeatType seatType = SeatType.normal,
    double cellSize = 16.0,
  }) {
    return LayoutSeat(
      x: gridX * cellSize + cellSize / 2,
      y: gridY * cellSize + cellSize / 2,
      zone: zone,
      floor: floor,
      row: row,
      number: number,
      grade: grade,
      seatType: seatType,
    );
  }

  /// 레거시 그리드 좌표 (역변환, 하위 호환용)
  int get gridX => (x / 16.0).floor();
  int get gridY => (y / 16.0).floor();

  /// 의미 기반 키 (위치 변경해도 유지)
  String get key {
    if (zone.isNotEmpty && row.isNotEmpty && number > 0) {
      return '$zone:$floor:$row:$number';
    }
    return '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
  }

  factory LayoutSeat.fromMap(Map<String, dynamic> map) {
    final rawX = map['x'];
    final rawY = map['y'];
    // v1(int) → 자동 변환: gridCoord * 16 + 8 (셀 중심)
    final double px = rawX is int
        ? rawX * 16.0 + 8.0
        : (rawX as num?)?.toDouble() ?? 0.0;
    final double py = rawY is int
        ? rawY * 16.0 + 8.0
        : (rawY as num?)?.toDouble() ?? 0.0;
    return LayoutSeat(
      x: px,
      y: py,
      zone: map['zone'] ?? '',
      floor: map['floor'] ?? '1층',
      row: (map['row'] ?? '').toString(),
      number: (map['number'] as num?)?.toInt() ?? 0,
      grade: map['grade'] ?? 'A',
      seatType: SeatType.fromString(map['type']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'zone': zone,
      'floor': floor,
      'row': row,
      'number': number,
      'grade': grade,
      'type': seatType.name,
    };
  }

  LayoutSeat copyWith({
    double? x,
    double? y,
    String? zone,
    String? floor,
    String? row,
    int? number,
    String? grade,
    SeatType? seatType,
  }) {
    return LayoutSeat(
      x: x ?? this.x,
      y: y ?? this.y,
      zone: zone ?? this.zone,
      floor: floor ?? this.floor,
      row: row ?? this.row,
      number: number ?? this.number,
      grade: grade ?? this.grade,
      seatType: seatType ?? this.seatType,
    );
  }
}

/// 배치도 텍스트 라벨 (층 구분, 열 이름, 커스텀 등)
class LayoutLabel {
  final double x;
  final double y;
  final String text;
  final String type; // 'floor' (1F, 2F), 'section' (A열, B열), 'custom'
  final double fontSize;

  LayoutLabel({
    required this.x,
    required this.y,
    required this.text,
    this.type = 'custom',
    this.fontSize = 12,
  });

  /// 레거시 호환
  int get gridX => (x / 16.0).floor();
  int get gridY => (y / 16.0).floor();
  String get key => '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';

  factory LayoutLabel.fromMap(Map<String, dynamic> map) {
    final rawX = map['x'];
    final rawY = map['y'];
    final double px = rawX is int ? rawX * 16.0 + 8.0 : (rawX as num?)?.toDouble() ?? 0.0;
    final double py = rawY is int ? rawY * 16.0 + 8.0 : (rawY as num?)?.toDouble() ?? 0.0;
    return LayoutLabel(
      x: px,
      y: py,
      text: map['text'] ?? '',
      type: map['type'] ?? 'custom',
      fontSize: (map['fontSize'] ?? 12).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'text': text,
      'type': type,
      'fontSize': fontSize,
    };
  }

  LayoutLabel copyWith({
    double? x,
    double? y,
    String? text,
    String? type,
    double? fontSize,
  }) {
    return LayoutLabel(
      x: x ?? this.x,
      y: y ?? this.y,
      text: text ?? this.text,
      type: type ?? this.type,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

/// 배치도 구분선 (팬스/통로 등 시각적 경계선)
class LayoutDivider {
  final double startX;
  final double startY;
  final double endX;
  final double endY;

  LayoutDivider({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });

  String get key =>
      '${startX.toStringAsFixed(1)},${startY.toStringAsFixed(1)}-'
      '${endX.toStringAsFixed(1)},${endY.toStringAsFixed(1)}';

  factory LayoutDivider.fromMap(Map<String, dynamic> map) {
    double _px(dynamic v) => v is int ? v * 16.0 + 8.0 : (v as num?)?.toDouble() ?? 0.0;
    return LayoutDivider(
      startX: _px(map['sx']),
      startY: _px(map['sy']),
      endX: _px(map['ex']),
      endY: _px(map['ey']),
    );
  }

  Map<String, dynamic> toMap() {
    return {'sx': startX, 'sy': startY, 'ex': endX, 'ey': endY};
  }
}

/// 공연장 좌석 배치도
/// layoutVersion 1: 레거시 그리드 (60x40, int 좌표)
/// layoutVersion 2: 자유 좌표 (2000x1400 기본, double px 좌표)
class VenueSeatLayout {
  final int layoutVersion; // 1=그리드, 2=자유좌표
  final double canvasWidth;  // 레퍼런스 캔버스 너비 (px)
  final double canvasHeight; // 레퍼런스 캔버스 높이 (px)
  final int gridCols; // 레거시 호환용
  final int gridRows; // 레거시 호환용
  final String stagePosition; // top / bottom
  final double stageWidthRatio; // 0.0~1.0 (캔버스 대비 비율)
  final double stageHeight; // px
  final String stageShape; // rect / arc / trapezoid
  final List<LayoutSeat> seats;
  final List<LayoutLabel> labels;
  final List<LayoutDivider> dividers;
  final Map<String, int> gradePrice;
  final String? backgroundImageUrl;
  final double backgroundOpacity;

  VenueSeatLayout({
    this.layoutVersion = 2,
    this.canvasWidth = 2000,
    this.canvasHeight = 1400,
    this.gridCols = 60,
    this.gridRows = 40,
    this.stagePosition = 'top',
    this.stageWidthRatio = 0.4,
    this.stageHeight = 28,
    this.stageShape = 'rect',
    this.seats = const [],
    this.labels = const [],
    this.dividers = const [],
    this.gradePrice = const {},
    this.backgroundImageUrl,
    this.backgroundOpacity = 0.3,
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
    final version = data['layoutVersion'] ?? 1;
    final cols = data['gridCols'] ?? 60;
    final rows = data['gridRows'] ?? 40;
    return VenueSeatLayout(
      layoutVersion: version is int ? version : 1,
      canvasWidth: version >= 2
          ? (data['canvasWidth'] ?? 2000).toDouble()
          : (cols as int) * 16.0,
      canvasHeight: version >= 2
          ? (data['canvasHeight'] ?? 1400).toDouble()
          : (rows as int) * 16.0,
      gridCols: cols is int ? cols : 60,
      gridRows: rows is int ? rows : 40,
      stagePosition: data['stagePosition'] ?? 'top',
      stageWidthRatio: (data['stageWidthRatio'] ?? 0.4).toDouble(),
      stageHeight: (data['stageHeight'] ?? 28).toDouble(),
      stageShape: data['stageShape'] ?? 'rect',
      seats: (data['seats'] as List<dynamic>?)
              ?.map((s) => LayoutSeat.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      labels: (data['labels'] as List<dynamic>?)
              ?.map((l) => LayoutLabel.fromMap(l as Map<String, dynamic>))
              .toList() ??
          [],
      dividers: (data['dividers'] as List<dynamic>?)
              ?.map((d) => LayoutDivider.fromMap(d as Map<String, dynamic>))
              .toList() ??
          [],
      gradePrice: Map<String, int>.from(data['gradePrice'] ?? {}),
      backgroundImageUrl: data['backgroundImageUrl'] as String?,
      backgroundOpacity: (data['backgroundOpacity'] ?? 0.3).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'layoutVersion': layoutVersion,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'gridCols': gridCols,
      'gridRows': gridRows,
      'stagePosition': stagePosition,
      'stageWidthRatio': stageWidthRatio,
      'stageHeight': stageHeight,
      'stageShape': stageShape,
      'seats': seats.map((s) => s.toMap()).toList(),
      'labels': labels.map((l) => l.toMap()).toList(),
      'dividers': dividers.map((d) => d.toMap()).toList(),
      'gradePrice': gradePrice,
      if (backgroundImageUrl != null) 'backgroundImageUrl': backgroundImageUrl,
      'backgroundOpacity': backgroundOpacity,
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

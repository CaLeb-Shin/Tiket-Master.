import 'package:cloud_firestore/cloud_firestore.dart';
import 'venue.dart';

/// 검증된 마스터 공연장 — 공연 등록 시 재사용 가능한 공연장 템플릿
class MasterVenue {
  final String id;
  final String name;
  final String? region; // 지역 (서울, 부산, 대전 등)
  final String? address;
  final int totalSeats;
  final List<VenueFloor> floors;
  final VenueSeatLayout? seatLayout; // 표준 도트맵
  final bool isVerified; // 멜팅 인증 공연장
  final bool hasSeatView; // 360도 시야 사진 보유
  final List<String> linkedVenueIds; // 이 마스터 기반으로 생성된 venue IDs
  final DateTime createdAt;

  MasterVenue({
    required this.id,
    required this.name,
    this.region,
    this.address,
    required this.totalSeats,
    required this.floors,
    this.seatLayout,
    this.isVerified = false,
    this.hasSeatView = false,
    this.linkedVenueIds = const [],
    required this.createdAt,
  });

  factory MasterVenue.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MasterVenue(
      id: doc.id,
      name: d['name'] ?? '',
      region: d['region'],
      address: d['address'],
      totalSeats: d['totalSeats'] ?? 0,
      floors: (d['floors'] as List<dynamic>?)
              ?.map((f) => VenueFloor.fromMap(f as Map<String, dynamic>))
              .toList() ??
          [],
      seatLayout: d['seatLayout'] != null
          ? VenueSeatLayout.fromMap(d['seatLayout'] as Map<String, dynamic>)
          : null,
      isVerified: d['isVerified'] ?? false,
      hasSeatView: d['hasSeatView'] ?? false,
      linkedVenueIds: d['linkedVenueIds'] != null
          ? List<String>.from(d['linkedVenueIds'])
          : [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'region': region,
      'address': address,
      'totalSeats': totalSeats,
      'floors': floors.map((f) => f.toMap()).toList(),
      if (seatLayout != null) 'seatLayout': seatLayout!.toMap(),
      'isVerified': isVerified,
      'hasSeatView': hasSeatView,
      'linkedVenueIds': linkedVenueIds,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 등급별 좌석 수
  Map<String, int> get seatCountByGrade {
    if (seatLayout != null) return seatLayout!.seatCountByGrade;
    final counts = <String, int>{};
    for (final floor in floors) {
      for (final block in floor.blocks) {
        if (block.grade != null) {
          counts[block.grade!] = (counts[block.grade!] ?? 0) + block.totalSeats;
        }
      }
    }
    return counts;
  }
}

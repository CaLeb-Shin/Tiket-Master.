import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';

final venueViewRepositoryProvider = Provider<VenueViewRepository>((ref) {
  return VenueViewRepository(ref.watch(firestoreServiceProvider));
});

/// 공연장별 시점 이미지 스트림
final venueViewsProvider =
    StreamProvider.family<Map<String, VenueSeatView>, String>(
        (ref, venueId) {
  return ref.watch(venueViewRepositoryProvider).getVenueViewsStream(venueId);
});

/// 좌석 시점 뷰 데이터 (열 단위 360° 이미지)
/// 키: "B_지하1층_7" → B구역 지하1층 7열
class VenueSeatView {
  final String zone; // 구역명 (A, B, C, D 등)
  final String floor; // 층 (지하1층, 지하2층)
  final String? row; // 열 (1, 2, 3... / null이면 구역 전체)
  final String imageUrl; // 360° equirectangular 이미지 URL
  final bool is360; // true: 360° 파노라마, false: 일반 사진
  final String? description; // 시야 설명

  const VenueSeatView({
    required this.zone,
    required this.floor,
    this.row,
    required this.imageUrl,
    this.is360 = true,
    this.description,
  });

  factory VenueSeatView.fromMap(Map<String, dynamic> map) {
    return VenueSeatView(
      zone: map['zone'] ?? '',
      floor: map['floor'] ?? '1층',
      row: map['row'],
      imageUrl: map['imageUrl'] ?? '',
      is360: map['is360'] ?? true,
      description: map['description'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'zone': zone,
      'floor': floor,
      'row': row,
      'imageUrl': imageUrl,
      'is360': is360,
      'description': description,
    };
  }

  /// 키 생성: "B_지하1층_7" (열 있을 때) 또는 "B_지하1층" (구역 전체)
  String get key => row != null ? '${zone}_${floor}_$row' : '${zone}_$floor';

  /// 표시명: "B구역 7열" 또는 "B구역"
  String get displayName =>
      row != null ? '$zone구역 $row열' : '$zone구역';
}

// 하위 호환 - 기존 코드에서 사용하는 이름
typedef VenueZoneView = VenueSeatView;

class VenueViewRepository {
  final FirestoreService _firestoreService;

  VenueViewRepository(this._firestoreService);

  /// 특정 공연장의 모든 시점 이미지 스트림
  Stream<Map<String, VenueSeatView>> getVenueViewsStream(String venueId) {
    return _firestoreService.venueViews
        .doc(venueId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return {};
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return {};

      final views = data['views'] as Map<String, dynamic>? ?? {};
      return views.map((key, value) => MapEntry(
            key,
            VenueSeatView.fromMap(value as Map<String, dynamic>),
          ));
    });
  }

  /// 특정 공연장의 시점 이미지 조회
  Future<Map<String, VenueSeatView>> getVenueViews(String venueId) async {
    final doc = await _firestoreService.venueViews.doc(venueId).get();
    if (!doc.exists) return {};
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return {};

    final views = data['views'] as Map<String, dynamic>? ?? {};
    return views.map((key, value) => MapEntry(
          key,
          VenueSeatView.fromMap(value as Map<String, dynamic>),
        ));
  }

  /// 시점 이미지 추가/업데이트
  Future<void> setVenueView(String venueId, VenueSeatView view) async {
    await _firestoreService.venueViews.doc(venueId).set({
      'views': {view.key: view.toMap()},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 시점 이미지 삭제
  Future<void> deleteVenueView(
      String venueId, String zone, String floor, [String? row]) async {
    final key = row != null ? '${zone}_${floor}_$row' : '${zone}_$floor';
    await _firestoreService.venueViews.doc(venueId).update({
      'views.$key': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 여러 시점 이미지 일괄 업데이트
  Future<void> setVenueViews(
      String venueId, List<VenueSeatView> views) async {
    final viewsMap = <String, dynamic>{};
    for (final view in views) {
      viewsMap[view.key] = view.toMap();
    }
    await _firestoreService.venueViews.doc(venueId).set({
      'views': viewsMap,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

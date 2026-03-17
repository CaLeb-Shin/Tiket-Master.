import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/repositories/venue_view_repository.dart';

/// 3단계 드릴다운 좌석 선택 위젯
/// Stage 1: Overview — Canvas로 전체 좌석맵 (구역별 색상), 구역 탭
/// Stage 2: Zone — 선택 구역 확대, 행별 좌석 표시
/// Stage 3: Seat — 좌석 탭 → 시야 사진 팝업 + 예매바
class ZoneDrilldown extends StatefulWidget {
  final List<Seat> seats;
  final String? selectedFloor;
  final Set<String> selectedSeatIds;
  final int maxSelectable;
  final Map<String, VenueSeatView> venueViews;
  final VenueSeatLayout? dotMapLayout;
  final String? currentUserId;
  final ValueChanged<Seat> onSeatToggle;
  final void Function(VenueSeatView view, Seat seat)? onShowSeatView;

  const ZoneDrilldown({
    super.key,
    required this.seats,
    this.selectedFloor,
    required this.selectedSeatIds,
    this.maxSelectable = 4,
    required this.venueViews,
    this.dotMapLayout,
    this.currentUserId,
    required this.onSeatToggle,
    this.onShowSeatView,
  });

  @override
  State<ZoneDrilldown> createState() => _ZoneDrilldownState();
}

enum _DrillStage { overview, zone }

class _ZoneDrilldownState extends State<ZoneDrilldown>
    with SingleTickerProviderStateMixin {
  _DrillStage _stage = _DrillStage.overview;
  String? _activeZone; // 선택된 구역명

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  static const _gradeOrder = ['VIP', 'R', 'S', 'A', 'B'];
  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFF30D158),
    'S': Color(0xFF0A84FF),
    'A': Color(0xFFFF9F0A),
    'B': Color(0xFF8E8E93),
  };

  Color _gradeColor(String? grade) =>
      _gradeColors[grade?.toUpperCase()] ?? AppTheme.textTertiary;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _goToZone(String zone) {
    setState(() {
      _stage = _DrillStage.zone;
      _activeZone = zone;
    });
    _animCtrl.forward(from: 0);
  }

  void _goToOverview() {
    setState(() {
      _stage = _DrillStage.overview;
      _activeZone = null;
    });
    _animCtrl.forward(from: 0);
  }

  List<Seat> get _floorSeats {
    if (widget.selectedFloor == null) return widget.seats;
    return widget.seats
        .where((s) => s.floor == widget.selectedFloor)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 드릴다운 네비게이션 바
        _buildBreadcrumb(),
        // 컨텐츠
        Expanded(
          child: FadeTransition(
            opacity: _fadeIn,
            child: _stage == _DrillStage.overview
                ? _buildOverview()
                : _buildZoneDetail(),
          ),
        ),
        // 범례
        _buildLegend(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BREADCRUMB
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _breadcrumbItem('전체', _stage == _DrillStage.overview, _goToOverview),
          if (_activeZone != null) ...[
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppTheme.textTertiary),
            _breadcrumbItem('$_activeZone구역', _stage == _DrillStage.zone, null),
          ],
          const Spacer(),
          if (_stage != _DrillStage.overview)
            GestureDetector(
              onTap: _goToOverview,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.zoom_out_map_rounded,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '전체보기',
                      style: AppTheme.nanum(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _breadcrumbItem(String label, bool isActive, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: AppTheme.nanum(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppTheme.gold : AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STAGE 1: OVERVIEW — Canvas 기반 전체 좌석맵
  // ═══════════════════════════════════════════════════════════════

  Widget _buildOverview() {
    final seats = _floorSeats;

    // 구역별 그룹
    final zones = <String, List<Seat>>{};
    for (final s in seats) {
      zones.putIfAbsent(s.block, () => []).add(s);
    }

    // 도트맵 레이아웃이 있으면 Canvas 오버뷰
    if (widget.dotMapLayout != null &&
        widget.dotMapLayout!.seats.isNotEmpty) {
      return _buildCanvasOverview(zones);
    }

    // 도트맵 없으면 구역 카드 그리드
    return _buildCardOverview(zones);
  }

  /// Canvas 기반 오버뷰 (2-2b: CustomPainter 1000석+)
  Widget _buildCanvasOverview(Map<String, List<Seat>> zones) {
    final layout = widget.dotMapLayout!;
    final seatByKey = <String, Seat>{};
    for (final s in _floorSeats) {
      seatByKey['${s.block}:${s.floor}:${s.row ?? ''}:${s.number}'] = s;
    }

    return GestureDetector(
      onTapDown: (details) => _onCanvasTap(details, layout, seatByKey),
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(80),
        child: CustomPaint(
          size: Size(layout.canvasWidth, layout.canvasHeight),
          painter: _OverviewPainter(
            layout: layout,
            seatByKey: seatByKey,
            selectedSeatIds: widget.selectedSeatIds,
            currentUserId: widget.currentUserId,
            gradeColors: _gradeColors,
          ),
        ),
      ),
    );
  }

  void _onCanvasTap(TapDownDetails details, VenueSeatLayout layout,
      Map<String, Seat> seatByKey) {
    // 구역 탭 감지: 가장 가까운 좌석의 zone 결정
    final scenePoint = details.localPosition;
    String? closestZone;
    double minDist = 40.0; // 구역 hit 반경
    for (final ls in layout.seats) {
      final d = (Offset(ls.x, ls.y) - scenePoint).distance;
      if (d < minDist) {
        minDist = d;
        closestZone = ls.zone;
      }
    }
    if (closestZone != null) {
      _goToZone(closestZone);
    }
  }

  /// 카드 기반 오버뷰 (도트맵 없을 때 폴백)
  Widget _buildCardOverview(Map<String, List<Seat>> zones) {
    final sortedZones = zones.keys.toList()..sort(_zoneComparator(zones));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // STAGE 라벨
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: const BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(60),
                bottomRight: Radius.circular(60),
              ),
            ),
            child: Text(
              'STAGE',
              textAlign: TextAlign.center,
              style: AppTheme.nanum(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFDF3F6),
                letterSpacing: 3,
              ),
            ),
          ),
          // 구역 카드
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: sortedZones.length,
            itemBuilder: (context, i) {
              final zone = sortedZones[i];
              final zoneSeats = zones[zone]!;
              final grade = zoneSeats
                  .firstWhere((s) => s.grade != null,
                      orElse: () => zoneSeats.first)
                  .grade;
              final color = _gradeColor(grade);
              final available = zoneSeats
                  .where((s) =>
                      s.status == SeatStatus.available &&
                      !s.isHeldByOther(widget.currentUserId))
                  .length;
              final total = zoneSeats.length;

              return GestureDetector(
                onTap: available > 0 ? () => _goToZone(zone) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: available > 0
                        ? color.withValues(alpha: 0.08)
                        : AppTheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: available > 0
                          ? color.withValues(alpha: 0.4)
                          : AppTheme.border,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$zone구역',
                            style: AppTheme.nanum(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (grade != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                grade.toUpperCase(),
                                style: AppTheme.nanum(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '잔여 $available / $total석',
                        style: AppTheme.nanum(
                          fontSize: 12,
                          color: available > 0
                              ? color
                              : AppTheme.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (available == 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '매진',
                          style: AppTheme.nanum(
                            fontSize: 11,
                            color: AppTheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STAGE 2: ZONE DETAIL — 행별 좌석 선택
  // ═══════════════════════════════════════════════════════════════

  Widget _buildZoneDetail() {
    if (_activeZone == null) return const SizedBox.shrink();

    final zoneSeats = _floorSeats
        .where((s) => s.block == _activeZone)
        .toList();

    if (zoneSeats.isEmpty) {
      return Center(
        child: Text('좌석 없음',
            style: AppTheme.nanum(color: AppTheme.textTertiary)),
      );
    }

    final grade = zoneSeats
        .firstWhere((s) => s.grade != null, orElse: () => zoneSeats.first)
        .grade;
    final color = _gradeColor(grade);

    // 행별 그룹
    final rowMap = <String, List<Seat>>{};
    for (final s in zoneSeats) {
      rowMap.putIfAbsent(s.row ?? '1', () => []).add(s);
    }
    final sortedRows = rowMap.keys.toList()
      ..sort((a, b) =>
          (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 3.0,
      boundaryMargin: const EdgeInsets.all(40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            // 구역 헤더
            _buildZoneHeader(zoneSeats, grade, color),
            const SizedBox(height: 10),
            // 행별 좌석
            ...sortedRows.map((row) {
              final seats = rowMap[row]!
                ..sort((a, b) => a.number.compareTo(b.number));
              return _buildSeatRow(row, seats, color);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneHeader(
      List<Seat> zoneSeats, String? grade, Color color) {
    final available = zoneSeats
        .where((s) =>
            s.status == SeatStatus.available &&
            !s.isHeldByOther(widget.currentUserId))
        .length;
    final held = zoneSeats
        .where((s) => s.isHeldByOther(widget.currentUserId))
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$_activeZone구역',
            style: AppTheme.nanum(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (grade != null) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${grade.toUpperCase()}석',
                style: AppTheme.nanum(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '잔여 $available석',
            style: AppTheme.nanum(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: available > 0 ? color : AppTheme.textTertiary,
            ),
          ),
          if (held > 0) ...[
            const SizedBox(width: 8),
            Text(
              '선점중 $held',
              style: AppTheme.nanum(
                fontSize: 10,
                color: const Color(0xFFFF8F00),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeatRow(String row, List<Seat> seats, Color zoneColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          // 열 번호
          SizedBox(
            width: 30,
            child: Text(
              '$row열',
              style: AppTheme.nanum(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          // 좌석들
          Expanded(
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              children: seats.map((s) => _buildSeatDot(s, zoneColor)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatDot(Seat seat, Color zoneColor) {
    final isSelected = widget.selectedSeatIds.contains(seat.id);
    final isAvailable = seat.status == SeatStatus.available;
    final isHeldByOther = seat.isHeldByOther(widget.currentUserId);
    final isHeldByMe = seat.isHeldByMe(widget.currentUserId);
    final hasView = _findBestView(seat) != null;

    Color bg;
    Color borderColor;

    if (isSelected) {
      bg = AppTheme.gold;
      borderColor = AppTheme.gold;
    } else if (isHeldByOther) {
      // 2-2d: 다른 사용자 선점 → 주황 비활성화
      bg = const Color(0xFFFF8F00).withValues(alpha: 0.15);
      borderColor = const Color(0xFFFF8F00).withValues(alpha: 0.4);
    } else if (isHeldByMe) {
      bg = AppTheme.gold.withValues(alpha: 0.3);
      borderColor = AppTheme.gold.withValues(alpha: 0.6);
    } else if (!isAvailable) {
      bg = AppTheme.border;
      borderColor = AppTheme.border;
    } else {
      bg = zoneColor.withValues(alpha: 0.15);
      borderColor = zoneColor.withValues(alpha: 0.5);
    }

    final canTap = isAvailable && !isHeldByOther;

    return GestureDetector(
      onTap: canTap
          ? () {
              widget.onSeatToggle(seat);
              // 2-2c: 시야 사진 자동 표시
              if (!isSelected) {
                final view = _findBestView(seat);
                if (view != null && widget.onShowSeatView != null) {
                  Future.microtask(() => widget.onShowSeatView!(view, seat));
                }
              }
            }
          : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border:
              Border.all(color: borderColor, width: isSelected ? 1.5 : 0.5),
        ),
        child: Stack(
          children: [
            Center(
              child: isSelected
                  ? const Icon(Icons.check,
                      size: 14, color: Color(0xFFFDF3F6))
                  : isHeldByOther
                      ? const Icon(Icons.lock_rounded,
                          size: 12, color: Color(0xFFFF8F00))
                      : Text(
                          '${seat.number}',
                          style: AppTheme.nanum(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: isAvailable
                                ? zoneColor
                                : AppTheme.textTertiary
                                    .withValues(alpha: 0.3),
                          ),
                        ),
            ),
            // 시야 사진 indicator
            if (hasView && isAvailable && !isSelected && !isHeldByOther)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppTheme.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VENUE VIEW MATCHING (2-2c)
  // ═══════════════════════════════════════════════════════════════

  VenueSeatView? _findBestView(Seat seat) {
    if (widget.venueViews.isEmpty) return null;
    final floor = seat.floor.trim();
    final zone = seat.block.trim().toUpperCase();
    final row = (seat.row ?? '').trim();
    final seatNumber = seat.number;

    bool matchesZoneFloor(VenueSeatView view) {
      return view.zone.trim().toUpperCase() == zone &&
          view.floor.trim() == floor;
    }

    // 1. 정확 매칭 (zone+floor+row+seat)
    for (final v in widget.venueViews.values) {
      if (!matchesZoneFloor(v)) continue;
      if (v.seat != seatNumber) continue;
      if ((v.row ?? '').trim() == row) return v;
    }
    // 2. 같은 행 가장 가까운 좌석
    if (row.isNotEmpty) {
      VenueSeatView? closest;
      int minDist = 999;
      for (final v in widget.venueViews.values) {
        if (!matchesZoneFloor(v)) continue;
        if ((v.row ?? '').trim() != row) continue;
        if (v.seat == null) return v;
        final dist = (v.seat! - seatNumber).abs();
        if (dist < minDist) {
          minDist = dist;
          closest = v;
        }
      }
      if (closest != null) return closest;
    }
    // 3. 같은 zone+floor 가장 가까운 행
    if (row.isNotEmpty) {
      final rowNum = int.tryParse(row);
      if (rowNum != null) {
        VenueSeatView? closest;
        int minDist = 999;
        for (final v in widget.venueViews.values) {
          if (!matchesZoneFloor(v)) continue;
          final vRow = int.tryParse((v.row ?? '').trim());
          if (vRow == null) continue;
          final dist = (vRow - rowNum).abs();
          if (dist < minDist) {
            minDist = dist;
            closest = v;
          }
        }
        if (closest != null) return closest;
      }
    }
    // 4. zone+floor 대표
    for (final v in widget.venueViews.values) {
      if (!matchesZoneFloor(v)) continue;
      if ((v.row ?? '').trim().isEmpty && v.seat == null) return v;
    }
    // 5. zone fallback
    for (final v in widget.venueViews.values) {
      if (v.zone.trim().toUpperCase() == zone) return v;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // LEGEND
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(AppTheme.textTertiary.withValues(alpha: 0.15),
              AppTheme.textTertiary, '선택 가능'),
          const SizedBox(width: 10),
          _legendItem(AppTheme.gold, AppTheme.gold, '선택됨'),
          const SizedBox(width: 10),
          _legendItem(
              const Color(0xFFFF8F00).withValues(alpha: 0.15),
              const Color(0xFFFF8F00),
              '선점중'),
          const SizedBox(width: 10),
          _legendItem(AppTheme.border, AppTheme.border, '판매됨'),
          const SizedBox(width: 10),
          _legendViewDot(),
        ],
      ),
    );
  }

  Widget _legendItem(Color bg, Color border, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border, width: 0.5),
          ),
        ),
        const SizedBox(width: 3),
        Text(label,
            style: AppTheme.nanum(
                fontSize: 10, color: AppTheme.textTertiary)),
      ],
    );
  }

  Widget _legendViewDot() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppTheme.border, width: 0.5),
          ),
          child: const Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.all(1),
              child: CircleAvatar(radius: 2.5, backgroundColor: AppTheme.gold),
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text('시야',
            style: AppTheme.nanum(
                fontSize: 10, color: AppTheme.textTertiary)),
      ],
    );
  }

  // ── Utils ──

  int Function(String, String) _zoneComparator(Map<String, List<Seat>> zones) {
    return (a, b) {
      final gradeA = zones[a]!
          .firstWhere((s) => s.grade != null, orElse: () => zones[a]!.first)
          .grade
          ?.toUpperCase();
      final gradeB = zones[b]!
          .firstWhere((s) => s.grade != null, orElse: () => zones[b]!.first)
          .grade
          ?.toUpperCase();
      final idxA = _gradeOrder.indexOf(gradeA ?? '');
      final idxB = _gradeOrder.indexOf(gradeB ?? '');
      final orderA = idxA >= 0 ? idxA : _gradeOrder.length;
      final orderB = idxB >= 0 ? idxB : _gradeOrder.length;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.compareTo(b);
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERVIEW CANVAS PAINTER (2-2b: 1000석+ CustomPainter)
// ═══════════════════════════════════════════════════════════════════════════

class _OverviewPainter extends CustomPainter {
  final VenueSeatLayout layout;
  final Map<String, Seat> seatByKey;
  final Set<String> selectedSeatIds;
  final String? currentUserId;
  final Map<String, Color> gradeColors;

  static const _holdColor = Color(0xFFFF8F00);
  static const _soldColor = Color(0xFF444450);
  static const _emptyColor = Color(0xFF2A2A34);

  _OverviewPainter({
    required this.layout,
    required this.seatByKey,
    required this.selectedSeatIds,
    this.currentUserId,
    required this.gradeColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotR = 6.0;

    // Stage
    _drawStage(canvas, size);

    // 뷰포트 최적화: 가시 영역만 렌더링
    for (final ls in layout.seats) {
      final cx = ls.x;
      final cy = ls.y;
      final key = ls.key;
      final eventSeat = seatByKey[key];

      Color dotColor;
      bool isSelected = false;

      if (eventSeat != null) {
        isSelected = selectedSeatIds.contains(eventSeat.id);
        final isHeldByOther = eventSeat.isHeldByOther(currentUserId);

        if (isSelected) {
          dotColor = const Color(0xFFFFD700);
        } else if (isHeldByOther) {
          dotColor = _holdColor;
        } else {
          switch (eventSeat.status) {
            case SeatStatus.available:
              dotColor = gradeColors[eventSeat.grade] ??
                  gradeColors[ls.grade] ??
                  _emptyColor;
            case SeatStatus.reserved:
            case SeatStatus.used:
              dotColor = _soldColor;
            case SeatStatus.blocked:
              dotColor = _soldColor;
          }
        }
      } else {
        dotColor = gradeColors[ls.grade] ?? _emptyColor;
      }

      canvas.drawCircle(
        Offset(cx, cy),
        dotR,
        Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill,
      );

      if (isSelected) {
        canvas.drawCircle(
          Offset(cx, cy),
          dotR + 2,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      // 판매된 좌석 X 표시
      if (eventSeat != null &&
          !isSelected &&
          (eventSeat.status == SeatStatus.reserved ||
              eventSeat.status == SeatStatus.used)) {
        final xPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawLine(
            Offset(cx - 3, cy - 3), Offset(cx + 3, cy + 3), xPaint);
        canvas.drawLine(
            Offset(cx + 3, cy - 3), Offset(cx - 3, cy + 3), xPaint);
      }
    }

    // 구역 라벨 그리기
    _drawZoneLabels(canvas);
  }

  void _drawStage(Canvas canvas, Size size) {
    final stageW = size.width * layout.stageWidthRatio.clamp(0.3, 0.8);
    final stageH = layout.stageHeight > 0 ? layout.stageHeight : 30.0;
    final stageRect = RRect.fromRectAndCorners(
      Rect.fromCenter(
        center: Offset(size.width / 2, stageH / 2 + 10),
        width: stageW,
        height: stageH,
      ),
      bottomLeft: const Radius.circular(40),
      bottomRight: const Radius.circular(40),
    );

    canvas.drawRRect(
      stageRect,
      Paint()..color = const Color(0x33C9A84C),
    );
    canvas.drawRRect(
      stageRect,
      Paint()
        ..color = const Color(0x66C9A84C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // STAGE 텍스트
    final tp = TextPainter(
      text: const TextSpan(
        text: 'STAGE',
        style: TextStyle(
          color: Color(0x99C9A84C),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width / 2 - tp.width / 2, stageH / 2 + 10 - tp.height / 2),
    );
  }

  void _drawZoneLabels(Canvas canvas) {
    // 구역별 중심 좌표 계산
    final zoneCenters = <String, List<double>>{};
    for (final ls in layout.seats) {
      zoneCenters.putIfAbsent(ls.zone, () => [0, 0, 0]);
      zoneCenters[ls.zone]![0] += ls.x;
      zoneCenters[ls.zone]![1] += ls.y;
      zoneCenters[ls.zone]![2] += 1;
    }

    for (final entry in zoneCenters.entries) {
      final zone = entry.key;
      final cx = entry.value[0] / entry.value[2];
      final cy = entry.value[1] / entry.value[2];

      final tp = TextPainter(
        text: TextSpan(
          text: zone,
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      // 배경
      final bgRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: tp.width + 12,
        height: tp.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        Paint()..color = const Color(0x44000000),
      );
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewPainter old) {
    return old.selectedSeatIds != selectedSeatIds ||
        old.seatByKey != seatByKey;
  }
}

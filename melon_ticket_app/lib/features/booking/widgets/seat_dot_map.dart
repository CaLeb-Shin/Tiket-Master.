import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/venue.dart';

/// 인터랙티브 도트맵 좌석 선택 위젯
class SeatDotMap extends StatefulWidget {
  final VenueSeatLayout layout;
  final List<Seat> seats; // 이벤트의 좌석 목록 (상태 포함)
  final Set<String> selectedSeatIds;
  final int maxSelectable;
  final ValueChanged<Seat> onSeatTap;

  const SeatDotMap({
    super.key,
    required this.layout,
    required this.seats,
    required this.selectedSeatIds,
    this.maxSelectable = 4,
    required this.onSeatTap,
  });

  @override
  State<SeatDotMap> createState() => _SeatDotMapState();
}

class _SeatDotMapState extends State<SeatDotMap> {
  final TransformationController _ctrl = TransformationController();
  Seat? _hoveredSeat;

  static const double _dotSize = 16.0;
  static const double _dotGap = 3.0;
  static const double _cellSize = _dotSize + _dotGap;

  // Grade colors
  static const Map<String, Color> _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  static const Color _soldColor = Color(0xFF444450);
  static const Color _reservedColor = Color(0xFFFF8F00);
  static const Color _selectedColor = Color(0xFFFFD700);
  static const Color _wheelchairColor = Color(0xFFFF9800);
  static const Color _holdColor = Color(0xFF555555);
  static const Color _emptyDotColor = Color(0xFF2A2A34);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// layout seat key → event Seat 매핑
  Map<String, Seat> get _seatByGrid {
    final map = <String, Seat>{};
    for (final seat in widget.seats) {
      if (seat.gridX != null && seat.gridY != null) {
        map['${seat.gridX},${seat.gridY}'] = seat;
      }
    }
    return map;
  }

  void _onTapDown(TapDownDetails details) {
    final matrix = _ctrl.value.clone()..invert();
    final scenePoint =
        MatrixUtils.transformPoint(matrix, details.localPosition);

    final gx = scenePoint.dx ~/ _cellSize;
    final gy = scenePoint.dy ~/ _cellSize;
    final key = '$gx,$gy';

    final seatByGrid = _seatByGrid;
    if (seatByGrid.containsKey(key)) {
      final seat = seatByGrid[key]!;
      if (seat.status == SeatStatus.available && seat.seatType != 'reserved_hold') {
        widget.onSeatTap(seat);
      }
    }
  }

  // ── Zoom Controls ──

  void _zoomIn() {
    final currentScale = _ctrl.value.getMaxScaleOnAxis();
    if (currentScale >= 5.0) return;
    _applyZoom(1.3);
  }

  void _zoomOut() {
    final currentScale = _ctrl.value.getMaxScaleOnAxis();
    if (currentScale <= 0.4) return;
    _applyZoom(1 / 1.3);
  }

  void _applyZoom(double factor) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final center = renderBox.size.center(Offset.zero);

    // Build zoom transform: translate to center, scale, translate back
    final zoom = Matrix4.identity()
      ..setEntry(0, 3, center.dx * (1 - factor))
      ..setEntry(1, 3, center.dy * (1 - factor))
      ..setEntry(0, 0, factor)
      ..setEntry(1, 1, factor);
    setState(() => _ctrl.value = zoom * _ctrl.value);
  }

  void _zoomReset() {
    setState(() => _ctrl.value = Matrix4.identity());
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final canvasW = layout.gridCols * _cellSize;
    final canvasH = layout.gridRows * _cellSize;
    final seatByGrid = _seatByGrid;

    // 층 구분 정보 계산
    final floorBounds = _computeFloorBounds(layout);

    return Column(
      children: [
        // Legend
        _buildLegend(),
        // Map + Zoom controls overlay
        Expanded(
          child: Stack(
            children: [
              // Map
              GestureDetector(
                onTapDown: _onTapDown,
                child: InteractiveViewer(
                  transformationController: _ctrl,
                  minScale: 0.4,
                  maxScale: 5.0,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(100),
                  child: CustomPaint(
                    size: Size(canvasW, canvasH),
                    painter: _DotMapPainter(
                      layout: layout,
                      seatByGrid: seatByGrid,
                      selectedSeatIds: widget.selectedSeatIds,
                      cellSize: _cellSize,
                      dotSize: _dotSize,
                      gradeColors: _gradeColors,
                      soldColor: _soldColor,
                      reservedColor: _reservedColor,
                      selectedColor: _selectedColor,
                      wheelchairColor: _wheelchairColor,
                      holdColor: _holdColor,
                      emptyDotColor: _emptyDotColor,
                      floorBounds: floorBounds,
                    ),
                  ),
                ),
              ),
              // Zoom control buttons — bottom right
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _zoomButton(Icons.add_rounded, _zoomIn),
                    const SizedBox(height: 4),
                    _zoomButton(Icons.remove_rounded, _zoomOut),
                    const SizedBox(height: 4),
                    _zoomButton(Icons.crop_free_rounded, _zoomReset),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Selected seat info
        if (_hoveredSeat != null) _buildSeatInfo(_hoveredSeat!),
      ],
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: AppTheme.textPrimary, size: 18),
          ),
        ),
      ),
    );
  }

  /// 층별 좌석 영역 범위 계산
  static Map<String, _FloorBound> _computeFloorBounds(VenueSeatLayout layout) {
    final bounds = <String, _FloorBound>{};
    for (final ls in layout.seats) {
      final floor = ls.floor;
      if (bounds.containsKey(floor)) {
        final b = bounds[floor]!;
        bounds[floor] = _FloorBound(
          minY: ls.gridY < b.minY ? ls.gridY : b.minY,
          maxY: ls.gridY > b.maxY ? ls.gridY : b.maxY,
          minX: ls.gridX < b.minX ? ls.gridX : b.minX,
          maxX: ls.gridX > b.maxX ? ls.gridX : b.maxX,
        );
      } else {
        bounds[floor] = _FloorBound(
          minY: ls.gridY,
          maxY: ls.gridY,
          minX: ls.gridX,
          maxX: ls.gridX,
        );
      }
    }
    return bounds;
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendDot(const Color(0xFFD4AF37), 'VIP'),
          _legendDot(const Color(0xFFE53935), 'R'),
          _legendDot(const Color(0xFF1E88E5), 'S'),
          _legendDot(const Color(0xFF43A047), 'A'),
          const SizedBox(width: 8),
          _legendDot(_soldColor, '판매됨'),
          _legendDot(_selectedColor, '선택'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTheme.nanum(fontSize: 10, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatInfo(Seat seat) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.surface,
      child: Text(
        seat.displayName,
        style: AppTheme.nanum(fontSize: 13, color: AppTheme.textPrimary),
      ),
    );
  }
}

/// 층별 좌석 영역 경계
class _FloorBound {
  final int minY;
  final int maxY;
  final int minX;
  final int maxX;

  const _FloorBound({
    required this.minY,
    required this.maxY,
    required this.minX,
    required this.maxX,
  });
}

// ─── Canvas Painter ───

class _DotMapPainter extends CustomPainter {
  final VenueSeatLayout layout;
  final Map<String, Seat> seatByGrid;
  final Set<String> selectedSeatIds;
  final double cellSize;
  final double dotSize;
  final Map<String, Color> gradeColors;
  final Color soldColor;
  final Color reservedColor;
  final Color selectedColor;
  final Color wheelchairColor;
  final Color holdColor;
  final Color emptyDotColor;
  final Map<String, _FloorBound> floorBounds;

  _DotMapPainter({
    required this.layout,
    required this.seatByGrid,
    required this.selectedSeatIds,
    required this.cellSize,
    required this.dotSize,
    required this.gradeColors,
    required this.soldColor,
    required this.reservedColor,
    required this.selectedColor,
    required this.wheelchairColor,
    required this.holdColor,
    required this.emptyDotColor,
    required this.floorBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotR = dotSize / 2 - 1;

    // Stage
    _drawStage(canvas, size);

    // Floor labels (draw before seats so seats render on top)
    _drawFloorLabels(canvas);

    // Draw all layout seats
    for (final ls in layout.seats) {
      final cx = ls.gridX * cellSize + cellSize / 2;
      final cy = ls.gridY * cellSize + cellSize / 2;
      final key = ls.key;

      final eventSeat = seatByGrid[key];

      Color dotColor;
      bool isSelected = false;

      if (eventSeat != null) {
        isSelected = selectedSeatIds.contains(eventSeat.id);

        if (isSelected) {
          dotColor = selectedColor;
        } else if (eventSeat.seatType == 'reserved_hold') {
          dotColor = holdColor;
        } else if (eventSeat.seatType == 'wheelchair') {
          dotColor = wheelchairColor;
        } else {
          switch (eventSeat.status) {
            case SeatStatus.available:
              dotColor = gradeColors[eventSeat.grade] ??
                  gradeColors[ls.grade] ??
                  emptyDotColor;
              break;
            case SeatStatus.reserved:
              dotColor = soldColor;
              break;
            case SeatStatus.used:
              dotColor = soldColor;
              break;
            case SeatStatus.blocked:
              dotColor = holdColor;
              break;
          }
        }
      } else {
        // Layout seat with no event seat - show as grade color (available)
        if (ls.seatType == SeatType.reservedHold) {
          dotColor = holdColor;
        } else if (ls.seatType == SeatType.wheelchair) {
          dotColor = wheelchairColor;
        } else {
          dotColor = gradeColors[ls.grade] ?? emptyDotColor;
        }
      }

      final fillPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), dotR, fillPaint);

      // Selected highlight ring
      if (isSelected) {
        final ringPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(Offset(cx, cy), dotR + 2, ringPaint);
      }

      // Sold/reserved: darker with X
      if (eventSeat != null &&
          !isSelected &&
          (eventSeat.status == SeatStatus.reserved ||
              eventSeat.status == SeatStatus.used)) {
        final xPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawLine(
            Offset(cx - 3, cy - 3), Offset(cx + 3, cy + 3), xPaint);
        canvas.drawLine(
            Offset(cx + 3, cy - 3), Offset(cx - 3, cy + 3), xPaint);
      }
    }
  }

  void _drawFloorLabels(Canvas canvas) {
    if (floorBounds.length <= 1) return; // 단층은 라벨 불필요

    for (final entry in floorBounds.entries) {
      final floor = entry.key;
      final b = entry.value;

      // 층 라벨을 좌석 영역 좌측 위에 표시
      final labelX = b.minX * cellSize - 4;
      final labelY = b.minY * cellSize - 18;

      final tp = TextPainter(
        text: TextSpan(
          text: floor,
          style: const TextStyle(
            color: Color(0xFF888898),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(labelX, labelY));

      // 층 구분선 (점선 효과 — 짧은 선분 반복)
      final lineY = b.minY * cellSize - 6;
      final lineStartX = b.minX * cellSize;
      final lineEndX = (b.maxX + 1) * cellSize;
      final linePaint = Paint()
        ..color = const Color(0xFF444450)
        ..strokeWidth = 0.5;

      for (double x = lineStartX; x < lineEndX; x += 6) {
        canvas.drawLine(
          Offset(x, lineY),
          Offset(x + 3, lineY),
          linePaint,
        );
      }
    }
  }

  void _drawStage(Canvas canvas, Size size) {
    final stageW = size.width * 0.35;
    final stageH = 28.0;
    final stageX = (size.width - stageW) / 2;
    final stageY =
        layout.stagePosition == 'top' ? 4.0 : size.height - stageH - 4;

    final stagePaint = Paint()
      ..color = const Color(0xFF3A3A44)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stageX, stageY, stageW, stageH),
        const Radius.circular(6),
      ),
      stagePaint,
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'STAGE',
        style: TextStyle(
          color: Color(0xFF666670),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        stageX + (stageW - textPainter.width) / 2,
        stageY + (stageH - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _DotMapPainter oldDelegate) => true;
}

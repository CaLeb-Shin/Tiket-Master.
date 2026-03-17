import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/venue.dart';

/// 읽기전용 미니 좌석맵 — 내 좌석 위치를 골드 펄스로 하이라이트 (2-4c)
class MiniSeatMap extends StatefulWidget {
  final VenueSeatLayout layout;
  final Seat mySeat;

  const MiniSeatMap({
    super.key,
    required this.layout,
    required this.mySeat,
  });

  @override
  State<MiniSeatMap> createState() => _MiniSeatMapState();
}

class _MiniSeatMapState extends State<MiniSeatMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final mySeat = widget.mySeat;

    // 내 좌석의 레이아웃 좌표 찾기
    LayoutSeat? myLayoutSeat;
    final myKey =
        '${mySeat.block}:${mySeat.floor}:${mySeat.row ?? ''}:${mySeat.number}';
    for (final ls in layout.seats) {
      if (ls.key == myKey) {
        myLayoutSeat = ls;
        break;
      }
    }

    if (myLayoutSeat == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return CustomPaint(
              size: Size(double.infinity, 200),
              painter: _MiniMapPainter(
                layout: layout,
                mySeat: myLayoutSeat!,
                pulseValue: _pulse.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final VenueSeatLayout layout;
  final LayoutSeat mySeat;
  final double pulseValue;

  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  _MiniMapPainter({
    required this.layout,
    required this.mySeat,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.seats.isEmpty) return;

    // 전체 좌석 범위 계산
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final ls in layout.seats) {
      if (ls.x < minX) minX = ls.x;
      if (ls.x > maxX) maxX = ls.x;
      if (ls.y < minY) minY = ls.y;
      if (ls.y > maxY) maxY = ls.y;
    }

    final layoutW = maxX - minX;
    final layoutH = maxY - minY;
    if (layoutW <= 0 || layoutH <= 0) return;

    // 내 좌석 중심으로 뷰포트 계산 (여유있게)
    final margin = 20.0;
    final scale = ((size.width - margin * 2) / layoutW)
        .clamp(0.0, (size.height - margin * 2) / layoutH);
    final offsetX = (size.width - layoutW * scale) / 2 - minX * scale;
    final offsetY = (size.height - layoutH * scale) / 2 - minY * scale;

    final dotR = (3.0 * scale).clamp(1.5, 4.0);

    // 모든 좌석 — 반투명
    for (final ls in layout.seats) {
      final cx = ls.x * scale + offsetX;
      final cy = ls.y * scale + offsetY;
      final isMe = ls.key == '${mySeat.zone}:${mySeat.floor}:${mySeat.row}:${mySeat.number}';

      if (isMe) continue; // 내 좌석은 나중에 그림

      final gradeColor = _gradeColors[ls.grade] ?? const Color(0xFF2A2A34);
      canvas.drawCircle(
        Offset(cx, cy),
        dotR,
        Paint()..color = gradeColor.withValues(alpha: 0.25),
      );
    }

    // 내 좌석 — 골드 펄스
    final myCx = mySeat.x * scale + offsetX;
    final myCy = mySeat.y * scale + offsetY;
    final myR = dotR * 2.5;

    // 외부 글로우
    canvas.drawCircle(
      Offset(myCx, myCy),
      myR + 6 * pulseValue,
      Paint()
        ..color = AppTheme.gold.withValues(alpha: 0.15 * pulseValue)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 외부 링
    canvas.drawCircle(
      Offset(myCx, myCy),
      myR + 2,
      Paint()
        ..color = AppTheme.gold.withValues(alpha: 0.4 * pulseValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 내부 채움
    canvas.drawCircle(
      Offset(myCx, myCy),
      myR,
      Paint()..color = AppTheme.gold,
    );

    // STAGE 라벨 (상단)
    final stageW = size.width * 0.4;
    final stageRect = RRect.fromRectAndCorners(
      Rect.fromCenter(
        center: Offset(size.width / 2, 12),
        width: stageW,
        height: 16,
      ),
      bottomLeft: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
    );
    canvas.drawRRect(
      stageRect,
      Paint()..color = const Color(0x33C9A84C),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'STAGE',
        style: TextStyle(
          color: Color(0x99C9A84C),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 12 - tp.height / 2));

    // 내 좌석 라벨
    final labelTp = TextPainter(
      text: TextSpan(
        text: '${mySeat.zone}구역 ${mySeat.row}열 ${mySeat.number}번',
        style: const TextStyle(
          color: Color(0xFFFDF3F6),
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final labelX = myCx - labelTp.width / 2;
    final labelY = myCy - myR - 14;

    // 라벨 배경
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            labelX - 4, labelY - 2, labelTp.width + 8, labelTp.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    labelTp.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) =>
      old.pulseValue != pulseValue || old.mySeat != mySeat;
}

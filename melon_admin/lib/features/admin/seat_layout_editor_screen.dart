import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import '../../app/admin_theme.dart';
import 'excel_seat_upload_helper.dart';

/// 좌석 배치 에디터 (도트 그리드 기반)
class SeatLayoutEditorScreen extends ConsumerStatefulWidget {
  final String venueId;
  const SeatLayoutEditorScreen({super.key, required this.venueId});

  @override
  ConsumerState<SeatLayoutEditorScreen> createState() =>
      _SeatLayoutEditorScreenState();
}

enum _EditorTool { paint, erase, select, line, text }
enum _EditorStep { stage, structure, seats }

class _SeatLayoutEditorScreenState
    extends ConsumerState<SeatLayoutEditorScreen> {
  // ─── Grid State ───
  int _gridCols = 60;
  int _gridRows = 40;
  String _stagePosition = 'top';
  double _stageWidthRatio = 0.4;
  double _stageHeight = 28;
  String _stageShape = 'rect'; // rect / arc / trapezoid
  final Map<String, LayoutSeat> _seats = {}; // key: "x,y"
  final Map<String, int> _gradePrice = {
    'VIP': 100000,
    'R': 80000,
    'S': 60000,
    'A': 40000,
  };

  // ─── Editor State ───
  _EditorStep _step = _EditorStep.stage;
  _EditorTool _tool = _EditorTool.paint;
  String _selectedGrade = 'VIP';
  SeatType _selectedSeatType = SeatType.normal;
  String _currentZone = 'A';
  String _currentFloor = '1층';
  LayoutSeat? _selectedSeat;
  final Set<String> _multiSelected = {};

  // ─── Dividers (구분선) ───
  final List<LayoutDivider> _dividers = [];
  ({int x, int y})? _dividerStart; // 구분선 시작점

  // ─── Canvas State ───
  final TransformationController _transformCtrl = TransformationController();
  final FocusNode _focusNode = FocusNode();
  static const double _dotSize = 14.0;
  static const double _dotGap = 2.0;
  static const double _cellSize = _dotSize + _dotGap;

  // ─── Line Tool State ───
  ({int x, int y})? _lineStart; // 라인 시작점

  // ─── Labels ───
  final Map<String, LayoutLabel> _labels = {}; // key: "x,y"

  // ─── Drag Indicator ───
  Offset? _dragIndicator; // 현재 드래그 중인 위치 (캔버스 좌표)

  // ─── Canvas Direct Manipulation ───
  String? _dragTarget; // 'stage_left' | 'stage_right' | 'stage_bottom' | 'label:x,y' | 'divider:idx' | null
  Offset? _dragStartPos; // 드래그 시작 위치

  // ─── Loading ───
  bool _loading = true;
  bool _saving = false;
  bool _isDragging = false;
  bool _showExcelGuide = false;
  Venue? _venue;

  // ─── Grade Colors ───
  static const Map<String, Color> gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  static const Color _wheelchairColor = Color(0xFFFF9800);
  static const Color _holdColor = Color(0xFF757575);
  static const Color _emptyDotColor = Color(0xFF3A3A44);

  static const List<String> _floorPresets = ['1층', '2층', '3층', '4층'];

  @override
  void initState() {
    super.initState();
    _loadVenue();
    _transformCtrl.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    // Trigger rebuild for zoom level display in bottom bar
    setState(() {});
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _transformCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadVenue() async {
    final repo = ref.read(venueRepositoryProvider);
    final venue = await repo.getVenue(widget.venueId);
    if (venue != null && mounted) {
      setState(() {
        _venue = venue;
        _stagePosition = venue.stagePosition;
        if (venue.seatLayout != null) {
          final layout = venue.seatLayout!;
          _gridCols = layout.gridCols;
          _gridRows = layout.gridRows;
          _stagePosition = layout.stagePosition;
          _stageWidthRatio = layout.stageWidthRatio;
          _stageHeight = layout.stageHeight;
          _stageShape = layout.stageShape;
          _gradePrice.addAll(layout.gradePrice);
          for (final seat in layout.seats) {
            _seats[seat.key] = seat;
          }
          for (final label in layout.labels) {
            _labels[label.key] = label;
          }
          _dividers.addAll(layout.dividers);
        }
        // 기존 데이터가 있으면 좌석 배치 스텝으로 시작
        if (_seats.isNotEmpty) _step = _EditorStep.seats;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final layout = VenueSeatLayout(
        gridCols: _gridCols,
        gridRows: _gridRows,
        stagePosition: _stagePosition,
        stageWidthRatio: _stageWidthRatio,
        stageHeight: _stageHeight,
        stageShape: _stageShape,
        seats: _seats.values.toList(),
        labels: _labels.values.toList(),
        dividers: List.from(_dividers),
        gradePrice: Map.from(_gradePrice),
      );

      final repo = ref.read(venueRepositoryProvider);
      await repo.updateVenue(widget.venueId, {
        'seatLayout': layout.toMap(),
        'totalSeats': layout.totalSeats,
        'stagePosition': _stagePosition,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('좌석 배치도 저장 완료 (${layout.totalSeats}석)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: AdminTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Auto Numbering ───
  void _autoNumber() {
    // Group seats by zone + floor + row (same gridY)
    final grouped = <String, List<LayoutSeat>>{};
    for (final seat in _seats.values) {
      final rowKey = '${seat.zone}_${seat.floor}_${seat.gridY}';
      grouped.putIfAbsent(rowKey, () => []).add(seat);
    }

    // Sort each group by gridX and assign numbers
    int rowIndex = 0;
    final sortedKeys = grouped.keys.toList()..sort();
    for (final key in sortedKeys) {
      final group = grouped[key]!;
      group.sort((a, b) => a.gridX.compareTo(b.gridX));
      rowIndex++;
      for (int i = 0; i < group.length; i++) {
        final seat = group[i];
        _seats[seat.key] = seat.copyWith(
          row: '$rowIndex',
          number: i + 1,
        );
      }
    }
    setState(() {});
  }

  // ─── Keyboard Shortcuts ───
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    final isCmd = HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.metaLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.metaRight);

    // ⌘+1~4 → 등급 전환 (VIP/R/S/A)
    if (isCmd) {
      if (key == LogicalKeyboardKey.digit1) {
        setState(() => _selectedGrade = 'VIP');
        return;
      } else if (key == LogicalKeyboardKey.digit2) {
        setState(() => _selectedGrade = 'R');
        return;
      } else if (key == LogicalKeyboardKey.digit3) {
        setState(() => _selectedGrade = 'S');
        return;
      } else if (key == LogicalKeyboardKey.digit4) {
        setState(() => _selectedGrade = 'A');
        return;
      }
    }

    // 1~4 → 도구 전환 (페인트/지우개/선택/라인)
    if (key == LogicalKeyboardKey.digit1) {
      setState(() => _tool = _EditorTool.paint);
    } else if (key == LogicalKeyboardKey.digit2) {
      setState(() => _tool = _EditorTool.erase);
    } else if (key == LogicalKeyboardKey.digit3) {
      setState(() => _tool = _EditorTool.select);
    } else if (key == LogicalKeyboardKey.digit4) {
      setState(() => _tool = _EditorTool.line);
    } else if (key == LogicalKeyboardKey.digit5) {
      setState(() => _tool = _EditorTool.text);
    } else if (key == LogicalKeyboardKey.escape) {
      // ESC → 라인 취소 또는 선택 해제
      setState(() {
        _lineStart = null;
        _selectedSeat = null;
        _multiSelected.clear();
      });
    }
  }

  // ─── Cmd key check ───
  bool get _isCmdPressed =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaRight);

  // ─── Canvas Tap ───
  // ─── Hit Test System ───
  Rect _getStageRect() {
    final canvasW = _gridCols * _cellSize;
    final stageW = canvasW * _stageWidthRatio;
    final stageX = (canvasW - stageW) / 2;
    final stageY = _stagePosition == 'top' ? 4.0 : _gridRows * _cellSize - _stageHeight - 4;
    return Rect.fromLTWH(stageX, stageY, stageW, _stageHeight);
  }

  String? _hitTest(Offset pos) {
    // 1. Stage handles (stage step)
    if (_step == _EditorStep.stage) {
      final sr = _getStageRect();
      const h = 10.0; // handle hit area
      // Left edge
      if ((pos.dx - sr.left).abs() < h && pos.dy > sr.top - h && pos.dy < sr.bottom + h) {
        return 'stage_left';
      }
      // Right edge
      if ((pos.dx - sr.right).abs() < h && pos.dy > sr.top - h && pos.dy < sr.bottom + h) {
        return 'stage_right';
      }
      // Bottom edge (top position) or Top edge (bottom position)
      if (_stagePosition == 'top') {
        if ((pos.dy - sr.bottom).abs() < h && pos.dx > sr.left - h && pos.dx < sr.right + h) {
          return 'stage_bottom';
        }
      } else {
        if ((pos.dy - sr.top).abs() < h && pos.dx > sr.left - h && pos.dx < sr.right + h) {
          return 'stage_bottom';
        }
      }
    }

    // 2. Labels (structure step)
    if (_step == _EditorStep.structure) {
      for (final label in _labels.values) {
        final lx = label.gridX * _cellSize + _cellSize / 2;
        final ly = label.gridY * _cellSize + _cellSize / 2;
        final hitSize = label.fontSize * label.text.length * 0.4 + 16;
        if ((pos.dx - lx).abs() < hitSize && (pos.dy - ly).abs() < label.fontSize + 8) {
          return 'label:${label.key}';
        }
      }
    }

    return null;
  }

  void _removeSeatsInStageArea() {
    final sr = _getStageRect();
    final keysToRemove = <String>[];
    for (final entry in _seats.entries) {
      final cx = entry.value.gridX * _cellSize + _cellSize / 2;
      final cy = entry.value.gridY * _cellSize + _cellSize / 2;
      if (sr.contains(Offset(cx, cy))) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _seats.remove(key);
    }
  }

  void _removeSeatsOnDivider(LayoutDivider d) {
    final keysToRemove = <String>[];
    for (final entry in _seats.entries) {
      final sx = entry.value.gridX;
      final sy = entry.value.gridY;
      // Check distance from seat to divider line
      final dx = d.endX - d.startX;
      final dy = d.endY - d.startY;
      final lenSq = dx * dx + dy * dy;
      if (lenSq == 0) continue;
      final t = ((sx - d.startX) * dx + (sy - d.startY) * dy) / lenSq;
      if (t < 0 || t > 1) continue;
      final projX = d.startX + t * dx;
      final projY = d.startY + t * dy;
      final dist = math.sqrt(math.pow(sx - projX, 2) + math.pow(sy - projY, 2));
      if (dist < 0.8) keysToRemove.add(entry.key);
    }
    for (final key in keysToRemove) {
      _seats.remove(key);
    }
  }

  void _removeSeatsAtLabel(LayoutLabel label) {
    final key = '${label.gridX},${label.gridY}';
    _seats.remove(key);
    // Also remove adjacent cells based on text length
    final span = (label.text.length * 0.5).ceil();
    for (var dx = -span; dx <= span; dx++) {
      _seats.remove('${label.gridX + dx},${label.gridY}');
    }
  }

  void _onCanvasTap(Offset localPosition) {
    final gx = localPosition.dx ~/ _cellSize;
    final gy = localPosition.dy ~/ _cellSize;
    if (gx < 0 || gx >= _gridCols || gy < 0 || gy >= _gridRows) return;

    // Stage 스텝: 빈 곳 탭 시 무시 (드래그 핸들만 사용)
    if (_step == _EditorStep.stage) return;

    // Structure 스텝: 라벨 탭 → 편집 다이얼로그, 빈 곳 탭 → 새 라벨
    if (_step == _EditorStep.structure) {
      // 기존 라벨 탭 → 편집
      for (final label in _labels.values) {
        final lx = label.gridX * _cellSize + _cellSize / 2;
        final ly = label.gridY * _cellSize + _cellSize / 2;
        final hitSize = label.fontSize * label.text.length * 0.4 + 16;
        if ((localPosition.dx - lx).abs() < hitSize &&
            (localPosition.dy - ly).abs() < label.fontSize + 8) {
          _showLabelDialog(label.gridX, label.gridY, existing: label);
          return;
        }
      }
      // 빈 곳 탭 → 라벨 모드면 새 라벨, 아니면 구분선 시작점
      if (_tool == _EditorTool.text) {
        _showLabelDialog(gx, gy);
      } else {
        // 구분선 시작점 설정 (드래그로 끝점 결정)
        setState(() => _dividerStart = (x: gx, y: gy));
      }
      return;
    }

    final key = '$gx,$gy';
    final effectiveTool = _isCmdPressed ? _EditorTool.erase : _tool;

    switch (effectiveTool) {
      case _EditorTool.paint:
        if (!_seats.containsKey(key)) {
          setState(() {
            _seats[key] = LayoutSeat(
              gridX: gx,
              gridY: gy,
              zone: _currentZone,
              floor: _currentFloor,
              grade: _selectedGrade,
              seatType: _selectedSeatType,
            );
          });
        }
        break;

      case _EditorTool.erase:
        if (_seats.containsKey(key)) {
          setState(() => _seats.remove(key));
        }
        break;

      case _EditorTool.select:
        if (_seats.containsKey(key)) {
          setState(() {
            _selectedSeat = _seats[key];
            _multiSelected.clear();
          });
        } else {
          setState(() {
            _selectedSeat = null;
            _multiSelected.clear();
          });
        }
        break;

      case _EditorTool.line:
        if (_lineStart == null) {
          // 첫 번째 클릭: 시작점 설정
          setState(() => _lineStart = (x: gx, y: gy));
        } else {
          // 두 번째 클릭: 시작점~끝점 사이에 좌석 배치 (Bresenham)
          _drawLine(_lineStart!.x, _lineStart!.y, gx, gy);
          setState(() => _lineStart = null);
        }
        break;

      case _EditorTool.text:
        _showLabelDialog(gx, gy);
        break;
    }
  }

  // ─── Label Dialog ───
  void _showLabelDialog(int gx, int gy, {LayoutLabel? existing}) {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    String labelType = existing?.type ?? 'custom';
    double fontSize = existing?.fontSize ?? 14;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AdminTheme.surface,
          title: Text(
            existing != null ? '라벨 수정' : '텍스트 라벨 추가',
            style: AdminTheme.sans(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick presets
                Text('프리셋', style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _labelPresetChip(ctx, '1F', 'floor', 16, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                    _labelPresetChip(ctx, '2F', 'floor', 16, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                    _labelPresetChip(ctx, '3F', 'floor', 16, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                    _labelPresetChip(ctx, 'A열', 'section', 11, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                    _labelPresetChip(ctx, 'B열', 'section', 11, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                    _labelPresetChip(ctx, 'STAGE', 'custom', 14, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                    _labelPresetChip(ctx, 'CONSOLE', 'custom', 12, textCtrl, (t, tp, fs) => setDialogState(() { labelType = tp; fontSize = fs; })),
                  ],
                ),
                const SizedBox(height: 14),
                // Text input
                TextField(
                  controller: textCtrl,
                  autofocus: true,
                  style: AdminTheme.sans(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '라벨 텍스트',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // Type selector
                Row(
                  children: [
                    Text('유형', style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary)),
                    const Spacer(),
                    ...['floor', 'section', 'custom'].map((t) {
                      final isSelected = labelType == t;
                      final display = {'floor': '층 구분', 'section': '구역', 'custom': '커스텀'}[t]!;
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: GestureDetector(
                          onTap: () => setDialogState(() => labelType = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? AdminTheme.gold.withValues(alpha: 0.15) : Colors.transparent,
                              border: Border.all(color: isSelected ? AdminTheme.gold : AdminTheme.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(display, style: AdminTheme.sans(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? AdminTheme.gold : AdminTheme.textSecondary,
                            )),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                // Font size slider
                Row(
                  children: [
                    Text('크기', style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary)),
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 8,
                        max: 28,
                        divisions: 20,
                        activeColor: AdminTheme.gold,
                        onChanged: (v) => setDialogState(() => fontSize = v),
                      ),
                    ),
                    Text('${fontSize.round()}', style: AdminTheme.sans(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _labels.remove(existing.key));
                },
                child: Text('삭제', style: TextStyle(color: AdminTheme.error)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (textCtrl.text.trim().isEmpty) return;
                setState(() {
                  _labels['$gx,$gy'] = LayoutLabel(
                    gridX: gx,
                    gridY: gy,
                    text: textCtrl.text.trim(),
                    type: labelType,
                    fontSize: fontSize,
                  );
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: Colors.black87,
              ),
              child: Text(existing != null ? '수정' : '추가'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelPresetChip(
    BuildContext ctx,
    String text,
    String type,
    double fontSize,
    TextEditingController textCtrl,
    void Function(String, String, double) onApply,
  ) {
    return GestureDetector(
      onTap: () {
        textCtrl.text = text;
        onApply(text, type, fontSize);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AdminTheme.border.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: AdminTheme.sans(fontSize: 10, color: AdminTheme.textSecondary)),
      ),
    );
  }

  // ─── Line Drawing (Bresenham) ───
  void _drawLine(int x0, int y0, int x1, int y1) {
    final points = <({int x, int y})>[];
    int dx = (x1 - x0).abs();
    int dy = (y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;
    int cx = x0, cy = y0;

    while (true) {
      points.add((x: cx, y: cy));
      if (cx == x1 && cy == y1) break;
      int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        cx += sx;
      }
      if (e2 < dx) {
        err += dx;
        cy += sy;
      }
    }

    setState(() {
      for (final p in points) {
        final key = '${p.x},${p.y}';
        if (!_seats.containsKey(key)) {
          _seats[key] = LayoutSeat(
            gridX: p.x,
            gridY: p.y,
            zone: _currentZone,
            floor: _currentFloor,
            grade: _selectedGrade,
            seatType: _selectedSeatType,
          );
        }
      }
    });
  }

  void _onCanvasDragStart(Offset localPosition) {
    _isDragging = true;
    _dragStartPos = localPosition;

    // Stage step: check for handle drag
    if (_step == _EditorStep.stage) {
      final hit = _hitTest(localPosition);
      if (hit != null && hit.startsWith('stage_')) {
        _dragTarget = hit;
        return;
      }
    }

    // Structure step: check for label drag or start divider
    if (_step == _EditorStep.structure) {
      final hit = _hitTest(localPosition);
      if (hit != null && hit.startsWith('label:')) {
        _dragTarget = hit;
        return;
      }
      // 구분선 시작 (tap에서 이미 _dividerStart 설정됨)
      if (_tool != _EditorTool.text && _dividerStart == null) {
        final gx = localPosition.dx ~/ _cellSize;
        final gy = localPosition.dy ~/ _cellSize;
        if (gx >= 0 && gx < _gridCols && gy >= 0 && gy < _gridRows) {
          setState(() => _dividerStart = (x: gx, y: gy));
        }
      }
    }

    // Seats step: normal paint/erase drag
    if (_step == _EditorStep.seats) {
      _onCanvasDragUpdate(localPosition);
    }
  }

  void _onCanvasDragUpdate(Offset localPosition) {
    // Stage step: handle resize
    if (_step == _EditorStep.stage && _dragTarget != null) {
      final canvasW = _gridCols * _cellSize;
      final canvasH = _gridRows * _cellSize;
      final sr = _getStageRect();

      if (_dragTarget == 'stage_left' || _dragTarget == 'stage_right') {
        // Symmetric resize: adjust width ratio
        final center = canvasW / 2;
        final halfW = (_dragTarget == 'stage_right')
            ? (localPosition.dx - center).abs()
            : (center - localPosition.dx).abs();
        final newRatio = (halfW * 2 / canvasW).clamp(0.15, 0.9);
        setState(() {
          _stageWidthRatio = newRatio;
          _removeSeatsInStageArea();
        });
      } else if (_dragTarget == 'stage_bottom') {
        final newH = _stagePosition == 'top'
            ? (localPosition.dy - sr.top).clamp(16.0, 60.0)
            : (sr.bottom - localPosition.dy).clamp(16.0, 60.0);
        setState(() {
          _stageHeight = newH;
          _removeSeatsInStageArea();
        });
      }
      return;
    }

    // Structure step: label drag or divider preview
    if (_step == _EditorStep.structure) {
      if (_dragTarget != null && _dragTarget!.startsWith('label:')) {
        final key = _dragTarget!.substring(6); // "x,y"
        final label = _labels[key];
        if (label != null) {
          final gx = localPosition.dx ~/ _cellSize;
          final gy = localPosition.dy ~/ _cellSize;
          if (gx >= 0 && gx < _gridCols && gy >= 0 && gy < _gridRows) {
            setState(() {
              _labels.remove(key);
              final moved = LayoutLabel(
                gridX: gx,
                gridY: gy,
                text: label.text,
                type: label.type,
                fontSize: label.fontSize,
              );
              _labels[moved.key] = moved;
              _dragTarget = 'label:${moved.key}';
              _removeSeatsAtLabel(moved);
            });
          }
        }
        return;
      }
      // 구분선 드래그 중: 끝점 미리보기 업데이트
      if (_dividerStart != null) {
        final gx = localPosition.dx ~/ _cellSize;
        final gy = localPosition.dy ~/ _cellSize;
        setState(() => _dragIndicator = localPosition);
        return;
      }
      return;
    }

    // Seats step: paint/erase drag
    if (_step == _EditorStep.seats) {
      final gx = localPosition.dx ~/ _cellSize;
      final gy = localPosition.dy ~/ _cellSize;
      if (gx < 0 || gx >= _gridCols || gy < 0 || gy >= _gridRows) return;

      _dragIndicator = localPosition;
      final key = '$gx,$gy';
      final effectiveTool = _isCmdPressed ? _EditorTool.erase : _tool;

      if (effectiveTool == _EditorTool.paint && !_seats.containsKey(key)) {
        setState(() {
          _seats[key] = LayoutSeat(
            gridX: gx,
            gridY: gy,
            zone: _currentZone,
            floor: _currentFloor,
            grade: _selectedGrade,
            seatType: _selectedSeatType,
          );
        });
      } else if (effectiveTool == _EditorTool.erase &&
          _seats.containsKey(key)) {
        setState(() => _seats.remove(key));
      } else {
        setState(() {}); // trigger repaint for drag indicator
      }
    }
  }

  void _onCanvasDragEnd() {
    // Structure step: 구분선 완성
    if (_step == _EditorStep.structure && _dividerStart != null && _dragIndicator != null) {
      final gx = _dragIndicator!.dx ~/ _cellSize;
      final gy = _dragIndicator!.dy ~/ _cellSize;
      if (gx >= 0 && gx < _gridCols && gy >= 0 && gy < _gridRows) {
        // 시작점과 끝점이 다른 경우에만 추가
        if (gx != _dividerStart!.x || gy != _dividerStart!.y) {
          final divider = LayoutDivider(
            startX: _dividerStart!.x,
            startY: _dividerStart!.y,
            endX: gx,
            endY: gy,
          );
          _dividers.add(divider);
          _removeSeatsOnDivider(divider);
        }
      }
    }

    setState(() {
      _isDragging = false;
      _dragTarget = null;
      _dragStartPos = null;
      _dragIndicator = null;
      _dividerStart = null;
    });
  }

  // ─── Excel Import (Enhanced) ───
  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    try {
      final bytes = result.files.first.bytes;
      if (bytes == null) return;

      // Use enhanced parser with auto-detect
      final parseResult =
          EnhancedExcelParser.parse(bytes, gridCols: _gridCols);

      if (parseResult.seats.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('엑셀에서 좌석 데이터를 찾을 수 없습니다'),
              backgroundColor: AdminTheme.error,
            ),
          );
        }
        return;
      }

      // Show validation preview dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ExcelValidationPreviewDialog(
          result: parseResult,
          onConfirm: () {
            Navigator.pop(ctx);
            _applyParsedSeats(parseResult.seats);
          },
          onCancel: () => Navigator.pop(ctx),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('엑셀 파싱 오류: $e'),
            backgroundColor: AdminTheme.error,
          ),
        );
      }
    }
  }

  void _applyParsedSeats(List<LayoutSeat> imported) {
    // Adjust grid size to fit imported data
    int maxX = 0, maxY = 0;
    for (final s in imported) {
      if (s.gridX > maxX) maxX = s.gridX;
      if (s.gridY > maxY) maxY = s.gridY;
    }

    setState(() {
      _gridCols = math.max(_gridCols, maxX + 5);
      _gridRows = math.max(_gridRows, maxY + 5);
      for (final seat in imported) {
        _seats[seat.key] = seat;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${imported.length}개 좌석 가져오기 완료')),
      );
    }
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AdminTheme.background,
        body: const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Column(
          children: [
            _buildTopBar(),
          // Excel Upload Guide Panel (collapsible)
          if (_showExcelGuide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ExcelUploadGuidePanel(
                onDownloadVisual:
                    ExcelTemplateDownloader.downloadVisualTemplate,
                onDownloadList:
                    ExcelTemplateDownloader.downloadListTemplate,
                onDownloadRowCol:
                    ExcelTemplateDownloader.downloadRowColTemplate,
              ),
            ),
          Expanded(
            child: Row(
              children: [
                // Canvas area
                Expanded(child: _buildCanvas()),
                // Right panel
                SizedBox(width: 300, child: _buildRightPanel()),
              ],
            ),
          ),
          _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        left: 12,
        right: 16,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: const Border(
            bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ─── Back + Title ───
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/venues/${widget.venueId}');
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            splashRadius: 18,
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _venue?.name ?? '좌석 배치 편집',
                style: AdminTheme.sans(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _seats.isNotEmpty
                          ? AdminTheme.gold
                          : AdminTheme.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_seats.length}석 배치됨',
                    style: AdminTheme.sans(
                        fontSize: 11, color: AdminTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(width: 16),
          _topBarDivider(),
          const SizedBox(width: 12),

          // ─── Excel Group ───
          _topBarIconButton(
            icon: Icons.help_outline_rounded,
            tooltip: '엑셀 가이드',
            onTap: () => setState(() => _showExcelGuide = !_showExcelGuide),
            active: _showExcelGuide,
          ),
          const SizedBox(width: 4),
          _topBarIconButton(
            icon: Icons.upload_file_rounded,
            tooltip: '엑셀 가져오기',
            onTap: _importExcel,
          ),

          const SizedBox(width: 8),
          _topBarDivider(),
          const SizedBox(width: 8),

          // ─── Edit Group ───
          _topBarIconButton(
            icon: Icons.format_list_numbered_rounded,
            tooltip: '자동 번호 매기기',
            onTap: _autoNumber,
          ),
          const SizedBox(width: 4),
          _topBarIconButton(
            icon: Icons.delete_sweep_rounded,
            tooltip: '전체 지우기',
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('전체 좌석 삭제'),
                  content: const Text('배치된 모든 좌석을 삭제하시겠습니까?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('취소')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _seats.clear());
                      },
                      child: const Text('삭제',
                          style: TextStyle(color: AdminTheme.error)),
                    ),
                  ],
                ),
              );
            },
            danger: true,
          ),

          const Spacer(),

          // ─── Save ───
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black87))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(
                _saving ? '저장 중...' : '저장',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBarDivider() {
    return Container(
      width: 1,
      height: 24,
      color: AdminTheme.border,
    );
  }

  Widget _topBarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
  }) {
    final color = active
        ? AdminTheme.gold
        : danger
            ? AdminTheme.error.withValues(alpha: 0.7)
            : AdminTheme.textSecondary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active
                ? AdminTheme.gold.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: active
                ? Border.all(color: AdminTheme.gold.withValues(alpha: 0.3))
                : null,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    final canvasW = _gridCols * _cellSize;
    final canvasH = _gridRows * _cellSize;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12121A), Color(0xFF16161E), Color(0xFF12121A)],
        ),
      ),
      child: InteractiveViewer(
        transformationController: _transformCtrl,
        minScale: 0.2,
        maxScale: 5.0,
        scaleFactor: 80.0, // 기본 200 → 80 (휠 줌 속도 감소)
        constrained: false,
        boundaryMargin: const EdgeInsets.all(200),
        child: GestureDetector(
          onTapDown: (details) => _onCanvasTap(details.localPosition),
          onPanStart: (details) {
            _onCanvasDragStart(details.localPosition);
          },
          onPanUpdate: (details) {
            if (_isDragging) _onCanvasDragUpdate(details.localPosition);
          },
          onPanEnd: (_) {
            _onCanvasDragEnd();
          },
          child: CustomPaint(
            size: Size(canvasW, canvasH),
            painter: _SeatGridPainter(
              gridCols: _gridCols,
              gridRows: _gridRows,
              cellSize: _cellSize,
              dotSize: _dotSize,
              seats: _seats,
              labels: _labels,
              stagePosition: _stagePosition,
              stageWidthRatio: _stageWidthRatio,
              stageHeight: _stageHeight,
              stageShape: _stageShape,
              selectedSeatKey: _selectedSeat?.key,
              gradeColors: gradeColors,
              emptyDotColor: _emptyDotColor,
              wheelchairColor: _wheelchairColor,
              holdColor: _holdColor,
              lineStart: _lineStart,
              dragIndicator: _dragIndicator,
              currentTool: _tool,
              isCmdPressed: _isCmdPressed,
              dividers: _dividers,
              dividerStart: _dividerStart,
              editorStep: _step,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(left: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // ─── Step Tabs ───
          _buildStepTabs(),
          // ─── Step Content ───
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              children: switch (_step) {
                _EditorStep.stage => _buildStagePanel(),
                _EditorStep.structure => _buildStructurePanel(),
                _EditorStep.seats => _buildSeatsPanel(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTabs() {
    Widget tab(_EditorStep step, String label, IconData icon) {
      final active = _step == step;
      final index = _EditorStep.values.indexOf(step) + 1;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _step = step;
            _dividerStart = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? AdminTheme.gold : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? AdminTheme.gold.withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: active ? AdminTheme.gold : AdminTheme.textTertiary,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: AdminTheme.sans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: active ? AdminTheme.gold : AdminTheme.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AdminTheme.sans(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? AdminTheme.gold : AdminTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          tab(_EditorStep.stage, '무대', Icons.stadium_rounded),
          tab(_EditorStep.structure, '구조', Icons.account_tree_rounded),
          tab(_EditorStep.seats, '좌석', Icons.event_seat_rounded),
        ],
      ),
    );
  }

  // ─── Step 1: 무대 설정 ───
  List<Widget> _buildStagePanel() {
    return [
      _panelSection(
        icon: Icons.grid_on_rounded,
        title: '그리드 크기',
        child: Row(
          children: [
            Expanded(
              child: _textField(
                label: '열',
                value: '$_gridCols',
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0 && n <= 120) {
                    setState(() => _gridCols = n);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('×',
                  style: AdminTheme.sans(
                      fontSize: 14, color: AdminTheme.textTertiary)),
            ),
            Expanded(
              child: _textField(
                label: '행',
                value: '$_gridRows',
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0 && n <= 80) {
                    setState(() => _gridRows = n);
                  }
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _panelSection(
        icon: Icons.stadium_rounded,
        title: '무대 설정',
        child: Column(
          children: [
            Row(
              children: [
                Text('무대 위치',
                    style: AdminTheme.sans(
                        fontSize: 11, color: AdminTheme.textSecondary)),
                const Spacer(),
                _toggleChip('상단', _stagePosition == 'top',
                    () => setState(() => _stagePosition = 'top')),
                const SizedBox(width: 4),
                _toggleChip('하단', _stagePosition == 'bottom',
                    () => setState(() => _stagePosition = 'bottom')),
              ],
            ),
            const SizedBox(height: 10),
            Text('무대 모양',
                style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                _stageShapeChip('rect', '사각형'),
                const SizedBox(width: 4),
                _stageShapeChip('arc', '아치형'),
                const SizedBox(width: 4),
                _stageShapeChip('trapezoid', '사다리꼴'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('무대 너비',
                    style: AdminTheme.sans(
                        fontSize: 10, color: AdminTheme.textTertiary)),
                Expanded(
                  child: Slider(
                    value: _stageWidthRatio,
                    min: 0.15,
                    max: 0.9,
                    activeColor: AdminTheme.gold,
                    onChanged: (v) =>
                        setState(() => _stageWidthRatio = v),
                  ),
                ),
                Text('${(_stageWidthRatio * 100).round()}%',
                    style: AdminTheme.sans(
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
            Row(
              children: [
                Text('무대 높이',
                    style: AdminTheme.sans(
                        fontSize: 10, color: AdminTheme.textTertiary)),
                Expanded(
                  child: Slider(
                    value: _stageHeight,
                    min: 16,
                    max: 60,
                    activeColor: AdminTheme.gold,
                    onChanged: (v) =>
                        setState(() => _stageHeight = v),
                  ),
                ),
                Text('${_stageHeight.round()}',
                    style: AdminTheme.sans(
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _stepNavButton('다음: 구조 설정 →', () => setState(() => _step = _EditorStep.structure)),
    ];
  }

  // ─── Step 2: 구조 설정 ───
  List<Widget> _buildStructurePanel() {
    return [
      _panelSection(
        icon: Icons.fence_rounded,
        title: '구분선 (팬스)',
        trailing: _dividerStart != null
            ? GestureDetector(
                onTap: () => setState(() => _dividerStart = null),
                child: Text('취소', style: AdminTheme.sans(fontSize: 10, color: AdminTheme.error)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    _dividerStart != null ? Icons.fiber_manual_record : Icons.touch_app_rounded,
                    size: 14,
                    color: _dividerStart != null ? AdminTheme.gold : AdminTheme.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dividerStart != null
                          ? '끝점을 클릭하세요 (시작: ${_dividerStart!.x},${_dividerStart!.y})'
                          : '캔버스에서 시작점을 클릭하세요',
                      style: AdminTheme.sans(
                        fontSize: 11,
                        color: _dividerStart != null ? AdminTheme.gold : AdminTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_dividers.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._dividers.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.remove_rounded, size: 12, color: AdminTheme.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '(${d.startX},${d.startY}) → (${d.endX},${d.endY})',
                            style: AdminTheme.sans(fontSize: 10, color: AdminTheme.textSecondary),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _dividers.removeAt(i)),
                          child: Icon(Icons.close_rounded, size: 14, color: AdminTheme.textTertiary),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      _panelSection(
        icon: Icons.text_fields_rounded,
        title: '라벨',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _tool = _tool == _EditorTool.text ? _EditorTool.paint : _EditorTool.text),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _tool == _EditorTool.text ? AdminTheme.gold.withValues(alpha: 0.15) : Colors.transparent,
                  border: Border.all(color: _tool == _EditorTool.text ? AdminTheme.gold : AdminTheme.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _tool == _EditorTool.text ? '배치 중' : '배치',
                  style: AdminTheme.sans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _tool == _EditorTool.text ? AdminTheme.gold : AdminTheme.textTertiary,
                  ),
                ),
              ),
            ),
            if (_labels.isNotEmpty) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _labels.clear()),
                child: Icon(Icons.delete_outline_rounded, size: 14, color: AdminTheme.textTertiary),
              ),
            ],
          ],
        ),
        child: Column(
          children: [
            if (_labels.isEmpty)
              Text(
                '캔버스를 클릭하여 라벨 배치 (라벨 모드 활성화 시)',
                style: AdminTheme.sans(fontSize: 10, color: AdminTheme.textTertiary),
              )
            else
              ..._labels.values.map((label) {
                final typeIcon = label.type == 'floor'
                    ? Icons.layers_rounded
                    : label.type == 'section'
                        ? Icons.grid_view_rounded
                        : Icons.text_snippet_rounded;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () => _showLabelDialog(label.gridX, label.gridY, existing: label),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(typeIcon, size: 12, color: AdminTheme.textTertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label.text,
                              style: AdminTheme.sans(fontSize: 11, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '(${label.gridX},${label.gridY})',
                            style: AdminTheme.sans(fontSize: 9, color: AdminTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: _stepNavButton('← 무대 설정', () => setState(() => _step = _EditorStep.stage))),
          const SizedBox(width: 8),
          Expanded(child: _stepNavButton('좌석 배치 →', () => setState(() => _step = _EditorStep.seats))),
        ],
      ),
    ];
  }

  // ─── Step 3: 좌석 배치 ───
  List<Widget> _buildSeatsPanel() {
    return [
      // Tools
      _panelSection(
        icon: Icons.construction_rounded,
        title: '도구',
        trailing: Text(
          {
            _EditorTool.paint: '페인트',
            _EditorTool.erase: '지우개',
            _EditorTool.select: '선택',
            _EditorTool.line: '라인',
            _EditorTool.text: '텍스트',
          }[_tool]!,
          style: AdminTheme.sans(
              fontSize: 10,
              color: AdminTheme.gold,
              fontWeight: FontWeight.w600),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _toolButton(
                    _EditorTool.paint, Icons.brush_rounded, '페인트'),
                const SizedBox(width: 4),
                _toolButton(_EditorTool.erase,
                    Icons.auto_fix_high_rounded, '지우개'),
                const SizedBox(width: 4),
                _toolButton(
                    _EditorTool.select, Icons.near_me_rounded, '선택'),
                const SizedBox(width: 4),
                _toolButton(_EditorTool.line,
                    Icons.timeline_rounded, '라인'),
                const SizedBox(width: 4),
                _toolButton(_EditorTool.text,
                    Icons.text_fields_rounded, '텍스트'),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  _shortcutRow('1~5', '도구 전환'),
                  const SizedBox(height: 3),
                  _shortcutRow('⌘+1~4', '등급 전환'),
                  const SizedBox(height: 3),
                  _shortcutRow('⌘+클릭', '지우기'),
                  const SizedBox(height: 3),
                  _shortcutRow('ESC', '취소'),
                ],
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 10),

      // Brush Settings
      _panelSection(
        icon: Icons.palette_rounded,
        title: '브러시 설정',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('등급',
                style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            PopupMenuButton<String>(
              onSelected: (grade) =>
                  setState(() => _selectedGrade = grade),
              offset: const Offset(0, 40),
              color: const Color(0xFF1E1E2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: AdminTheme.border.withValues(alpha: 0.6)),
              ),
              itemBuilder: (_) => ['VIP', 'R', 'S', 'A'].map((grade) {
                final color = gradeColors[grade]!;
                final isSelected = _selectedGrade == grade;
                return PopupMenuItem<String>(
                  value: grade,
                  height: 40,
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(grade,
                            style: AdminTheme.sans(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? color
                                  : AdminTheme.textPrimary,
                            )),
                      ),
                      if (isSelected)
                        Icon(Icons.check_rounded,
                            size: 16, color: color),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: gradeColors[_selectedGrade]!
                      .withValues(alpha: 0.12),
                  border: Border.all(
                    color: gradeColors[_selectedGrade]!,
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: gradeColors[_selectedGrade],
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: gradeColors[_selectedGrade]!
                                .withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_selectedGrade,
                          style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: gradeColors[_selectedGrade],
                          )),
                    ),
                    Icon(Icons.unfold_more_rounded,
                        size: 16,
                        color: gradeColors[_selectedGrade]),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Text('유형',
                style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: SeatType.values.map((type) {
                final isSelected = _selectedSeatType == type;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedSeatType = type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AdminTheme.gold.withValues(alpha: 0.15)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? AdminTheme.gold
                            : AdminTheme.border,
                        width: isSelected ? 1.5 : 0.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      type.displayName,
                      style: AdminTheme.sans(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AdminTheme.gold
                            : AdminTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            Text('구역',
                style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _textField(
              label: '구역명 (A, B, C...)',
              value: _currentZone,
              onChanged: (v) => setState(() => _currentZone = v),
            ),

            const SizedBox(height: 12),

            Text('층',
                style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: _floorPresets.map((floor) {
                final isSelected = _currentFloor == floor;
                return Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _currentFloor = floor),
                    child: Container(
                      margin: EdgeInsets.only(
                          right: floor != '4층' ? 4 : 0),
                      padding:
                          const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AdminTheme.gold
                                .withValues(alpha: 0.15)
                            : const Color(0xFF1A1A24),
                        border: Border.all(
                          color: isSelected
                              ? AdminTheme.gold
                              : AdminTheme.border
                                  .withValues(alpha: 0.5),
                          width: isSelected ? 1.5 : 0.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          floor,
                          style: AdminTheme.sans(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isSelected
                                ? AdminTheme.gold
                                : AdminTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),

      const SizedBox(height: 10),

      // Grade Prices
      _panelSection(
        icon: Icons.payments_rounded,
        title: '등급별 가격',
        child: Column(
          children: ['VIP', 'R', 'S', 'A']
              .map((grade) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: gradeColors[grade],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 32,
                          child: Text(grade,
                              style: AdminTheme.sans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: _textField(
                            label: '',
                            value: '${_gradePrice[grade] ?? 0}',
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null) {
                                setState(
                                    () => _gradePrice[grade] = n);
                              }
                            },
                            suffix: '원',
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),

      // Selected Seat Info
      if (_selectedSeat != null) ...[
        const SizedBox(height: 10),
        _panelSection(
          icon: Icons.touch_app_rounded,
          title: '선택된 좌석',
          child: _buildSelectedSeatPanel(),
        ),
      ],

      // Stats
      const SizedBox(height: 10),
      _panelSection(
        icon: Icons.analytics_rounded,
        title: '현황',
        child: Column(
          children: _buildStats(),
        ),
      ),

      const SizedBox(height: 20),
      _stepNavButton('← 구조 설정', () => setState(() => _step = _EditorStep.structure)),
    ];
  }

  Widget _stepNavButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AdminTheme.gold.withValues(alpha: 0.1),
          border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AdminTheme.gold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelSection({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AdminTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: AdminTheme.sans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textTertiary,
                  letterSpacing: 0.8,
                ),
              ),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSelectedSeatPanel() {
    final seat = _selectedSeat!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '위치: (${seat.gridX}, ${seat.gridY})',
          style:
              AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _textField(
                label: '구역',
                value: seat.zone,
                onChanged: (v) => _updateSelectedSeat(zone: v),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _textField(
                label: '열',
                value: seat.row,
                onChanged: (v) => _updateSelectedSeat(row: v),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _textField(
                label: '번호',
                value: '${seat.number}',
                onChanged: (v) => _updateSelectedSeat(
                    number: int.tryParse(v) ?? seat.number),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: ['VIP', 'R', 'S', 'A'].map((g) {
            return GestureDetector(
              onTap: () => _updateSelectedSeat(grade: g),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: seat.grade == g
                      ? gradeColors[g]!.withValues(alpha: 0.25)
                      : Colors.transparent,
                  border: Border.all(
                    color: seat.grade == g
                        ? gradeColors[g]!
                        : AdminTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(g,
                    style: AdminTheme.sans(
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: SeatType.values.map((t) {
            return GestureDetector(
              onTap: () => _updateSelectedSeat(seatType: t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: seat.seatType == t
                      ? AdminTheme.gold.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: seat.seatType == t
                        ? AdminTheme.gold
                        : AdminTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(t.displayName,
                    style: AdminTheme.sans(fontSize: 10)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _updateSelectedSeat({
    String? zone,
    String? floor,
    String? row,
    int? number,
    String? grade,
    SeatType? seatType,
  }) {
    if (_selectedSeat == null) return;
    final updated = _selectedSeat!.copyWith(
      zone: zone,
      floor: floor,
      row: row,
      number: number,
      grade: grade,
      seatType: seatType,
    );
    setState(() {
      _seats[updated.key] = updated;
      _selectedSeat = updated;
    });
  }

  List<Widget> _buildStats() {
    final counts = <String, int>{};
    int wheelchairCount = 0;
    int holdCount = 0;
    for (final seat in _seats.values) {
      counts[seat.grade] = (counts[seat.grade] ?? 0) + 1;
      if (seat.seatType == SeatType.wheelchair) wheelchairCount++;
      if (seat.seatType == SeatType.reservedHold) holdCount++;
    }

    return [
      ...['VIP', 'R', 'S', 'A']
          .where((g) => (counts[g] ?? 0) > 0)
          .map((grade) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: gradeColors[grade], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('$grade: ${counts[grade]}석',
                        style: AdminTheme.sans(fontSize: 12)),
                  ],
                ),
              )),
      if (wheelchairCount > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: _wheelchairColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('장애인석: $wheelchairCount석',
                  style: AdminTheme.sans(fontSize: 12)),
            ],
          ),
        ),
      if (holdCount > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: _holdColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('유보석: $holdCount석',
                  style: AdminTheme.sans(fontSize: 12)),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '총 ${_seats.length}석',
          style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AdminTheme.gold),
        ),
      ),
    ];
  }

  Widget _buildBottomBar() {
    // Calculate zoom level from transform matrix
    final matrix = _transformCtrl.value;
    final zoom = (matrix.getMaxScaleOnAxis() * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _shortcutBadge('1~5', '도구'),
          const SizedBox(width: 8),
          _shortcutBadge('⌘+1~4', '등급'),
          const SizedBox(width: 8),
          _shortcutBadge('⌘+클릭', '지우기'),
          const SizedBox(width: 8),
          _shortcutBadge('휠', '줌'),
          const Spacer(),
          // Grid info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_gridCols}×$_gridRows',
              style: AdminTheme.sans(
                  fontSize: 10,
                  color: AdminTheme.textTertiary,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          // Zoom level
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$zoom%',
              style: AdminTheme.sans(
                  fontSize: 10,
                  color: AdminTheme.textTertiary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(String key, String action) {
    return Row(
      children: [
        Icon(Icons.keyboard_rounded,
            size: 10, color: AdminTheme.textTertiary),
        const SizedBox(width: 5),
        Text(key,
            style: AdminTheme.sans(
                fontSize: 9,
                color: AdminTheme.textSecondary,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(action,
            style: AdminTheme.sans(
                fontSize: 9, color: AdminTheme.textTertiary)),
      ],
    );
  }

  Widget _shortcutBadge(String key, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A34),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
                color: AdminTheme.border.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Text(key,
              style: AdminTheme.sans(
                  fontSize: 9,
                  color: AdminTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        Text(action,
            style: AdminTheme.sans(
                fontSize: 10, color: AdminTheme.textTertiary)),
      ],
    );
  }

  // ─── Helpers ───

  Widget _toolButton(_EditorTool tool, IconData icon, String label) {
    final isSelected = _tool == tool;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tool = tool),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AdminTheme.gold.withValues(alpha: 0.15)
                : const Color(0xFF1A1A24),
            border: Border.all(
              color: isSelected
                  ? AdminTheme.gold
                  : AdminTheme.border.withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 0.5,
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AdminTheme.gold.withValues(alpha: 0.1),
                      blurRadius: 8,
                    )
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected
                      ? AdminTheme.gold
                      : AdminTheme.textSecondary),
              const SizedBox(height: 3),
              Text(label,
                  style: AdminTheme.sans(
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AdminTheme.gold
                        : AdminTheme.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AdminTheme.gold.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: selected ? AdminTheme.gold : AdminTheme.border,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: AdminTheme.sans(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AdminTheme.gold : AdminTheme.textSecondary,
            )),
      ),
    );
  }

  Widget _stageShapeChip(String shape, String label) {
    final isSelected = _stageShape == shape;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _stageShape = shape),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AdminTheme.gold.withValues(alpha: 0.15)
                : const Color(0xFF1A1A24),
            border: Border.all(
              color: isSelected
                  ? AdminTheme.gold
                  : AdminTheme.border.withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 0.5,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(label,
                style: AdminTheme.sans(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AdminTheme.gold : AdminTheme.textSecondary,
                )),
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? suffix,
  }) {
    return TextField(
      controller: TextEditingController(text: value),
      onChanged: onChanged,
      style: AdminTheme.sans(fontSize: 12),
      decoration: InputDecoration(
        labelText: label.isNotEmpty ? label : null,
        suffixText: suffix,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AdminTheme.label(fontSize: 10),
    );
  }
}

// ─── Canvas Painter ───

class _SeatGridPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  final double cellSize;
  final double dotSize;
  final Map<String, LayoutSeat> seats;
  final Map<String, LayoutLabel> labels;
  final String stagePosition;
  final double stageWidthRatio;
  final double stageHeight;
  final String stageShape;
  final String? selectedSeatKey;
  final Map<String, Color> gradeColors;
  final Color emptyDotColor;
  final Color wheelchairColor;
  final Color holdColor;
  final ({int x, int y})? lineStart;
  final Offset? dragIndicator;
  final _EditorTool currentTool;
  final bool isCmdPressed;
  final List<LayoutDivider> dividers;
  final ({int x, int y})? dividerStart;
  final _EditorStep editorStep;

  _SeatGridPainter({
    required this.gridCols,
    required this.gridRows,
    required this.cellSize,
    required this.dotSize,
    required this.seats,
    required this.labels,
    required this.stagePosition,
    required this.stageWidthRatio,
    required this.stageHeight,
    required this.stageShape,
    this.selectedSeatKey,
    required this.gradeColors,
    required this.emptyDotColor,
    required this.wheelchairColor,
    required this.holdColor,
    this.lineStart,
    this.dragIndicator,
    required this.currentTool,
    required this.isCmdPressed,
    this.dividers = const [],
    this.dividerStart,
    this.editorStep = _EditorStep.seats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ─── Stage area ───
    _drawStage(canvas, size);

    // ─── Dividers (구분선) ───
    _drawDividers(canvas);

    // ─── Empty dots ───
    final emptyPaint = Paint()
      ..color = emptyDotColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final dotR = dotSize / 2 - 1;

    final seatSize = dotSize - 2; // 사각형 크기
    const seatRadius = Radius.circular(3); // 라운드 코너

    for (int y = 0; y < gridRows; y++) {
      for (int x = 0; x < gridCols; x++) {
        final cx = x * cellSize + cellSize / 2;
        final cy = y * cellSize + cellSize / 2;
        final key = '$x,$y';

        if (seats.containsKey(key)) {
          final seat = seats[key]!;
          Color color;
          if (seat.seatType == SeatType.wheelchair) {
            color = wheelchairColor;
          } else if (seat.seatType == SeatType.reservedHold) {
            color = holdColor;
          } else {
            color = gradeColors[seat.grade] ?? emptyDotColor;
          }

          final seatRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: seatSize, height: seatSize),
            seatRadius,
          );

          final fillPaint = Paint()
            ..color = color
            ..style = PaintingStyle.fill;
          canvas.drawRRect(seatRect, fillPaint);

          // Subtle inner highlight (top-left light)
          final highlightPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.15)
            ..style = PaintingStyle.fill;
          final highlightRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - seatSize / 2 + 1, cy - seatSize / 2 + 1, seatSize * 0.45, seatSize * 0.35),
            const Radius.circular(2),
          );
          canvas.drawRRect(highlightRect, highlightPaint);

          // Selected highlight
          if (key == selectedSeatKey) {
            final selPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
            final selRect = RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(cx, cy), width: seatSize + 4, height: seatSize + 4),
              const Radius.circular(4),
            );
            canvas.drawRRect(selRect, selPaint);
          }

          // Wheelchair icon indicator (♿ dot)
          if (seat.seatType == SeatType.wheelchair) {
            final iconPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill;
            canvas.drawCircle(Offset(cx, cy), 2, iconPaint);
          }

          // Hold icon indicator (X mark)
          if (seat.seatType == SeatType.reservedHold) {
            final xPaint = Paint()
              ..color = Colors.white.withValues(alpha: 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;
            canvas.drawLine(
                Offset(cx - 3, cy - 3), Offset(cx + 3, cy + 3), xPaint);
            canvas.drawLine(
                Offset(cx + 3, cy - 3), Offset(cx - 3, cy + 3), xPaint);
          }
        } else {
          // Empty grid dot — small square outline
          final emptyRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: seatSize * 0.5, height: seatSize * 0.5),
            const Radius.circular(1.5),
          );
          canvas.drawRRect(emptyRect, emptyPaint);
        }
      }
    }

    // ─── Labels ───
    for (final label in labels.values) {
      _drawLabel(canvas, label);
    }

    // ─── Line Start Indicator ───
    if (lineStart != null) {
      final lx = lineStart!.x * cellSize + cellSize / 2;
      final ly = lineStart!.y * cellSize + cellSize / 2;
      final startPaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(lx, ly), dotR + 3, startPaint);
      // Crosshair
      canvas.drawLine(Offset(lx - 8, ly), Offset(lx + 8, ly), startPaint);
      canvas.drawLine(Offset(lx, ly - 8), Offset(lx, ly + 8), startPaint);
    }

    // ─── Drag Indicator ───
    if (dragIndicator != null) {
      final effectiveTool = isCmdPressed ? _EditorTool.erase : currentTool;
      final indicatorColor = effectiveTool == _EditorTool.erase
          ? const Color(0xFFFF5252)
          : effectiveTool == _EditorTool.paint
              ? const Color(0xFF69F0AE)
              : const Color(0xFF00E5FF);

      // Snap to grid
      final gx = (dragIndicator!.dx / cellSize).floor();
      final gy = (dragIndicator!.dy / cellSize).floor();
      final cx = gx * cellSize + cellSize / 2;
      final cy = gy * cellSize + cellSize / 2;

      final indicatorPaint = Paint()
        ..color = indicatorColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final indicatorRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: seatSize + 4, height: seatSize + 4),
        const Radius.circular(4),
      );
      canvas.drawRRect(indicatorRect, indicatorPaint);

      // Glow effect
      final glowPaint = Paint()
        ..color = indicatorColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final glowRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: seatSize + 10, height: seatSize + 10),
        const Radius.circular(6),
      );
      canvas.drawRRect(glowRect, glowPaint);
    }
  }

  void _drawLabel(Canvas canvas, LayoutLabel label) {
    final x = label.gridX * cellSize + cellSize / 2;
    final y = label.gridY * cellSize + cellSize / 2;

    Color textColor;
    FontWeight fontWeight;
    double letterSpacing;

    switch (label.type) {
      case 'floor':
        textColor = const Color(0xFFFFD54F); // warm gold
        fontWeight = FontWeight.w800;
        letterSpacing = 2.0;
        break;
      case 'section':
        textColor = const Color(0xFFB0BEC5); // soft grey-blue
        fontWeight = FontWeight.w600;
        letterSpacing = 0.5;
        break;
      default:
        textColor = const Color(0xFF90A4AE);
        fontWeight = FontWeight.w500;
        letterSpacing = 1.0;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: TextStyle(
          color: textColor,
          fontSize: label.fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    // Background pill for floor labels
    if (label.type == 'floor') {
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y),
          width: textPainter.width + 16,
          height: textPainter.height + 8,
        ),
        const Radius.circular(4),
      );
      final bgPaint = Paint()
        ..color = const Color(0xFF2A2A34)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(bgRect, bgPaint);
      final borderPaint = Paint()
        ..color = const Color(0xFFFFD54F).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(bgRect, borderPaint);
    }

    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  void _drawStage(Canvas canvas, Size size) {
    final stageW = size.width * stageWidthRatio;
    final stageH = stageHeight;
    final stageX = (size.width - stageW) / 2;
    final stageY = stagePosition == 'top' ? 4.0 : size.height - stageH - 4;

    final stagePaint = Paint()
      ..color = const Color(0xFF3A3A44)
      ..style = PaintingStyle.fill;
    final stageBorderPaint = Paint()
      ..color = const Color(0xFF4A4A54)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    switch (stageShape) {
      case 'arc':
        // 아치형 — 위가 볼록 (상단) / 아래가 볼록 (하단)
        final path = Path();
        if (stagePosition == 'top') {
          path.moveTo(stageX, stageY + stageH);
          path.lineTo(stageX, stageY + stageH * 0.4);
          path.quadraticBezierTo(
            stageX + stageW / 2, stageY - stageH * 0.3,
            stageX + stageW, stageY + stageH * 0.4,
          );
          path.lineTo(stageX + stageW, stageY + stageH);
          path.close();
        } else {
          path.moveTo(stageX, stageY);
          path.lineTo(stageX, stageY + stageH * 0.6);
          path.quadraticBezierTo(
            stageX + stageW / 2, stageY + stageH * 1.3,
            stageX + stageW, stageY + stageH * 0.6,
          );
          path.lineTo(stageX + stageW, stageY);
          path.close();
        }
        canvas.drawPath(path, stagePaint);
        canvas.drawPath(path, stageBorderPaint);
        break;

      case 'trapezoid':
        // 사다리꼴 — 관객쪽이 넓음
        final inset = stageW * 0.12;
        final path = Path();
        if (stagePosition == 'top') {
          // 위: 좁은 쪽, 아래: 넓은 쪽
          path.moveTo(stageX + inset, stageY);
          path.lineTo(stageX + stageW - inset, stageY);
          path.lineTo(stageX + stageW, stageY + stageH);
          path.lineTo(stageX, stageY + stageH);
          path.close();
        } else {
          // 위: 넓은 쪽, 아래: 좁은 쪽
          path.moveTo(stageX, stageY);
          path.lineTo(stageX + stageW, stageY);
          path.lineTo(stageX + stageW - inset, stageY + stageH);
          path.lineTo(stageX + inset, stageY + stageH);
          path.close();
        }
        canvas.drawPath(path, stagePaint);
        canvas.drawPath(path, stageBorderPaint);
        break;

      default: // rect
        final stageRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(stageX, stageY, stageW, stageH),
          const Radius.circular(4),
        );
        canvas.drawRRect(stageRect, stagePaint);
        canvas.drawRRect(stageRect, stageBorderPaint);
    }

    // Stage label
    final labelSize = math.min(stageH * 0.4, 12.0);
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'STAGE',
        style: TextStyle(
          color: const Color(0xFF666670),
          fontSize: labelSize,
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

    // Draw drag handles (stage step only)
    if (editorStep == _EditorStep.stage) {
      final handlePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.fill;
      final handleBorder = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const hs = 5.0; // handle size

      // Left handle
      final ly = stageY + stageH / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(stageX, ly), width: hs * 2, height: hs * 3),
          const Radius.circular(2),
        ),
        handlePaint,
      );
      // Right handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(stageX + stageW, ly), width: hs * 2, height: hs * 3),
          const Radius.circular(2),
        ),
        handlePaint,
      );
      // Bottom/Top handle (audience side)
      final bx = stageX + stageW / 2;
      final by = stagePosition == 'top' ? stageY + stageH : stageY;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(bx, by), width: hs * 3, height: hs * 2),
          const Radius.circular(2),
        ),
        handlePaint,
      );

      // Hint border around stage
      canvas.drawRect(
        Rect.fromLTWH(stageX - 1, stageY - 1, stageW + 2, stageH + 2),
        handleBorder,
      );
    }
  }

  void _drawDividers(Canvas canvas) {
    if (dividers.isEmpty && dividerStart == null) return;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 완성된 구분선들
    for (final d in dividers) {
      final x1 = d.startX * cellSize + cellSize / 2;
      final y1 = d.startY * cellSize + cellSize / 2;
      final x2 = d.endX * cellSize + cellSize / 2;
      final y2 = d.endY * cellSize + cellSize / 2;
      _drawDashedLine(canvas, Offset(x1, y1), Offset(x2, y2), paint);
    }

    // 구분선 시작점 표시
    if (dividerStart != null) {
      final cx = dividerStart!.x * cellSize + cellSize / 2;
      final cy = dividerStart!.y * cellSize + cellSize / 2;
      canvas.drawCircle(
        Offset(cx, cy),
        6,
        Paint()
          ..color = const Color(0xFF00E5FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      // 십자 표시
      canvas.drawLine(
        Offset(cx - 8, cy), Offset(cx + 8, cy),
        Paint()..color = const Color(0x8800E5FF)..strokeWidth = 0.5,
      );
      canvas.drawLine(
        Offset(cx, cy - 8), Offset(cx, cy + 8),
        Paint()..color = const Color(0x8800E5FF)..strokeWidth = 0.5,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    const dashLen = 4.0;
    const gapLen = 3.0;
    final unitX = dx / dist;
    final unitY = dy / dist;

    double drawn = 0;
    while (drawn < dist) {
      final start = Offset(p1.dx + unitX * drawn, p1.dy + unitY * drawn);
      final endD = math.min(drawn + dashLen, dist);
      final end = Offset(p1.dx + unitX * endD, p1.dy + unitY * endD);
      canvas.drawLine(start, end, paint);
      drawn += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _SeatGridPainter oldDelegate) => true;
}

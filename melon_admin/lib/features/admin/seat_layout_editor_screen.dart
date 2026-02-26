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

enum _EditorTool { paint, erase, select }

class _SeatLayoutEditorScreenState
    extends ConsumerState<SeatLayoutEditorScreen> {
  // ─── Grid State ───
  int _gridCols = 60;
  int _gridRows = 40;
  String _stagePosition = 'top';
  final Map<String, LayoutSeat> _seats = {}; // key: "x,y"
  final Map<String, int> _gradePrice = {
    'VIP': 100000,
    'R': 80000,
    'S': 60000,
    'A': 40000,
  };

  // ─── Editor State ───
  _EditorTool _tool = _EditorTool.paint;
  String _selectedGrade = 'VIP';
  SeatType _selectedSeatType = SeatType.normal;
  String _currentZone = 'A';
  String _currentFloor = '1층';
  LayoutSeat? _selectedSeat;
  final Set<String> _multiSelected = {};

  // ─── Canvas State ───
  final TransformationController _transformCtrl = TransformationController();
  static const double _dotSize = 14.0;
  static const double _dotGap = 2.0;
  static const double _cellSize = _dotSize + _dotGap;

  // ─── Loading ───
  bool _loading = true;
  bool _saving = false;
  bool _isDragging = false;
  bool _isRightDragging = false;
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

  @override
  void initState() {
    super.initState();
    _loadVenue();
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
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
          _gradePrice.addAll(layout.gradePrice);
          for (final seat in layout.seats) {
            _seats[seat.key] = seat;
          }
        }
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
        seats: _seats.values.toList(),
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

  // ─── Cmd key check ───
  bool get _isCmdPressed =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaRight);

  // ─── Canvas Tap ───
  void _onCanvasTap(Offset localPosition) {
    final gx = localPosition.dx ~/ _cellSize;
    final gy = localPosition.dy ~/ _cellSize;
    if (gx < 0 || gx >= _gridCols || gy < 0 || gy >= _gridRows) return;

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
    }
  }

  // ─── Right-click Erase ───
  void _onCanvasEraseAt(Offset localPosition) {
    final gx = localPosition.dx ~/ _cellSize;
    final gy = localPosition.dy ~/ _cellSize;
    if (gx < 0 || gx >= _gridCols || gy < 0 || gy >= _gridRows) return;

    final key = '$gx,$gy';
    if (_seats.containsKey(key)) {
      setState(() => _seats.remove(key));
    }
  }

  void _onCanvasDrag(Offset localPosition) {
    final gx = localPosition.dx ~/ _cellSize;
    final gy = localPosition.dy ~/ _cellSize;
    if (gx < 0 || gx >= _gridCols || gy < 0 || gy >= _gridRows) return;

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
    } else if (effectiveTool == _EditorTool.erase && _seats.containsKey(key)) {
      setState(() => _seats.remove(key));
    }
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
      body: Column(
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
                SizedBox(width: 280, child: _buildRightPanel()),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        right: 12,
        bottom: 8,
      ),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border:
            Border(bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/venues/${widget.venueId}');
              }
            },
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _venue?.name ?? '좌석 배치 편집',
                style: AdminTheme.sans(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                '${_seats.length}석 배치됨',
                style:
                    AdminTheme.sans(fontSize: 12, color: AdminTheme.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          // Excel guide toggle
          _topBarButton(
            icon: Icons.help_outline_rounded,
            label: '엑셀 가이드',
            onTap: () => setState(() => _showExcelGuide = !_showExcelGuide),
            active: _showExcelGuide,
          ),
          const SizedBox(width: 8),
          // Excel import
          _topBarButton(
            icon: Icons.upload_file_rounded,
            label: '엑셀 가져오기',
            onTap: _importExcel,
          ),
          const SizedBox(width: 8),
          // Auto number
          _topBarButton(
            icon: Icons.format_list_numbered_rounded,
            label: '자동 번호 매기기',
            onTap: _autoNumber,
          ),
          const SizedBox(width: 8),
          // Clear all
          _topBarButton(
            icon: Icons.delete_sweep_rounded,
            label: '전체 지우기',
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
          ),
          const SizedBox(width: 16),
          // Save button
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AdminTheme.onAccent))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_saving ? '저장 중...' : '저장'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AdminTheme.gold.withValues(alpha: 0.1) : null,
            border: Border.all(
                color: active ? AdminTheme.gold : AdminTheme.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? AdminTheme.gold : AdminTheme.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: AdminTheme.sans(
                      fontSize: 12,
                      color:
                          active ? AdminTheme.gold : AdminTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    final canvasW = _gridCols * _cellSize;
    final canvasH = _gridRows * _cellSize;

    return Container(
      color: const Color(0xFF16161C),
      child: InteractiveViewer(
        transformationController: _transformCtrl,
        minScale: 0.3,
        maxScale: 4.0,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(200),
        child: Listener(
          onPointerDown: (event) {
            if ((event.buttons & 0x02) != 0) {
              _isRightDragging = true;
              _onCanvasEraseAt(event.localPosition);
            }
          },
          onPointerMove: (event) {
            if (_isRightDragging) {
              _onCanvasEraseAt(event.localPosition);
            }
          },
          onPointerUp: (event) {
            _isRightDragging = false;
          },
          child: GestureDetector(
            onTapDown: (details) => _onCanvasTap(details.localPosition),
            onSecondaryTapDown: (_) {}, // prevent browser context menu
            onPanStart: (details) {
              _isDragging = true;
              _onCanvasDrag(details.localPosition);
            },
            onPanUpdate: (details) {
              if (_isDragging) _onCanvasDrag(details.localPosition);
            },
            onPanEnd: (_) => _isDragging = false,
            child: CustomPaint(
              size: Size(canvasW, canvasH),
              painter: _SeatGridPainter(
                gridCols: _gridCols,
                gridRows: _gridRows,
                cellSize: _cellSize,
                dotSize: _dotSize,
                seats: _seats,
                stagePosition: _stagePosition,
                selectedSeatKey: _selectedSeat?.key,
                gradeColors: gradeColors,
                emptyDotColor: _emptyDotColor,
                wheelchairColor: _wheelchairColor,
                holdColor: _holdColor,
              ),
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Tools ───
          _sectionLabel('도구'),
          const SizedBox(height: 8),
          Row(
            children: [
              _toolButton(_EditorTool.paint, Icons.brush_rounded, '페인트'),
              const SizedBox(width: 6),
              _toolButton(_EditorTool.erase, Icons.auto_fix_high_rounded, '지우개'),
              const SizedBox(width: 6),
              _toolButton(_EditorTool.select, Icons.near_me_rounded, '선택'),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: AdminTheme.border),
          const SizedBox(height: 16),

          // ─── Grade Selection ───
          _sectionLabel('좌석 등급'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ['VIP', 'R', 'S', 'A'].map((grade) {
              final isSelected = _selectedGrade == grade;
              final color = gradeColors[grade]!;
              return GestureDetector(
                onTap: () => setState(() => _selectedGrade = grade),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? color : AdminTheme.border,
                      width: isSelected ? 1.5 : 0.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      Text(grade,
                          style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected ? color : AdminTheme.textPrimary,
                          )),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // ─── Seat Type ───
          _sectionLabel('좌석 유형'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: SeatType.values.map((type) {
              final isSelected = _selectedSeatType == type;
              return GestureDetector(
                onTap: () => setState(() => _selectedSeatType = type),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AdminTheme.gold.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AdminTheme.gold : AdminTheme.border,
                      width: isSelected ? 1.5 : 0.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    type.displayName,
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color:
                          isSelected ? AdminTheme.gold : AdminTheme.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),
          const Divider(color: AdminTheme.border),
          const SizedBox(height: 16),

          // ─── Zone / Floor ───
          _sectionLabel('구역 / 층'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: '구역',
                  value: _currentZone,
                  onChanged: (v) => setState(() => _currentZone = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  label: '층',
                  value: _currentFloor,
                  onChanged: (v) => setState(() => _currentFloor = v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: AdminTheme.border),
          const SizedBox(height: 16),

          // ─── Grid Settings ───
          _sectionLabel('그리드 설정'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: '열 수',
                  value: '$_gridCols',
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0 && n <= 120) {
                      setState(() => _gridCols = n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  label: '행 수',
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
          const SizedBox(height: 12),
          Row(
            children: [
              Text('무대 위치:', style: AdminTheme.sans(fontSize: 12)),
              const SizedBox(width: 8),
              _toggleChip('상단', _stagePosition == 'top',
                  () => setState(() => _stagePosition = 'top')),
              const SizedBox(width: 6),
              _toggleChip('하단', _stagePosition == 'bottom',
                  () => setState(() => _stagePosition = 'bottom')),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: AdminTheme.border),
          const SizedBox(height: 16),

          // ─── Grade Prices ───
          _sectionLabel('등급별 가격'),
          const SizedBox(height: 8),
          ...['VIP', 'R', 'S', 'A'].map((grade) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: gradeColors[grade],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(grade,
                          style: AdminTheme.sans(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: _textField(
                        label: '',
                        value: '${_gradePrice[grade] ?? 0}',
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null) {
                            setState(() => _gradePrice[grade] = n);
                          }
                        },
                        suffix: '원',
                      ),
                    ),
                  ],
                ),
              )),

          // ─── Selected Seat Info ───
          if (_selectedSeat != null) ...[
            const SizedBox(height: 20),
            const Divider(color: AdminTheme.border),
            const SizedBox(height: 16),
            _sectionLabel('선택된 좌석'),
            const SizedBox(height: 8),
            _buildSelectedSeatPanel(),
          ],

          // ─── Stats ───
          const SizedBox(height: 20),
          const Divider(color: AdminTheme.border),
          const SizedBox(height: 16),
          _sectionLabel('현황'),
          const SizedBox(height: 8),
          ..._buildStats(),
        ],
      ),
    );
  }

  Widget _buildSelectedSeatPanel() {
    final seat = _selectedSeat!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '위치: (${seat.gridX}, ${seat.gridY})',
            style: AdminTheme.sans(fontSize: 12, color: AdminTheme.textSecondary),
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
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  label: '열',
                  value: seat.row,
                  onChanged: (v) => _updateSelectedSeat(row: v),
                ),
              ),
              const SizedBox(width: 8),
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
          Row(
            children: [
              Text('등급: ', style: AdminTheme.sans(fontSize: 12)),
              ...['VIP', 'R', 'S', 'A'].map((g) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () => _updateSelectedSeat(grade: g),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: seat.grade == g
                              ? gradeColors[g]!.withValues(alpha: 0.3)
                              : Colors.transparent,
                          border: Border.all(
                            color: seat.grade == g
                                ? gradeColors[g]!
                                : AdminTheme.border,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(g,
                            style: AdminTheme.sans(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('유형: ', style: AdminTheme.sans(fontSize: 12)),
              ...SeatType.values.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
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
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(t.displayName,
                            style: AdminTheme.sans(fontSize: 10)),
                      ),
                    ),
                  )),
            ],
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Keyboard shortcuts hint
          Text(
            '드래그: 연속 배치 · 우클릭/⌘+클릭: 지우기 · 선택 도구: 좌석 편집',
            style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary),
          ),
          const Spacer(),
          Text(
            '그리드: ${_gridCols}×$_gridRows',
            style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───

  Widget _toolButton(_EditorTool tool, IconData icon, String label) {
    final isSelected = _tool == tool;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tool = tool),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AdminTheme.gold.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border.all(
              color: isSelected ? AdminTheme.gold : AdminTheme.border,
              width: isSelected ? 1.5 : 0.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 18,
                  color: isSelected ? AdminTheme.gold : AdminTheme.textSecondary),
              const SizedBox(height: 2),
              Text(label,
                  style: AdminTheme.sans(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color:
                        isSelected ? AdminTheme.gold : AdminTheme.textSecondary,
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
  final String stagePosition;
  final String? selectedSeatKey;
  final Map<String, Color> gradeColors;
  final Color emptyDotColor;
  final Color wheelchairColor;
  final Color holdColor;

  _SeatGridPainter({
    required this.gridCols,
    required this.gridRows,
    required this.cellSize,
    required this.dotSize,
    required this.seats,
    required this.stagePosition,
    this.selectedSeatKey,
    required this.gradeColors,
    required this.emptyDotColor,
    required this.wheelchairColor,
    required this.holdColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ─── Stage area ───
    _drawStage(canvas, size);

    // ─── Empty dots ───
    final emptyPaint = Paint()
      ..color = emptyDotColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final dotR = dotSize / 2 - 1;

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

          final fillPaint = Paint()
            ..color = color
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(cx, cy), dotR, fillPaint);

          // Selected highlight
          if (key == selectedSeatKey) {
            final selPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
            canvas.drawCircle(Offset(cx, cy), dotR + 2, selPaint);
          }

          // Wheelchair icon indicator (smaller dot inside)
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
          canvas.drawCircle(Offset(cx, cy), dotR, emptyPaint);
        }
      }
    }
  }

  void _drawStage(Canvas canvas, Size size) {
    final stageW = size.width * 0.4;
    final stageH = 24.0;
    final stageX = (size.width - stageW) / 2;
    final stageY = stagePosition == 'top' ? 4.0 : size.height - stageH - 4;

    final stagePaint = Paint()
      ..color = const Color(0xFF3A3A44)
      ..style = PaintingStyle.fill;

    final stageRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(stageX, stageY, stageW, stageH),
      const Radius.circular(4),
    );
    canvas.drawRRect(stageRect, stagePaint);

    // Stage label
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'STAGE',
        style: TextStyle(
          color: Color(0xFF666670),
          fontSize: 10,
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
  bool shouldRepaint(covariant _SeatGridPainter oldDelegate) => true;
}

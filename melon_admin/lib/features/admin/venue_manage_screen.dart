import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/services/storage_service.dart';

/// 공연장 관리 화면 (목록 + 등록)
class VenueManageScreen extends ConsumerStatefulWidget {
  const VenueManageScreen({super.key});

  @override
  ConsumerState<VenueManageScreen> createState() => _VenueManageScreenState();
}

class _VenueManageScreenState extends ConsumerState<VenueManageScreen> {
  bool _showCreateForm = false;

  @override
  Widget build(BuildContext context) {
    final venuesAsync = ref.watch(venuesStreamProvider);

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: venuesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AdminTheme.gold)),
              error: (e, _) => Center(
                  child: Text('오류: $e',
                      style: AdminTheme.sans(color: AdminTheme.error))),
              data: (venues) {
                if (_showCreateForm) {
                  return _VenueCreateForm(
                    existingVenues: venues,
                    onBack: () => setState(() => _showCreateForm = false),
                    onCreated: () => setState(() => _showCreateForm = false),
                  );
                }
                return _buildVenueList(venues);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_showCreateForm) {
                setState(() => _showCreateForm = false);
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AdminTheme.textPrimary, size: 20),
          ),
          Expanded(
            child: Text(
              _showCreateForm ? '공연장 등록' : '공연장 관리',
              style: AdminTheme.serif(fontSize: 17),
            ),
          ),
          if (!_showCreateForm)
            GestureDetector(
              onTap: () => setState(() => _showCreateForm = true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: AdminTheme.goldGradient,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 16, color: AdminTheme.onAccent),
                    const SizedBox(width: 4),
                    Text(
                      '공연장 등록',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.onAccent,
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

  Widget _buildVenueList(List<Venue> venues) {
    if (venues.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AdminTheme.gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_city_rounded,
                  size: 36, color: AdminTheme.gold),
            ),
            const SizedBox(height: 16),
            Text(
              '등록된 공연장이 없습니다',
              style: AdminTheme.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '공연장을 등록하면 공연 등록 시 선택할 수 있습니다',
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showCreateForm = true),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('첫 공연장 등록하기',
                  style: AdminTheme.sans(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ),
      );
    }

    final fmt = NumberFormat('#,###');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: venues.length,
      itemBuilder: (context, index) {
        final venue = venues[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: InkWell(
              onTap: () => _showVenueDetail(venue),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  // 아이콘
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AdminTheme.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.location_city_rounded,
                        size: 24, color: AdminTheme.gold),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                venue.name,
                                style: AdminTheme.sans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AdminTheme.textPrimary,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (venue.seatMapImageUrl != null &&
                                    venue.seatMapImageUrl!.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AdminTheme.info.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('배치도',
                                        style: AdminTheme.sans(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AdminTheme.info,
                                        )),
                                  ),
                                if (venue.hasSeatView)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AdminTheme.gold.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('3D 시야',
                                        style: AdminTheme.sans(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AdminTheme.gold,
                                        )),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층'
                          '${venue.address != null ? ' · ${venue.address}' : ''}',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: venue.availableGrades
                              .map((g) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AdminTheme.surface,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(g,
                                        style: AdminTheme.sans(
                                          fontSize: 10,
                                          color: AdminTheme.textSecondary,
                                        )),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AdminTheme.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVenueDetail(Venue venue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VenueDetailSheet(venue: venue),
    );
  }
}

int _layoutDraftSeed = 0;

String _nextLayoutDraftId() =>
    'layout_${DateTime.now().microsecondsSinceEpoch}_${_layoutDraftSeed++}';

const String _stageTop = 'top';
const String _stageBottom = 'bottom';
const String _layoutHorizontal = 'horizontal';
const String _layoutVertical = 'vertical';
const int _layoutRowMin = 0;
const int _layoutRowMax = 6;
const int _layoutOffsetMin = -16;
const int _layoutOffsetMax = 16;

String _normalizeStagePosition(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == _stageBottom ? _stageBottom : _stageTop;
}

String _stagePositionLabel(String value) {
  return _normalizeStagePosition(value) == _stageBottom ? '하단' : '상단';
}

String _normalizeLayoutDirection(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == _layoutVertical ? _layoutVertical : _layoutHorizontal;
}

String _layoutDirectionLabel(String value) {
  return _normalizeLayoutDirection(value) == _layoutVertical ? '세로형' : '가로형';
}

Color _gradeColorForLayout(String? grade) {
  final normalized = (grade ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'VIP':
      return const Color(0xFFC9A84C);
    case 'R':
      return const Color(0xFF30D158);
    case 'S':
      return const Color(0xFF0A84FF);
    case 'A':
      return const Color(0xFFFF9F0A);
    default:
      return AdminTheme.info;
  }
}

String _displayFloorLabel(String floorName, int index) {
  final digits = RegExp(r'(\d+)').firstMatch(floorName);
  if (digits != null) {
    return '${digits.group(1)}F';
  }
  if (floorName.contains('지하')) {
    final basementDigits = RegExp(r'지하\s*(\d+)').firstMatch(floorName);
    if (basementDigits != null) {
      return 'B${basementDigits.group(1)}';
    }
    return 'B${index + 1}';
  }
  return floorName;
}

class _VenueLayoutEditorResult {
  final List<VenueFloor> floors;
  final String stagePosition;

  const _VenueLayoutEditorResult({
    required this.floors,
    required this.stagePosition,
  });
}

class _LayoutCustomRowDraft {
  final String id;
  String name;
  int seatCount;
  int offset;

  _LayoutCustomRowDraft({
    required this.id,
    required this.name,
    required this.seatCount,
    this.offset = 0,
  });
}

class _LayoutBlockDraft {
  final String id;
  String name;
  int rows;
  int seatsPerRow;
  String? grade;
  int layoutRow;
  int layoutOffset;
  String layoutDirection;
  bool useCustomRows;
  final List<_LayoutCustomRowDraft> customRows;

  _LayoutBlockDraft({
    required this.id,
    required this.name,
    required this.rows,
    required this.seatsPerRow,
    this.grade,
    this.layoutRow = 0,
    this.layoutOffset = 0,
    this.layoutDirection = 'horizontal',
    this.useCustomRows = false,
    List<_LayoutCustomRowDraft>? customRows,
  }) : customRows = customRows ?? [];
}

int _draftBlockTotalSeats(_LayoutBlockDraft block) {
  if (block.useCustomRows && block.customRows.isNotEmpty) {
    return block.customRows.fold<int>(0, (sum, row) => sum + row.seatCount);
  }
  return block.rows * block.seatsPerRow;
}

int _draftBlockRows(_LayoutBlockDraft block) {
  if (block.useCustomRows && block.customRows.isNotEmpty) {
    return block.customRows.length;
  }
  return block.rows;
}

int _draftBlockMaxSeatsPerRow(_LayoutBlockDraft block) {
  if (block.useCustomRows && block.customRows.isNotEmpty) {
    return block.customRows.fold<int>(
      0,
      (maxValue, row) => row.seatCount > maxValue ? row.seatCount : maxValue,
    );
  }
  return block.seatsPerRow;
}

List<VenueBlockCustomRow> _toCustomRows(_LayoutBlockDraft block) {
  if (!block.useCustomRows || block.customRows.isEmpty) {
    return const <VenueBlockCustomRow>[];
  }
  return block.customRows.asMap().entries.map((entry) {
    final index = entry.key;
    final row = entry.value;
    final rowName = row.name.trim().isEmpty ? '${index + 1}' : row.name.trim();
    return VenueBlockCustomRow(
      name: rowName,
      seatCount: row.seatCount,
      offset: row.offset,
    );
  }).toList();
}

class _LayoutFloorDraft {
  final String id;
  String name;
  final List<_LayoutBlockDraft> blocks;

  _LayoutFloorDraft({
    required this.id,
    required this.name,
    required this.blocks,
  });
}

List<_LayoutFloorDraft> _toLayoutDrafts(List<VenueFloor> floors) {
  return floors
      .map(
        (floor) => _LayoutFloorDraft(
          id: _nextLayoutDraftId(),
          name: floor.name,
          blocks: floor.blocks
              .map(
                (block) => _LayoutBlockDraft(
                  id: _nextLayoutDraftId(),
                  name: block.name,
                  rows: block.rows,
                  seatsPerRow: block.seatsPerRow,
                  grade: block.grade,
                  layoutRow: block.layoutRow,
                  layoutOffset: block.layoutOffset,
                  layoutDirection: _normalizeLayoutDirection(
                    block.layoutDirection,
                  ),
                  useCustomRows: block.customRows.isNotEmpty,
                  customRows: block.customRows
                      .map(
                        (row) => _LayoutCustomRowDraft(
                          id: _nextLayoutDraftId(),
                          name: row.name,
                          seatCount: row.seatCount,
                          offset: row.offset,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      )
      .toList();
}

List<VenueFloor> _toVenueFloors(List<_LayoutFloorDraft> drafts) {
  return drafts.map((floorDraft) {
    final blocks = floorDraft.blocks.map(
      (blockDraft) {
        final customRows = _toCustomRows(blockDraft);
        final rows =
            customRows.isNotEmpty ? customRows.length : blockDraft.rows;
        final seatsPerRow = customRows.isNotEmpty
            ? customRows.fold<int>(
                0,
                (maxValue, row) =>
                    row.seatCount > maxValue ? row.seatCount : maxValue,
              )
            : blockDraft.seatsPerRow;
        final totalSeats = customRows.isNotEmpty
            ? customRows.fold<int>(0, (sum, row) => sum + row.seatCount)
            : blockDraft.rows * blockDraft.seatsPerRow;
        return VenueBlock(
          name: blockDraft.name.trim(),
          rows: rows,
          seatsPerRow: seatsPerRow,
          totalSeats: totalSeats,
          grade: (blockDraft.grade?.trim().isNotEmpty ?? false)
              ? blockDraft.grade!.trim()
              : null,
          layoutRow: blockDraft.layoutRow,
          layoutOffset: blockDraft.layoutOffset,
          layoutDirection: _normalizeLayoutDirection(
            blockDraft.layoutDirection,
          ),
          customRows: customRows,
        );
      },
    ).toList();
    final floorTotalSeats =
        blocks.fold<int>(0, (sum, block) => sum + block.totalSeats);
    return VenueFloor(
      name: floorDraft.name.trim(),
      blocks: blocks,
      totalSeats: floorTotalSeats,
    );
  }).toList();
}

int _calcTotalSeats(List<VenueFloor> floors) {
  return floors.fold<int>(0, (sum, floor) => sum + floor.totalSeats);
}

String? _validateLayoutDrafts(List<_LayoutFloorDraft> drafts) {
  if (drafts.isEmpty) {
    return '층을 1개 이상 추가해주세요';
  }
  for (final floor in drafts) {
    if (floor.name.trim().isEmpty) {
      return '층 이름을 입력해주세요';
    }
    if (floor.blocks.isEmpty) {
      return '${floor.name}에 구역을 1개 이상 추가해주세요';
    }
    for (final block in floor.blocks) {
      if (block.name.trim().isEmpty) {
        return '${floor.name}의 구역명을 입력해주세요';
      }
      if (block.useCustomRows) {
        if (block.customRows.isEmpty) {
          return '${floor.name} ${block.name} 구역의 행 데이터를 1개 이상 추가해주세요';
        }
        for (final row in block.customRows) {
          if (row.seatCount <= 0) {
            return '${floor.name} ${block.name} 구역 행 좌석 수는 1 이상이어야 합니다';
          }
        }
      } else if (block.rows <= 0 || block.seatsPerRow <= 0) {
        return '${floor.name} ${block.name} 구역의 행/좌석 수는 1 이상이어야 합니다';
      }
    }
  }
  return null;
}

// =============================================================================
// 좌석 구조 편집 바텀시트
// =============================================================================

class _VenueLayoutEditorSheet extends StatefulWidget {
  final String venueName;
  final List<VenueFloor> initialFloors;
  final String initialStagePosition;

  const _VenueLayoutEditorSheet({
    required this.venueName,
    required this.initialFloors,
    required this.initialStagePosition,
  });

  @override
  State<_VenueLayoutEditorSheet> createState() =>
      _VenueLayoutEditorSheetState();
}

class _VenueLayoutEditorSheetState extends State<_VenueLayoutEditorSheet> {
  late List<_LayoutFloorDraft> _drafts;
  late String _stagePosition;
  final Map<String, Offset> _dragStartGlobal = <String, Offset>{};
  final Map<String, int> _dragStartRow = <String, int>{};
  final Map<String, int> _dragStartOffset = <String, int>{};

  @override
  void initState() {
    super.initState();
    _drafts = _toLayoutDrafts(widget.initialFloors);
    _stagePosition = _normalizeStagePosition(widget.initialStagePosition);
    if (_drafts.isEmpty) {
      _drafts = [
        _LayoutFloorDraft(
          id: _nextLayoutDraftId(),
          name: '1층',
          blocks: [
            _LayoutBlockDraft(
              id: _nextLayoutDraftId(),
              name: 'A',
              rows: 10,
              seatsPerRow: 10,
            ),
          ],
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktopEditor = screenSize.width >= 1100;
    final totalSeats = _toVenueFloors(_drafts)
        .fold<int>(0, (sum, floor) => sum + floor.totalSeats);
    final blockCount =
        _drafts.fold<int>(0, (sum, floor) => sum + floor.blocks.length);

    return Container(
      height: screenSize.height * (isDesktopEditor ? 0.94 : 0.88),
      decoration: const BoxDecoration(
        color: AdminTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AdminTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '좌석 구조 편집',
                        style: AdminTheme.serif(fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.venueName,
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    '닫기',
                    style: AdminTheme.sans(
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AdminTheme.border, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminTheme.surface,
                      border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _metric('층', '${_drafts.length}')),
                        Expanded(child: _metric('구역', '$blockCount')),
                        Expanded(
                            child: _metric('총 좌석',
                                '${NumberFormat('#,###').format(totalSeats)}석')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminTheme.surface,
                      border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '무대 위치',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('상단'),
                              selected: _stagePosition == _stageTop,
                              onSelected: (_) =>
                                  setState(() => _stagePosition = _stageTop),
                            ),
                            ChoiceChip(
                              label: const Text('하단'),
                              selected: _stagePosition == _stageBottom,
                              onSelected: (_) =>
                                  setState(() => _stagePosition = _stageBottom),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._drafts.map((floor) => _buildFloorCard(floor)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _addFloor,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminTheme.textPrimary,
                        side: const BorderSide(color: AdminTheme.border, width: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '층 추가',
                            style:
                                AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: AdminTheme.surface,
              border:
                  Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.textPrimary,
                      side: const BorderSide(color: AdminTheme.border, width: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      '취소',
                      style: AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyLayout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                    ),
                    child: Text(
                      '적용',
                      style: AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 11,
            color: AdminTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AdminTheme.sans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AdminTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildFloorCard(_LayoutFloorDraft floor) {
    final floorSeatCount = floor.blocks.fold<int>(
      0,
      (sum, block) => sum + _draftBlockTotalSeats(block),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${floor.id}-name'),
                  initialValue: floor.name,
                  onChanged: (value) => floor.name = value,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: '층 이름',
                    labelStyle: AdminTheme.sans(
                      color: AdminTheme.textTertiary,
                      fontSize: 12,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AdminTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          const BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          const BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          const BorderSide(color: AdminTheme.gold, width: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${NumberFormat('#,###').format(floorSeatCount)}석',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.gold,
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    _drafts.length == 1 ? null : () => _removeFloor(floor),
                icon: const Icon(Icons.delete_outline_rounded),
                color: AdminTheme.error,
                tooltip: '층 삭제',
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...floor.blocks.map((block) => _buildBlockCard(floor, block)),
          const SizedBox(height: 6),
          _buildBlockDragCanvas(floor),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _addBlock(floor),
              style: TextButton.styleFrom(
                foregroundColor: AdminTheme.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '구역 추가',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBlockDragCanvas(_LayoutFloorDraft floor) {
    final stageOnTop = _stagePosition == _stageTop;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktopEditor = screenWidth >= 1100;
    final canvasHeight = isDesktopEditor
        ? (floor.blocks.length >= 6 ? 420.0 : 360.0)
        : (floor.blocks.length >= 6 ? 320.0 : 280.0);
    const stageHeight = 34.0;
    const stageWidth = 180.0;
    const blockWidth = 112.0;
    const blockHeight = 52.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '구역 배치 드래그',
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '블록을 끌어서 이동',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final rowRange = math.max(1, _layoutRowMax - _layoutRowMin);
              final chartTop = stageOnTop ? stageHeight + 18 : 8.0;
              final chartBottom = stageOnTop ? 8.0 : stageHeight + 18;
              final chartHeight =
                  math.max(72.0, canvasHeight - chartTop - chartBottom);
              const horizontalSlots = _layoutOffsetMax - _layoutOffsetMin + 2;
              final xStep = math.max(
                8.0,
                (width - blockWidth - 24) / horizontalSlots,
              );
              final yStep = chartHeight / rowRange;

              double rowY(int row) {
                final clamped = row < _layoutRowMin
                    ? _layoutRowMin
                    : (row > _layoutRowMax ? _layoutRowMax : row);
                final normalized = (clamped - _layoutRowMin) / rowRange;
                return stageOnTop
                    ? chartTop + (normalized * chartHeight)
                    : chartTop + ((1 - normalized) * chartHeight);
              }

              double centerX(int offset) {
                final clamped = offset < _layoutOffsetMin
                    ? _layoutOffsetMin
                    : (offset > _layoutOffsetMax ? _layoutOffsetMax : offset);
                return (width / 2) + (clamped * xStep);
              }

              return SizedBox(
                height: canvasHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AdminTheme.card,
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: AdminTheme.border, width: 0.5),
                        ),
                      ),
                    ),
                    ...List.generate(rowRange + 1, (idx) {
                      final row = _layoutRowMin + idx;
                      final y = rowY(row);
                      return Positioned(
                        left: 8,
                        right: 8,
                        top: y,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              child: Text(
                                '${row + 1}',
                                style: AdminTheme.sans(
                                  fontSize: 9,
                                  color: AdminTheme.textTertiary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AdminTheme.border.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    Positioned(
                      top: stageOnTop ? 8 : null,
                      bottom: stageOnTop ? null : 8,
                      left: (width - stageWidth) / 2,
                      child: Container(
                        width: stageWidth,
                        height: stageHeight,
                        decoration: BoxDecoration(
                          color: AdminTheme.sage,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'STAGE',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AdminTheme.onAccent,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    ...floor.blocks.map((block) {
                      final gradeColor = _gradeColorForLayout(block.grade);
                      final seatText = NumberFormat('#,###')
                          .format(_draftBlockTotalSeats(block));
                      final gradeLabel =
                          (block.grade?.trim().isNotEmpty ?? false)
                              ? block.grade!.trim().toUpperCase()
                              : '미지정';
                      final x = centerX(block.layoutOffset);
                      final y = rowY(block.layoutRow);
                      final left = (x - (blockWidth / 2))
                          .clamp(0.0, math.max(0.0, width - blockWidth))
                          .toDouble();
                      final top = (y - (blockHeight / 2))
                          .clamp(0.0, math.max(0.0, canvasHeight - blockHeight))
                          .toDouble();
                      return Positioned(
                        left: left,
                        top: top,
                        width: blockWidth,
                        height: blockHeight,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: GestureDetector(
                            onPanStart: (details) =>
                                _startBlockDrag(block, details),
                            onPanUpdate: (details) => _updateBlockDrag(
                              block,
                              details,
                              stageOnTop: stageOnTop,
                              xStep: xStep,
                              yStep: yStep,
                            ),
                            onPanEnd: (_) => _endBlockDrag(block),
                            onPanCancel: () => _endBlockDrag(block),
                            child: Container(
                              decoration: BoxDecoration(
                                color: gradeColor.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: gradeColor, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: AdminTheme.sage.withValues(alpha: 0.2),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    block.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AdminTheme.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                      color: AdminTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$gradeLabel · $seatText석',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AdminTheme.sans(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.0,
                                      color: AdminTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _startBlockDrag(_LayoutBlockDraft block, DragStartDetails details) {
    _dragStartGlobal[block.id] = details.globalPosition;
    _dragStartRow[block.id] = block.layoutRow;
    _dragStartOffset[block.id] = block.layoutOffset;
  }

  void _updateBlockDrag(
    _LayoutBlockDraft block,
    DragUpdateDetails details, {
    required bool stageOnTop,
    required double xStep,
    required double yStep,
  }) {
    final startGlobal = _dragStartGlobal[block.id];
    final startRow = _dragStartRow[block.id];
    final startOffset = _dragStartOffset[block.id];
    if (startGlobal == null || startRow == null || startOffset == null) {
      return;
    }

    final dx = details.globalPosition.dx - startGlobal.dx;
    final dy = details.globalPosition.dy - startGlobal.dy;
    final offsetDelta = (dx / math.max(1, xStep)).round();
    final visualRowDelta = (dy / math.max(1, yStep)).round();
    final stageRowDelta = stageOnTop ? visualRowDelta : -visualRowDelta;

    var nextOffset = startOffset + offsetDelta;
    if (nextOffset < _layoutOffsetMin) nextOffset = _layoutOffsetMin;
    if (nextOffset > _layoutOffsetMax) nextOffset = _layoutOffsetMax;

    var nextRow = startRow + stageRowDelta;
    if (nextRow < _layoutRowMin) nextRow = _layoutRowMin;
    if (nextRow > _layoutRowMax) nextRow = _layoutRowMax;

    if (nextOffset == block.layoutOffset && nextRow == block.layoutRow) {
      return;
    }

    setState(() {
      block.layoutOffset = nextOffset;
      block.layoutRow = nextRow;
    });
  }

  void _endBlockDrag(_LayoutBlockDraft block) {
    _dragStartGlobal.remove(block.id);
    _dragStartRow.remove(block.id);
    _dragStartOffset.remove(block.id);
  }

  Widget _buildBlockCard(_LayoutFloorDraft floor, _LayoutBlockDraft block) {
    final seatCount = _draftBlockTotalSeats(block);
    final rowCount = _draftBlockRows(block);
    final maxSeatsPerRow = _draftBlockMaxSeatsPerRow(block);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${block.id}-name'),
                  initialValue: block.name,
                  onChanged: (value) => block.name = value,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('구역명'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextFormField(
                  key: ValueKey('${block.id}-grade'),
                  initialValue: block.grade ?? '',
                  onChanged: (value) => block.grade = value,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('등급'),
                ),
              ),
              IconButton(
                onPressed: floor.blocks.length == 1
                    ? null
                    : () => _removeBlock(floor, block),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                color: AdminTheme.error,
                tooltip: '구역 삭제',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '자유 편집 모드',
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Switch(
                value: block.useCustomRows,
                onChanged: (enabled) => _toggleCustomRowMode(block, enabled),
                activeThumbColor: AdminTheme.gold,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (block.useCustomRows) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _pill('${block.customRows.length}행'),
                      const SizedBox(width: 6),
                      _pill('${NumberFormat('#,###').format(seatCount)}석'),
                      const SizedBox(width: 6),
                      _pill('행 이동/추가 가능'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...block.customRows.asMap().entries.map(
                        (entry) => _buildCustomRowEditor(
                          block,
                          entry.key,
                          entry.value,
                        ),
                      ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _addCustomRow(block),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminTheme.textPrimary,
                        side: const BorderSide(color: AdminTheme.border, width: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '행 추가',
                            style:
                                AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('${block.id}-rows'),
                    initialValue: block.rows.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      block.rows = int.tryParse(value) ?? 0;
                      setState(() {});
                    },
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textPrimary,
                    ),
                    decoration: _fieldDecoration('행 수'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('${block.id}-seats-per-row'),
                    initialValue: block.seatsPerRow.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      block.seatsPerRow = int.tryParse(value) ?? 0;
                      setState(() {});
                    },
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textPrimary,
                    ),
                    decoration: _fieldDecoration('행당 좌석'),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AdminTheme.card,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${NumberFormat('#,###').format(seatCount)}석',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '배치 방향',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('가로형'),
                selected: _normalizeLayoutDirection(block.layoutDirection) ==
                    _layoutHorizontal,
                onSelected: block.useCustomRows
                    ? null
                    : (_) => setState(
                          () => block.layoutDirection = _layoutHorizontal,
                        ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('세로형'),
                selected: _normalizeLayoutDirection(block.layoutDirection) ==
                    _layoutVertical,
                onSelected: block.useCustomRows
                    ? null
                    : (_) => setState(
                          () => block.layoutDirection = _layoutVertical,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              block.useCustomRows
                  ? '자유 편집 모드에서는 행 위치/좌석 수를 직접 조정합니다'
                  : '기본 구성: ${block.rows}행 · 행당 ${block.seatsPerRow}석 · 배치는 드래그 화면에서 이동',
              style: AdminTheme.sans(
                fontSize: 10,
                color: AdminTheme.textTertiary,
              ),
            ),
          ),
          if (block.useCustomRows)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '현재 요약: $rowCount행 · 최대 $maxSeatsPerRow석/행 · 총 ${NumberFormat('#,###').format(seatCount)}석',
                  style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: AdminTheme.sans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AdminTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildCustomRowEditor(
      _LayoutBlockDraft block, int index, _LayoutCustomRowDraft row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${row.id}-name'),
                  initialValue: row.name,
                  onChanged: (value) => row.name = value,
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('행 라벨'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextFormField(
                  key: ValueKey('${row.id}-seat-count'),
                  initialValue: row.seatCount.toString(),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    row.seatCount = int.tryParse(value) ?? 0;
                    setState(() {});
                  },
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('좌석 수'),
                ),
              ),
              IconButton(
                onPressed:
                    index == 0 ? null : () => _moveCustomRow(block, index, -1),
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                tooltip: '위로 이동',
              ),
              IconButton(
                onPressed: index == block.customRows.length - 1
                    ? null
                    : () => _moveCustomRow(block, index, 1),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                tooltip: '아래로 이동',
              ),
              IconButton(
                onPressed: block.customRows.length <= 1
                    ? null
                    : () => _removeCustomRow(block, index),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: AdminTheme.error,
                tooltip: '행 삭제',
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '위치',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
              Expanded(
                child: Slider(
                  value: row.offset.toDouble().clamp(-12, 12),
                  min: -12,
                  max: 12,
                  divisions: 24,
                  activeColor: AdminTheme.gold,
                  onChanged: (value) {
                    setState(() => row.offset = value.round());
                  },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${row.offset}',
                  textAlign: TextAlign.right,
                  style: AdminTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleCustomRowMode(_LayoutBlockDraft block, bool enabled) {
    setState(() {
      block.useCustomRows = enabled;
      if (enabled && block.customRows.isEmpty) {
        for (var i = 0; i < block.rows; i++) {
          block.customRows.add(
            _LayoutCustomRowDraft(
              id: _nextLayoutDraftId(),
              name: '${i + 1}',
              seatCount: block.seatsPerRow,
            ),
          );
        }
      }
    });
  }

  void _addCustomRow(_LayoutBlockDraft block) {
    setState(() {
      final nextIdx = block.customRows.length + 1;
      final baseSeats = block.customRows.isNotEmpty
          ? block.customRows.last.seatCount
          : math.max(1, block.seatsPerRow);
      block.customRows.add(
        _LayoutCustomRowDraft(
          id: _nextLayoutDraftId(),
          name: '$nextIdx',
          seatCount: baseSeats,
        ),
      );
    });
  }

  void _removeCustomRow(_LayoutBlockDraft block, int index) {
    setState(() {
      block.customRows.removeAt(index);
    });
  }

  void _moveCustomRow(_LayoutBlockDraft block, int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= block.customRows.length) return;
    setState(() {
      final row = block.customRows.removeAt(index);
      block.customRows.insert(target, row);
    });
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: AdminTheme.sans(
        fontSize: 11,
        color: AdminTheme.textTertiary,
      ),
      isDense: true,
      filled: true,
      fillColor: AdminTheme.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AdminTheme.gold, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  void _addFloor() {
    setState(() {
      _drafts.add(
        _LayoutFloorDraft(
          id: _nextLayoutDraftId(),
          name: '${_drafts.length + 1}층',
          blocks: [
            _LayoutBlockDraft(
              id: _nextLayoutDraftId(),
              name: 'A',
              rows: 10,
              seatsPerRow: 10,
            ),
          ],
        ),
      );
    });
  }

  void _removeFloor(_LayoutFloorDraft floor) {
    setState(() {
      _drafts.removeWhere((item) => item.id == floor.id);
    });
  }

  void _addBlock(_LayoutFloorDraft floor) {
    setState(() {
      final index = floor.blocks.length;
      floor.blocks.add(
        _LayoutBlockDraft(
          id: _nextLayoutDraftId(),
          name: String.fromCharCode(65 + index),
          rows: 10,
          seatsPerRow: 10,
          layoutRow: index ~/ 3,
          layoutOffset: ((index % 3) - 1) * 6,
        ),
      );
    });
  }

  void _removeBlock(_LayoutFloorDraft floor, _LayoutBlockDraft block) {
    setState(() {
      floor.blocks.removeWhere((item) => item.id == block.id);
    });
  }

  void _applyLayout() {
    final validationError = _validateLayoutDrafts(_drafts);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    final floors = _toVenueFloors(_drafts);
    Navigator.pop(
      context,
      _VenueLayoutEditorResult(
        floors: floors,
        stagePosition: _stagePosition,
      ),
    );
  }
}

class _GeneratedSeatMapDiagram extends StatelessWidget {
  final List<VenueFloor> floors;
  final String stagePosition;
  final bool compact;
  final bool showSummaryLabel;

  const _GeneratedSeatMapDiagram({
    required this.floors,
    required this.stagePosition,
    required this.compact,
    this.showSummaryLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStagePosition = _normalizeStagePosition(stagePosition);
    final stageOnTop = normalizedStagePosition == _stageTop;
    final padding = compact ? 10.0 : 14.0;

    return Container(
      color: AdminTheme.surface,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSummaryLabel) ...[
              Text(
                '무대 위치: ${_stagePositionLabel(normalizedStagePosition)}',
                style: AdminTheme.sans(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (stageOnTop) ...[
              _buildStageLabel(compact),
              const SizedBox(height: 10),
            ],
            ...floors.asMap().entries.map(
                  (entry) => _buildFloorLayer(
                    floor: entry.value,
                    floorIndex: entry.key,
                    stageOnTop: stageOnTop,
                  ),
                ),
            if (!stageOnTop) ...[
              const SizedBox(height: 10),
              _buildStageLabel(compact),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStageLabel(bool isCompact) {
    return Center(
      child: Container(
        width: isCompact ? 160 : 230,
        padding: EdgeInsets.symmetric(vertical: isCompact ? 7 : 10),
        decoration: BoxDecoration(
          color: AdminTheme.sage,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'STAGE',
          textAlign: TextAlign.center,
          style: AdminTheme.sans(
            fontSize: isCompact ? 14 : 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AdminTheme.onAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildFloorLayer({
    required VenueFloor floor,
    required int floorIndex,
    required bool stageOnTop,
  }) {
    final fmt = NumberFormat('#,###');
    final floorLabel = _displayFloorLabel(floor.name, floorIndex);
    final blocksByRow = <int, List<VenueBlock>>{};
    for (final block in floor.blocks) {
      final rowKey = block.layoutRow < 0 ? 0 : block.layoutRow;
      blocksByRow.putIfAbsent(rowKey, () => <VenueBlock>[]).add(block);
    }
    for (final rowBlocks in blocksByRow.values) {
      rowBlocks.sort((a, b) {
        final offsetCompare = a.layoutOffset.compareTo(b.layoutOffset);
        if (offsetCompare != 0) return offsetCompare;
        return a.name.compareTo(b.name);
      });
    }
    var rowKeys = blocksByRow.keys.toList()..sort();
    if (!stageOnTop) {
      rowKeys = rowKeys.reversed.toList();
    }

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 14),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 10 : 12,
        compact ? 10 : 14,
        compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.cardElevated,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            floorLabel,
            textAlign: TextAlign.center,
            style: AdminTheme.serif(
              fontSize: compact ? 19 : 24,
              fontWeight: FontWeight.w800,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (rowKeys.isNotEmpty)
            ...rowKeys.map((rowKey) {
              final rowBlocks = blocksByRow[rowKey] ?? const <VenueBlock>[];
              return Padding(
                padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: compact ? 8 : 12,
                  runSpacing: compact ? 8 : 10,
                  children: rowBlocks.map((block) {
                    final xOffset =
                        block.layoutOffset.toDouble() * (compact ? 2.0 : 2.6);
                    return Transform.translate(
                      offset: Offset(xOffset, 0),
                      child: _GeneratedSeatBlock(
                        block: block,
                        compact: compact,
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          const SizedBox(height: 8),
          Text(
            '${floor.name} · ${fmt.format(floor.totalSeats)}석',
            textAlign: TextAlign.center,
            style: AdminTheme.sans(
              fontSize: compact ? 10 : 11,
              color: AdminTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratedSeatBlock extends StatelessWidget {
  final VenueBlock block;
  final bool compact;

  const _GeneratedSeatBlock({
    required this.block,
    required this.compact,
  });

  List<_GeneratedSeatRow> _resolveRows(String layoutDirection) {
    if (block.customRows.isNotEmpty) {
      final rows = block.customRows
          .where((row) => row.seatCount > 0)
          .map(
            (row) => _GeneratedSeatRow(
              seatCount: math.max(1, row.seatCount),
              offset: row.offset,
            ),
          )
          .toList();
      if (rows.isNotEmpty) return rows;
    }

    final rowCount = math.max(1, block.rows);
    final seatsPerRow = math.max(1, block.seatsPerRow);
    final visualRows =
        layoutDirection == _layoutVertical ? seatsPerRow : rowCount;
    final visualSeatsPerRow =
        layoutDirection == _layoutVertical ? rowCount : seatsPerRow;
    return List.generate(
      visualRows,
      (_) => _GeneratedSeatRow(seatCount: visualSeatsPerRow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradeColor = _gradeColorForLayout(block.grade);
    final layoutDirection = _normalizeLayoutDirection(block.layoutDirection);
    final rows = _resolveRows(layoutDirection);
    final isCustom = block.customRows.isNotEmpty;
    final dotSize = compact ? 5.0 : 6.0;
    final dotMargin = compact ? 1.0 : 1.2;
    final slotWidth = dotSize + (dotMargin * 2);
    final maxSeatCount = rows.fold<int>(
      1,
      (maxValue, row) => row.seatCount > maxValue ? row.seatCount : maxValue,
    );
    final minOffset = rows.fold<int>(
      0,
      (minValue, row) => row.offset < minValue ? row.offset : minValue,
    );
    final maxOffset = rows.fold<int>(
      0,
      (maxValue, row) => row.offset > maxValue ? row.offset : maxValue,
    );
    final totalSlots = maxSeatCount + (maxOffset - minOffset);
    final baseWidth = compact ? 86.0 : 112.0;
    final rowVisualWidth = math.max(slotWidth, totalSlots * slotWidth);
    final width =
        math.max(baseWidth, rowVisualWidth + 10).clamp(70.0, 260.0).toDouble();
    final seatFill = gradeColor.withValues(alpha: compact ? 0.6 : 0.72);
    final seatBorder = gradeColor.withValues(alpha: 0.95);
    final summaryText = isCustom
        ? '${rows.length}행 · 최대 $maxSeatCount석/행 · 자유 편집'
        : '${block.rows}열 x ${block.seatsPerRow} · ${_layoutDirectionLabel(layoutDirection)}';

    return SizedBox(
      width: width,
      child: Column(
        children: [
          Text(
            '${block.name}열',
            style: AdminTheme.sans(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ...rows.map((row) {
            final leadingSlots = row.offset - minOffset;
            return Padding(
              padding: EdgeInsets.only(bottom: compact ? 2 : 3),
              child: SizedBox(
                width: rowVisualWidth,
                child: Row(
                  children: [
                    if (leadingSlots > 0)
                      SizedBox(width: leadingSlots * slotWidth),
                    ...List.generate(row.seatCount, (_) {
                      return Container(
                        width: dotSize,
                        height: dotSize,
                        margin: EdgeInsets.all(dotMargin),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: seatFill,
                          border: Border.all(
                            color: seatBorder,
                            width: 0.45,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 2),
          Text(
            summaryText,
            style: AdminTheme.sans(
              fontSize: compact ? 9 : 10,
              color: AdminTheme.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratedSeatRow {
  final int seatCount;
  final int offset;

  const _GeneratedSeatRow({
    required this.seatCount,
    this.offset = 0,
  });
}

// =============================================================================
// 공연장 상세 바텀시트
// =============================================================================

class _VenueDetailSheet extends ConsumerStatefulWidget {
  final Venue venue;
  const _VenueDetailSheet({required this.venue});

  @override
  ConsumerState<_VenueDetailSheet> createState() => _VenueDetailSheetState();
}

class _VenueDetailSheetState extends ConsumerState<_VenueDetailSheet> {
  bool _isUploadingSeatMap = false;
  bool _isSavingLayout = false;
  String? _seatMapUrl;
  late List<VenueFloor> _floors;
  late String _stagePosition;

  @override
  void initState() {
    super.initState();
    _seatMapUrl = widget.venue.seatMapImageUrl;
    _floors = widget.venue.floors;
    _stagePosition = _normalizeStagePosition(widget.venue.stagePosition);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    final venue = widget.venue;
    final totalSeats = _calcTotalSeats(_floors);

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AdminTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AdminTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AdminTheme.goldGradient,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.location_city_rounded,
                      size: 22, color: AdminTheme.onAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venue.name,
                          style: AdminTheme.serif(fontSize: 18)),
                      if (venue.address != null)
                        Text(venue.address!,
                            style: AdminTheme.sans(
                              fontSize: 12,
                              color: AdminTheme.textTertiary,
                            )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AdminTheme.border, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _stat('총 좌석', '${fmt.format(totalSeats)}석'),
                      _stat('층수', '${_floors.length}층'),
                      _stat('무대', _stagePositionLabel(_stagePosition)),
                      _stat('3D 시야', venue.hasSeatView ? '등록됨' : '미등록'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('좌석 배치 자산',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      )),
                  const SizedBox(height: 8),
                  _buildSeatMapAssetCard(venue),
                  const SizedBox(height: 20),
                  Text('층/구역 구성',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      )),
                  const SizedBox(height: 8),
                  if (_floors.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminTheme.surface,
                        border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '등록된 좌석 구조가 없습니다. 좌석 구조 편집에서 추가해주세요.',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    )
                  else
                    ..._floors.map((floor) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(floor.name,
                                style: AdminTheme.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AdminTheme.textPrimary,
                                )),
                            const SizedBox(height: 8),
                            ...floor.blocks.map((block) => Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AdminTheme.card,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Text('${block.name}열',
                                          style: AdminTheme.sans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AdminTheme.textPrimary,
                                          )),
                                      const SizedBox(width: 8),
                                      if (block.grade != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color:
                                                AdminTheme.gold.withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(block.grade!,
                                              style: AdminTheme.sans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: AdminTheme.gold,
                                              )),
                                        ),
                                      const Spacer(),
                                      Builder(
                                        builder: (_) {
                                          final isCustom =
                                              block.customRows.isNotEmpty;
                                          final rowCount = isCustom
                                              ? block.customRows.length
                                              : block.rows;
                                          final modeText = isCustom
                                              ? '자유 편집'
                                              : _layoutDirectionLabel(
                                                  block.layoutDirection,
                                                );
                                          return Text(
                                              '$rowCount행 · ${fmt.format(block.totalSeats)}석 · $modeText',
                                              style: AdminTheme.sans(
                                                fontSize: 12,
                                                color: AdminTheme.textTertiary,
                                              ));
                                        },
                                      ),
                                    ],
                                  ),
                                )),
                            const SizedBox(height: 12),
                          ],
                        )),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: AdminTheme.surface,
              border:
                  Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSavingLayout
                            ? null
                            : () => _editSeatStructure(venue),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminTheme.textPrimary,
                          side: const BorderSide(color: AdminTheme.border, width: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isSavingLayout
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AdminTheme.gold,
                                ),
                              )
                            : Text('좌석 구조 편집',
                                style: AdminTheme.sans(
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(
                            '/venues/${venue.id}/views?name=${Uri.encodeComponent(venue.name)}',
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminTheme.textPrimary,
                          side: const BorderSide(color: AdminTheme.border, width: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('3D 시야 업로드',
                            style: AdminTheme.sans(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteVenue(context, ref, venue);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.error.withValues(alpha: 0.15),
                      foregroundColor: AdminTheme.error,
                      elevation: 0,
                    ),
                    child: Text('삭제',
                        style:
                            AdminTheme.sans(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editSeatStructure(Venue venue) async {
    final updated = await showModalBottomSheet<_VenueLayoutEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.of(sheetContext).size.width;
        final widthFactor = width >= 1100 ? 0.98 : 1.0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: _VenueLayoutEditorSheet(
              venueName: venue.name,
              initialFloors: _floors,
              initialStagePosition: _stagePosition,
            ),
          ),
        );
      },
    );

    if (updated == null) return;
    final updatedFloors = updated.floors;
    final updatedStagePosition = _normalizeStagePosition(updated.stagePosition);

    setState(() => _isSavingLayout = true);
    try {
      final totalSeats = _calcTotalSeats(updatedFloors);
      await ref.read(venueRepositoryProvider).updateVenue(
        venue.id,
        {
          'floors': updatedFloors.map((floor) => floor.toMap()).toList(),
          'totalSeats': totalSeats,
          'stagePosition': updatedStagePosition,
        },
      );
      if (!mounted) return;
      setState(() {
        _floors = updatedFloors;
        _stagePosition = updatedStagePosition;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('좌석 구조와 무대 위치가 저장되었습니다'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('좌석 구조 저장 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingLayout = false);
    }
  }

  Widget _buildSeatMapAssetCard(Venue venue) {
    final hasSeatMap = _seatMapUrl != null && _seatMapUrl!.isNotEmpty;
    final hasGeneratedMap = !hasSeatMap && _floors.isNotEmpty;
    final hasLayout = _floors.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasSeatMap
                      ? '좌석배치도 이미지 등록됨'
                      : hasGeneratedMap
                          ? '좌석 구조 기반 자동 배치도'
                          : '좌석배치도 미등록',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: hasSeatMap || hasGeneratedMap
                        ? AdminTheme.info
                        : AdminTheme.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed:
                    _isSavingLayout ? null : () => _editSeatStructure(venue),
                style: TextButton.styleFrom(
                  foregroundColor: AdminTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: _isSavingLayout
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminTheme.gold,
                        ),
                      )
                    : Text(
                        hasLayout ? '수정' : '구조 만들기',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              TextButton(
                onPressed: _isUploadingSeatMap
                    ? null
                    : () => _uploadSeatMapImage(venue),
                style: TextButton.styleFrom(
                  foregroundColor: AdminTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: _isUploadingSeatMap
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminTheme.gold,
                        ),
                      )
                    : Text(
                        hasSeatMap ? '배치도 교체' : '배치도 업로드',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: double.infinity,
              height: hasGeneratedMap ? 300 : 140,
              child: hasSeatMap
                  ? Image.network(
                      _seatMapUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _assetPlaceholder('배치도 이미지 로드 실패'),
                    )
                  : hasGeneratedMap
                      ? _buildGeneratedSeatMapPreview()
                      : _assetPlaceholder('좌석배치도 이미지를 업로드하세요'),
            ),
          ),
          if (hasGeneratedMap) ...[
            const SizedBox(height: 8),
            Text(
              '이미지가 없어도 좌석 구조 데이터로 배치도를 자동 생성합니다. STAGE(무대)는 ${_stagePositionLabel(_stagePosition)}에 표시됩니다.',
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneratedSeatMapPreview() {
    return _GeneratedSeatMapDiagram(
      floors: _floors,
      stagePosition: _stagePosition,
      compact: true,
      showSummaryLabel: true,
    );
  }

  Widget _assetPlaceholder(String text) {
    return Container(
      color: AdminTheme.surface,
      child: Center(
        child: Text(
          text,
          style: AdminTheme.sans(
            fontSize: 12,
            color: AdminTheme.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _uploadSeatMapImage(Venue venue) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (bytes == null || file == null) return;

      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미지 크기는 10MB 이하만 업로드 가능합니다'),
            backgroundColor: AdminTheme.error,
          ),
        );
        return;
      }

      setState(() => _isUploadingSeatMap = true);
      final oldUrl = _seatMapUrl;

      final imageUrl =
          await ref.read(storageServiceProvider).uploadSeatMapImage(
                bytes: bytes,
                venueId: venue.id,
                fileName: file.name,
              );
      await ref.read(venueRepositoryProvider).updateVenue(
        venue.id,
        {'seatMapImageUrl': imageUrl},
      );

      if (oldUrl != null && oldUrl.isNotEmpty) {
        await ref.read(storageServiceProvider).deleteFile(oldUrl);
      }

      if (!mounted) return;
      setState(() => _seatMapUrl = imageUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('좌석배치도 업로드 완료'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업로드 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingSeatMap = false);
    }
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: AdminTheme.card,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Text(value,
                style: AdminTheme.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.gold,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteVenue(
      BuildContext context, WidgetRef ref, Venue venue) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text('공연장 삭제',
            style: AdminTheme.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary)),
        content: Text('${venue.name}을(를) 삭제하시겠습니까?',
            style: AdminTheme.sans(
                fontSize: 14, color: AdminTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AdminTheme.textTertiary,
            ),
            child: Text('취소',
                style: AdminTheme.sans(color: AdminTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AdminTheme.error,
            ),
            child:
                Text('삭제', style: AdminTheme.sans(color: AdminTheme.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(venueRepositoryProvider).deleteVenue(venue.id);
    }
  }
}

// =============================================================================
// 공연장 등록 폼
// =============================================================================

class _VenueCreateForm extends ConsumerStatefulWidget {
  final List<Venue> existingVenues;
  final VoidCallback onBack;
  final VoidCallback onCreated;

  const _VenueCreateForm({
    required this.existingVenues,
    required this.onBack,
    required this.onCreated,
  });

  @override
  ConsumerState<_VenueCreateForm> createState() => _VenueCreateFormState();
}

class _VenueCreateFormState extends ConsumerState<_VenueCreateForm> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _selectedPreset;
  String _stagePosition = _stageTop;
  Uint8List? _seatMapBytes;
  String? _seatMapFileName;
  List<VenueFloor> _layoutFloors = [];

  // 프리셋으로 자동 채워진 경우
  Venue? _presetVenue;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width >= 900 ? 40 : 16,
        vertical: 20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프리셋 선택
              Text('프리셋 선택',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textSecondary,
                  )),
              const SizedBox(height: 10),
              _buildPresetOption(
                '스카이아트홀',
                '서울 등촌 · 409석 · 지하1~2층',
                'sky_art_hall',
              ),
              const SizedBox(height: 8),
              _buildPresetOption(
                '부산시민회관 대극장',
                '부산 동구 · 1,606석 · 1~2층',
                'busan_civic_hall',
              ),

              const SizedBox(height: 24),

              // 직접 입력
              Text('또는 직접 입력',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textSecondary,
                  )),
              const SizedBox(height: 10),

              _buildField('공연장명', _nameCtrl, '예: 스카이아트홀'),
              const SizedBox(height: 12),
              _buildField('주소 (선택)', _addressCtrl, '예: 서울특별시 강서구 등촌동'),
              const SizedBox(height: 12),
              _buildSeatMapUploadField(),
              const SizedBox(height: 12),
              _buildSeatLayoutField(),

              // 프리셋 미리보기
              if (_presetVenue != null) ...[
                const SizedBox(height: 20),
                _buildPresetPreview(_presetVenue!),
              ],

              const SizedBox(height: 28),

              // 등록 버튼
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _createVenue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.gold,
                    foregroundColor: AdminTheme.onAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    disabledBackgroundColor: AdminTheme.border,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AdminTheme.onAccent))
                      : Text('공연장 등록',
                          style: AdminTheme.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetOption(String name, String detail, String presetId) {
    final isSelected = _selectedPreset == presetId;
    return GestureDetector(
      onTap: () => _selectPreset(presetId),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AdminTheme.goldSubtle : AdminTheme.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AdminTheme.gold : AdminTheme.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AdminTheme.gold.withValues(alpha: 0.2)
                    : AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.location_city_rounded,
                  size: 20,
                  color: isSelected ? AdminTheme.gold : AdminTheme.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AdminTheme.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      )),
                  Text(detail,
                      style: AdminTheme.sans(
                        fontSize: 12,
                        color: AdminTheme.textTertiary,
                      )),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: AdminTheme.gold, size: 22),
          ],
        ),
      ),
    );
  }

  void _selectPreset(String presetId) {
    Venue preset;
    if (presetId == 'sky_art_hall') {
      preset = SkyArtHallPreset.venue;
    } else if (presetId == 'busan_civic_hall') {
      preset = BusanCivicHallPreset.venue;
    } else {
      return;
    }

    setState(() {
      _selectedPreset = presetId;
      _presetVenue = preset;
      _nameCtrl.text = preset.name;
      _addressCtrl.text = preset.address ?? '';
      _layoutFloors = preset.floors;
      _stagePosition = _normalizeStagePosition(preset.stagePosition);
    });
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            )),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          style:
              AdminTheme.sans(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AdminTheme.sans(
                fontSize: 13, color: AdminTheme.textTertiary),
            filled: true,
            fillColor: AdminTheme.card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AdminTheme.gold, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetPreview(Venue venue) {
    final fmt = NumberFormat('#,###');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AdminTheme.success, size: 16),
              const SizedBox(width: 8),
              Text('프리셋 미리보기',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.success,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Text('총 ${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층',
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textSecondary,
              )),
          const SizedBox(height: 6),
          ...venue.floors.map((floor) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${floor.name}: ${floor.blocks.map((b) => "${b.name}(${b.grade ?? "-"})").join(", ")}',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSeatMapUploadField() {
    final hasFile = _seatMapBytes != null && _seatMapFileName != null;
    final hasLayout = _layoutFloors.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('좌석배치도 이미지 (선택)',
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            )),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasFile ? _seatMapFileName! : '업로드된 파일 없음',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color:
                        hasFile ? AdminTheme.textPrimary : AdminTheme.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _pickSeatMapImage,
                style: TextButton.styleFrom(
                  foregroundColor: AdminTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: Text(
                  hasFile ? '교체' : '업로드',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminTheme.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AdminTheme.info.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasLayout
                    ? '이미지 없이도 작성한 좌석 구조로 자동 배치도를 생성합니다. 무대 위치도 함께 수정할 수 있습니다.'
                    : '좌석배치도 이미지가 없어도 아래 버튼에서 직접 좌석 구조를 만들 수 있습니다.',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _openSeatLayoutEditor,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminTheme.textPrimary,
                    side: const BorderSide(color: AdminTheme.border, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.construction_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        hasLayout ? '직접 만든 좌석 구조 편집' : '좌석배치도 직접 만들기',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeatLayoutField() {
    final fmt = NumberFormat('#,###');
    final totalSeats = _calcTotalSeats(_layoutFloors);
    final blockCount =
        _layoutFloors.fold<int>(0, (sum, floor) => sum + floor.blocks.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('좌석 구조',
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            )),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _layoutFloors.isEmpty
                    ? '아직 좌석 구조가 없습니다'
                    : '총 ${fmt.format(totalSeats)}석 · ${_layoutFloors.length}층 · $blockCount구역 · 무대 ${_stagePositionLabel(_stagePosition)}',
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: _layoutFloors.isEmpty
                      ? AdminTheme.textTertiary
                      : AdminTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '무대 위치',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('상단'),
                    selected: _stagePosition == _stageTop,
                    onSelected: (_) =>
                        setState(() => _stagePosition = _stageTop),
                  ),
                  ChoiceChip(
                    label: const Text('하단'),
                    selected: _stagePosition == _stageBottom,
                    onSelected: (_) =>
                        setState(() => _stagePosition = _stageBottom),
                  ),
                ],
              ),
              if (_layoutFloors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _layoutFloors
                      .map(
                        (floor) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AdminTheme.surface,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${floor.name} (${fmt.format(floor.totalSeats)}석)',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              color: AdminTheme.textSecondary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                _buildLayoutPreviewMap(),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _openSeatLayoutEditor,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminTheme.textPrimary,
                    side: const BorderSide(color: AdminTheme.border, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view_rounded, size: 17),
                      const SizedBox(width: 8),
                      Text(
                        _layoutFloors.isEmpty ? '좌석배치도 직접 만들기' : '좌석 구조 편집',
                        style: AdminTheme.sans(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutPreviewMap() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '자동 생성 배치도 미리보기',
            style: AdminTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _GeneratedSeatMapDiagram(
            floors: _layoutFloors,
            stagePosition: _stagePosition,
            compact: false,
            showSummaryLabel: true,
          ),
        ],
      ),
    );
  }

  Future<void> _openSeatLayoutEditor() async {
    final initialFloors =
        _layoutFloors.isNotEmpty ? _layoutFloors : (_presetVenue?.floors ?? []);
    final result = await showModalBottomSheet<_VenueLayoutEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.of(sheetContext).size.width;
        final widthFactor = width >= 1100 ? 0.98 : 1.0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: _VenueLayoutEditorSheet(
              venueName: _nameCtrl.text.trim().isEmpty
                  ? '새 공연장'
                  : _nameCtrl.text.trim(),
              initialFloors: initialFloors,
              initialStagePosition: _stagePosition,
            ),
          ),
        );
      },
    );

    if (result == null) return;
    setState(() {
      _layoutFloors = result.floors;
      _stagePosition = _normalizeStagePosition(result.stagePosition);
    });
  }

  Future<void> _pickSeatMapImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미지 크기는 10MB 이하만 가능합니다'),
            backgroundColor: AdminTheme.error,
          ),
        );
        return;
      }

      setState(() {
        _seatMapBytes = bytes;
        _seatMapFileName = file.name;
      });
    } catch (_) {
      // 선택 취소
    }
  }

  Future<void> _createVenue() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공연장명을 입력해주세요'),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    final floors = _layoutFloors.isNotEmpty
        ? _layoutFloors
        : (_presetVenue?.floors ?? <VenueFloor>[]);
    if (_seatMapBytes == null && floors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('좌석배치도 이미지가 없다면 좌석 구조를 먼저 직접 만들어주세요'),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final venue = Venue(
        id: '',
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? _presetVenue?.address
            : _addressCtrl.text.trim(),
        stagePosition: _stagePosition,
        floors: floors,
        totalSeats: _calcTotalSeats(floors),
        createdAt: DateTime.now(),
      );

      final venueId =
          await ref.read(venueRepositoryProvider).createVenue(venue);

      if (_seatMapBytes != null && _seatMapFileName != null) {
        final seatMapUrl =
            await ref.read(storageServiceProvider).uploadSeatMapImage(
                  bytes: _seatMapBytes!,
                  venueId: venueId,
                  fileName: _seatMapFileName!,
                );
        await ref.read(venueRepositoryProvider).updateVenue(
          venueId,
          {'seatMapImageUrl': seatMapUrl},
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${venue.name} 등록 완료'),
            backgroundColor: AdminTheme.success,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e'),
            backgroundColor: AdminTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

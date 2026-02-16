import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme.dart';
import '../../data/models/venue.dart';
import '../../data/repositories/venue_repository.dart';
import '../../data/repositories/venue_view_repository.dart';
import '../../services/storage_service.dart';

/// 공연장 시점 이미지 업로드 화면
class VenueViewUploadScreen extends ConsumerStatefulWidget {
  final String venueId;
  final String venueName;

  const VenueViewUploadScreen({
    super.key,
    required this.venueId,
    required this.venueName,
  });

  @override
  ConsumerState<VenueViewUploadScreen> createState() =>
      _VenueViewUploadScreenState();
}

class _VenueViewUploadScreenState extends ConsumerState<VenueViewUploadScreen> {
  final List<_ZoneViewEntry> _entries = [];
  bool _isUploading = false;
  String? _uploadStatus;
  String? _selectedLayoutFloor;
  String? _selectedLayoutZone;

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final venueAsync = ref.watch(venueStreamProvider(widget.venueId));
    final venue = venueAsync.valueOrNull;
    final viewsAsync = ref.watch(venueViewsProvider(widget.venueId));
    final existingViews = viewsAsync.valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 설명
                  _buildInfoCard(),
                  const SizedBox(height: 20),

                  // 기존 시점 이미지
                  if (existingViews.isNotEmpty) ...[
                    _buildSectionTitle('등록된 시점 이미지'),
                    const SizedBox(height: 10),
                    ...existingViews.entries
                        .map((e) => _buildExistingViewCard(e.key, e.value)),
                    const SizedBox(height: 24),
                  ],

                  // 새 이미지 추가
                  _buildSectionTitle('새 시점 이미지 추가'),
                  if (venue != null) ...[
                    const SizedBox(height: 8),
                    _buildLayoutTemplateCard(venue, existingViews),
                  ] else ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Text(
                        '공연장 좌석 정보를 불러오는 중입니다...',
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ..._entries
                      .asMap()
                      .entries
                      .map((e) => _buildEntryCard(e.key, e.value)),
                  const SizedBox(height: 10),
                  _buildAddButton(),
                  const SizedBox(height: 24),

                  // 업로드 상태
                  if (_uploadStatus != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppTheme.gold.withOpacity(0.3)),
                      ),
                      child: Text(
                        _uploadStatus!,
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          color: AppTheme.gold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),

      // 업로드 버튼
      bottomNavigationBar: _entries.isNotEmpty
          ? Container(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border:
                    Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _uploadAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: const Color(0xFFFDF3F6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: AppTheme.border,
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFDF3F6),
                          ),
                        )
                      : Text(
                          '${_entries.length}개 이미지 업로드',
                          style: GoogleFonts.notoSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '시점 이미지 관리',
                  style: GoogleFonts.notoSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  widget.venueName,
                  style: GoogleFonts.notoSans(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_rounded,
                    size: 14, color: Color(0xFFFDF3F6)),
                const SizedBox(width: 4),
                Text(
                  'Seat View',
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFDF3F6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withOpacity(0.2), width: 0.5),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.gold.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.threesixty_rounded,
                size: 26, color: AppTheme.gold),
          ),
          const SizedBox(height: 12),
          Text(
            '좌석 시점 이미지 (일반/360°)',
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '일반 카메라 사진과 360° 파노라마를 모두 등록할 수 있습니다.\n구역/층/행/좌석 단위로 업로드하면 예매 화면에서\n좌석 시야를 바로 확인할 수 있습니다.',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              fontSize: 13,
              color: AppTheme.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.notoSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildExistingViewCard(String key, VenueZoneView view) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 72,
              height: 48,
              child: Stack(
                children: [
                  Image.network(
                    view.imageUrl,
                    width: 72,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.surface,
                      child: const Icon(Icons.image_not_supported,
                          size: 20, color: AppTheme.textTertiary),
                    ),
                  ),
                  if (view.is360)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '360°',
                          style: GoogleFonts.notoSans(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.displayName,
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${view.floor}${view.is360 ? ' · 360° 파노라마' : ' · 일반 사진'}',
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
                if (view.description != null)
                  Text(
                    view.description!,
                    style: GoogleFonts.notoSans(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _deleteExistingView(key, view),
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(int index, _ZoneViewEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Thumbnail
              if (entry.imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 48,
                    child: Image.memory(
                      entry.imageBytes!,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 72,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Icon(Icons.add_photo_alternate_rounded,
                      size: 24, color: AppTheme.textTertiary),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    // Zone + Floor
                    Row(
                      children: [
                        Expanded(
                          child: _buildMiniField(
                            hint: '구역 (A, B...)',
                            controller: entry.zoneCtrl,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildMiniField(
                            hint: '층 (1층...)',
                            controller: entry.floorCtrl,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 52,
                          child: _buildMiniField(
                            hint: '행',
                            controller: entry.rowCtrl,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 56,
                          child: _buildMiniField(
                            hint: '좌석',
                            controller: entry.seatCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMiniField(
                            hint: '시야 설명 (선택)',
                            controller: entry.descCtrl,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ToggleButtons(
                          isSelected: [!entry.is360, entry.is360],
                          onPressed: (index) {
                            setState(() => entry.is360 = index == 1);
                          },
                          borderRadius: BorderRadius.circular(8),
                          borderColor: AppTheme.border,
                          selectedBorderColor: AppTheme.gold,
                          fillColor: AppTheme.gold.withOpacity(0.15),
                          constraints:
                              const BoxConstraints(minHeight: 34, minWidth: 58),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '일반',
                                style: GoogleFonts.notoSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: !entry.is360
                                      ? AppTheme.gold
                                      : AppTheme.textTertiary,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '360°',
                                style: GoogleFonts.notoSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: entry.is360
                                      ? AppTheme.gold
                                      : AppTheme.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Column(
                children: [
                  IconButton(
                    onPressed: () => _pickImage(index),
                    icon: const Icon(Icons.image_rounded,
                        size: 20, color: AppTheme.gold),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      final removed = _entries.removeAt(index);
                      removed.dispose();
                    }),
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppTheme.textTertiary),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniField({
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.notoSans(fontSize: 13, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.notoSans(fontSize: 12, color: AppTheme.textTertiary),
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.gold, width: 1),
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addEntry,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.gold.withOpacity(0.3),
            width: 1,
            strokeAlign: BorderSide.strokeAlignCenter,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_circle_outline_rounded,
                size: 20, color: AppTheme.gold),
            const SizedBox(width: 8),
            Text(
              '시점 이미지 추가',
              style: GoogleFonts.notoSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addEntry() {
    setState(() {
      _entries.add(_ZoneViewEntry());
    });
  }

  Widget _buildLayoutTemplateCard(
      Venue venue, Map<String, VenueZoneView> existingViews) {
    final layoutFloors = _resolveLayoutFloorsForPicker(venue, existingViews);
    final hasRealLayout = venue.floors.any((floor) => floor.blocks.isNotEmpty);
    final selectedFloor = layoutFloors.firstWhere(
      (floor) => floor.name == _selectedLayoutFloor,
      orElse: () => layoutFloors.first,
    );
    final selectedBlock = selectedFloor.blocks.firstWhere(
      (block) => block.name == _selectedLayoutZone,
      orElse: () => selectedFloor.blocks.isNotEmpty
          ? selectedFloor.blocks.first
          : VenueBlock(
              name: '',
              rows: 1,
              seatsPerRow: 1,
              totalSeats: 1,
            ),
    );
    final hasSelectedBlock = selectedBlock.name.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '좌석 구조 기반 템플릿',
            style: GoogleFonts.notoSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '추천 로직에서 사용하는 구역/층/행/좌석 키 기준으로 업로드 항목을 자동 생성합니다.',
            style: GoogleFonts.notoSans(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
          if (!hasRealLayout)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '좌석 구조가 없어 임시 배치도로 표시 중입니다. 공연장 관리에서 좌석 구조를 저장하면 정확한 배치가 반영됩니다.',
                style: GoogleFonts.notoSans(
                  fontSize: 10,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addEntriesFromLayout(
                    venue,
                    existingViews: existingViews,
                    includeRows: false,
                    floorsOverride: layoutFloors,
                  ),
                  icon: const Icon(Icons.grid_view_rounded, size: 16),
                  label: Text(
                    '구역 단위 생성',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addEntriesFromLayout(
                    venue,
                    existingViews: existingViews,
                    includeRows: true,
                    floorsOverride: layoutFloors,
                  ),
                  icon: const Icon(Icons.view_stream_rounded, size: 16),
                  label: Text(
                    '앞/중/뒤 열 생성',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '무대 배치도에서 구역 선택',
                  style: GoogleFonts.notoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '클릭: 행/좌석 선택, 더블클릭: 구역 대표 시야 업로드',
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: layoutFloors.map((floor) {
                    final selected = floor.name == selectedFloor.name;
                    return ChoiceChip(
                      label: Text(floor.name),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedLayoutFloor = floor.name;
                          _selectedLayoutZone = null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                _buildLayoutSelectionMap(
                  venue: venue,
                  floor: selectedFloor,
                  existingViews: existingViews,
                ),
                if (hasSelectedBlock) ...[
                  const SizedBox(height: 10),
                  _buildRowSeatClickUploader(
                    floor: selectedFloor,
                    block: selectedBlock,
                    existingViews: existingViews,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<VenueFloor> _resolveLayoutFloorsForPicker(
    Venue venue,
    Map<String, VenueZoneView> existingViews,
  ) {
    final realFloors =
        venue.floors.where((floor) => floor.blocks.isNotEmpty).toList();
    if (realFloors.isNotEmpty) {
      return realFloors;
    }

    final grouped = <String, Map<String, Set<String>>>{};
    for (final view in existingViews.values) {
      final floorName = view.floor.trim().isEmpty ? '1층' : view.floor.trim();
      final zoneName =
          view.zone.trim().isEmpty ? 'A' : view.zone.trim().toUpperCase();
      final zoneRows = grouped
          .putIfAbsent(floorName, () => <String, Set<String>>{})
          .putIfAbsent(zoneName, () => <String>{});
      final rowLabel = (view.row ?? '').trim();
      if (rowLabel.isNotEmpty) {
        zoneRows.add(rowLabel);
      }
    }

    if (grouped.isEmpty) {
      grouped['1층'] = {
        'A': <String>{'1'},
        'B': <String>{'1'},
        'C': <String>{'1'},
        'D': <String>{'1'},
      };
    }

    final floors = grouped.entries.map((entry) {
      final floorName = entry.key;
      final zones = entry.value.keys.toList()..sort();
      final blocks = zones.asMap().entries.map((zoneEntry) {
        final idx = zoneEntry.key;
        final zone = zoneEntry.value;
        final rowCount = math.max(1, entry.value[zone]!.length);
        return VenueBlock(
          name: zone,
          rows: rowCount,
          seatsPerRow: 3,
          totalSeats: rowCount * 3,
          layoutRow: idx ~/ 4,
          layoutOffset: _fallbackLayoutOffsetByIndex(idx),
        );
      }).toList();
      return VenueFloor(
        name: floorName,
        blocks: blocks,
        totalSeats: blocks.fold<int>(0, (sum, b) => sum + b.totalSeats),
      );
    }).toList();

    floors.sort((a, b) => a.name.compareTo(b.name));
    return floors;
  }

  int _fallbackLayoutOffsetByIndex(int index) {
    const offsets = <int>[-11, -4, 4, 11];
    return offsets[index % offsets.length];
  }

  Widget _buildLayoutSelectionMap({
    required Venue venue,
    required VenueFloor floor,
    required Map<String, VenueZoneView> existingViews,
  }) {
    final stageOnTop = _isStageOnTop(venue.stagePosition);
    final blocks = floor.blocks;
    if (blocks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          '${floor.name}에 구역이 없습니다',
          style: GoogleFonts.notoSans(
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      );
    }

    final maxLayoutRow = blocks.fold<int>(
      0,
      (maxValue, block) =>
          block.layoutRow > maxValue ? block.layoutRow : maxValue,
    );
    final rowCount = math.max(1, maxLayoutRow + 1);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1100;
    final canvasHeight =
        (isDesktop ? 170.0 : 150.0) + (rowCount * (isDesktop ? 56.0 : 50.0));

    const minOffset = -16;
    const maxOffset = 16;
    const blockWidth = 128.0;
    const blockHeight = 62.0;
    const stageHeight = 34.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final chartTop = stageOnTop ? stageHeight + 20 : 12.0;
        final chartBottom = stageOnTop ? 12.0 : stageHeight + 20;
        final rowRange = math.max(1, rowCount - 1);
        final chartHeight =
            math.max(120.0, canvasHeight - chartTop - chartBottom);
        final xStep = math.max(
          8.0,
          (width - blockWidth - 30) / ((maxOffset - minOffset) + 4),
        );

        double rowY(int row) {
          final clamped =
              row < 0 ? 0 : (row > maxLayoutRow ? maxLayoutRow : row);
          final normalized = rowRange == 0 ? 0.0 : clamped / rowRange;
          return stageOnTop
              ? chartTop + (normalized * chartHeight)
              : chartTop + ((1 - normalized) * chartHeight);
        }

        double centerX(int offset) {
          final clamped = offset < minOffset
              ? minOffset
              : (offset > maxOffset ? maxOffset : offset);
          return (width / 2) + (clamped * xStep);
        }

        return SizedBox(
          height: canvasHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border, width: 0.5),
                  ),
                ),
              ),
              ...List.generate(rowCount, (idx) {
                final y = rowY(idx);
                return Positioned(
                  left: 8,
                  right: 8,
                  top: y,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(
                          '${idx + 1}',
                          style: GoogleFonts.notoSans(
                            fontSize: 9,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppTheme.border.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              Positioned(
                top: stageOnTop ? 8 : null,
                bottom: stageOnTop ? null : 8,
                left: (width - (isDesktop ? 210.0 : 170.0)) / 2,
                child: Container(
                  width: isDesktop ? 210.0 : 170.0,
                  height: stageHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB8BEC9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'STAGE',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              ...blocks.map((block) {
                final center = centerX(block.layoutOffset);
                final top = (rowY(block.layoutRow) - (blockHeight / 2))
                    .clamp(0.0, math.max(0.0, canvasHeight - blockHeight))
                    .toDouble();
                final left = (center - (blockWidth / 2))
                    .clamp(0.0, math.max(0.0, width - blockWidth))
                    .toDouble();

                final pendingIdx =
                    _findPendingEntryIndex(block.name, floor.name, null);
                final hasPending = pendingIdx >= 0;
                final hasSaved = _hasSavedRepresentativeView(
                  existingViews,
                  zone: block.name,
                  floor: floor.name,
                );
                final isSelected = _selectedLayoutFloor == floor.name &&
                    _selectedLayoutZone == block.name;
                final baseColor = _gradeColorForBlock(block.grade);
                final borderColor = hasPending
                    ? AppTheme.gold
                    : (hasSaved ? AppTheme.success : baseColor);
                final statusText =
                    hasPending ? '업로드 대기' : (hasSaved ? '등록됨' : '선택');
                final gradeLabel = (block.grade?.trim().isNotEmpty ?? false)
                    ? block.grade!.trim().toUpperCase()
                    : '미지정';

                return Positioned(
                  left: left,
                  top: top,
                  width: blockWidth,
                  height: blockHeight,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _selectedLayoutFloor = floor.name;
                        _selectedLayoutZone = block.name;
                      });
                    },
                    onDoubleTap: () => _addEntryFromMapBlock(
                      floor: floor,
                      block: block,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 5),
                      decoration: BoxDecoration(
                        color: (isSelected ? AppTheme.gold : borderColor)
                            .withOpacity(isSelected ? 0.26 : 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppTheme.gold : borderColor,
                          width: isSelected ? 1.4 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.16),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            block.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$gradeLabel · ${block.totalSeats}석',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: borderColor,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRowSeatClickUploader({
    required VenueFloor floor,
    required VenueBlock block,
    required Map<String, VenueZoneView> existingViews,
  }) {
    final rowLabels = _rowLabelsForBlock(block);
    final gradeLabel = (block.grade?.trim().isNotEmpty ?? false)
        ? block.grade!.trim().toUpperCase()
        : '미지정';
    final seatTotal = rowLabels.fold<int>(
      0,
      (sum, row) => sum + _seatCountForRow(block, row),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.gold.withOpacity(0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '선택 구역: ${floor.name} ${block.name}구역',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: GoogleFonts.notoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 170,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _addEntryFromMapBlock(floor: floor, block: block),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(132, 34),
                  maximumSize: const Size(170, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.crop_square_rounded, size: 14),
                label: Text(
                  '구역 대표 업로드',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$gradeLabel · 총 $seatTotal석 · 좌석 점 클릭 시 해당 좌석 업로드 항목 생성',
            style: GoogleFonts.notoSans(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          ...rowLabels.map((rowLabel) {
            final seatCount = _seatCountForRow(block, rowLabel);
            final rowPendingCount =
                List<int>.generate(seatCount, (idx) => idx + 1)
                    .where((seatNumber) {
              return _findPendingEntryIndex(
                    block.name,
                    floor.name,
                    rowLabel,
                    seatNumber,
                  ) >=
                  0;
            }).length;
            final rowSavedCount =
                List<int>.generate(seatCount, (idx) => idx + 1)
                    .where((seatNumber) {
              return _hasSavedSeatView(
                existingViews,
                zone: block.name,
                floor: floor.name,
                row: rowLabel,
                seat: seatNumber,
              );
            }).length;
            final statusColor = rowPendingCount > 0
                ? AppTheme.gold
                : (rowSavedCount > 0
                    ? AppTheme.success
                    : AppTheme.textTertiary);
            final statusLabel = rowPendingCount > 0
                ? '대기 $rowPendingCount석'
                : (rowSavedCount > 0 ? '등록 $rowSavedCount석' : '미등록');

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$rowLabel행',
                        style: GoogleFonts.notoSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$seatCount석',
                        style: GoogleFonts.notoSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        statusLabel,
                        style: GoogleFonts.notoSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(seatCount, (seatIdx) {
                      final seatNumber = seatIdx + 1;
                      final hasPending = _findPendingEntryIndex(
                            block.name,
                            floor.name,
                            rowLabel,
                            seatNumber,
                          ) >=
                          0;
                      final hasSaved = _hasSavedSeatView(
                        existingViews,
                        zone: block.name,
                        floor: floor.name,
                        row: rowLabel,
                        seat: seatNumber,
                      );
                      final seatColor = hasPending
                          ? AppTheme.gold
                          : (hasSaved
                              ? AppTheme.success
                              : _gradeColorForBlock(block.grade));
                      final seatStatus =
                          hasPending ? '업로드 대기' : (hasSaved ? '등록됨' : '미등록');

                      return Tooltip(
                        waitDuration: const Duration(milliseconds: 250),
                        message: '$rowLabel행 $seatNumber번 · $seatStatus',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => _addEntryFromMapSeat(
                            floor: floor,
                            block: block,
                            rowLabel: rowLabel,
                            seatNumber: seatNumber,
                          ),
                          child: Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: seatColor.withOpacity(0.22),
                              border: Border.all(color: seatColor, width: 1),
                            ),
                            child: Text(
                              '$seatNumber',
                              style: GoogleFonts.notoSans(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: seatColor,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _addEntriesFromLayout(
    Venue venue, {
    required Map<String, VenueZoneView> existingViews,
    required bool includeRows,
    List<VenueFloor>? floorsOverride,
  }) {
    final floors = floorsOverride ?? venue.floors;
    final occupiedKeys = <String>{
      ...existingViews.values
          .map((view) => _entryKey(view.zone, view.floor, view.row, view.seat)),
      ..._entries.map((entry) => _entryKey(
          entry.zoneCtrl.text,
          entry.floorCtrl.text,
          entry.rowCtrl.text,
          _seatFromText(entry.seatCtrl.text))),
    };

    var added = 0;
    setState(() {
      for (final floor in floors) {
        for (final block in floor.blocks) {
          if (includeRows) {
            final rows = _suggestedRowsForBlock(block);
            for (final row in rows) {
              final key = _entryKey(block.name, floor.name, row);
              if (occupiedKeys.contains(key)) continue;
              occupiedKeys.add(key);
              _entries.add(
                _ZoneViewEntry(
                  zone: block.name,
                  floor: floor.name,
                  row: row,
                  description: '${floor.name} ${block.name}구역 $row열 시야',
                ),
              );
              added++;
            }
          } else {
            final key = _entryKey(block.name, floor.name, null);
            if (occupiedKeys.contains(key)) continue;
            occupiedKeys.add(key);
            _entries.add(
              _ZoneViewEntry(
                zone: block.name,
                floor: floor.name,
                description: '${floor.name} ${block.name}구역 대표 시야',
              ),
            );
            added++;
          }
        }
      }
    });

    if (!mounted) return;
    final message = added == 0
        ? '추가할 새 템플릿 항목이 없습니다 (기존/입력 항목과 중복)'
        : '$added개 업로드 항목을 좌석 구조 기준으로 추가했습니다';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: added == 0 ? AppTheme.textTertiary : AppTheme.success,
      ),
    );
  }

  int? _seatFromText(String? text) {
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  String _entryKey(String zone, String floor, String? row, [int? seat]) {
    return VenueSeatView.buildKey(
      zone: zone.trim().toUpperCase(),
      floor: floor.trim(),
      row: (row ?? '').trim(),
      seat: seat,
    );
  }

  List<String> _rowLabelsForBlock(VenueBlock block) {
    if (block.customRows.isNotEmpty) {
      return block.customRows.asMap().entries.map((entry) {
        final idx = entry.key;
        final label = entry.value.name.trim();
        return label.isEmpty ? '${idx + 1}' : label;
      }).toList();
    }
    return List.generate(math.max(1, block.rows), (idx) => '${idx + 1}');
  }

  int _seatCountForRow(VenueBlock block, String rowLabel) {
    if (block.customRows.isNotEmpty) {
      final custom = block.customRows.firstWhere(
        (row) => row.name.trim() == rowLabel.trim(),
        orElse: () => const VenueBlockCustomRow(name: '', seatCount: 0),
      );
      if (custom.seatCount > 0) {
        return custom.seatCount;
      }
    }
    return math.max(1, block.seatsPerRow);
  }

  List<String> _suggestedRowsForBlock(VenueBlock block) {
    final labels = _rowLabelsForBlock(block);
    if (labels.length <= 3) return labels;
    return [
      labels.first,
      labels[(labels.length / 2).floor()],
      labels.last,
    ];
  }

  bool _isStageOnTop(String? stagePosition) {
    final normalized = (stagePosition ?? '').trim().toLowerCase();
    return normalized != 'bottom';
  }

  Color _gradeColorForBlock(String? grade) {
    switch ((grade ?? '').trim().toUpperCase()) {
      case 'VIP':
        return const Color(0xFFC9A84C);
      case 'R':
        return const Color(0xFF30D158);
      case 'S':
        return const Color(0xFF0A84FF);
      case 'A':
        return const Color(0xFFFF9F0A);
      default:
        return AppTheme.info;
    }
  }

  int _findPendingEntryIndex(
    String zone,
    String floor,
    String? row, [
    int? seat,
  ]) {
    final normalizedZone = zone.trim().toUpperCase();
    final normalizedFloor = floor.trim();
    final normalizedRow = (row ?? '').trim();
    final normalizedSeat = seat;
    return _entries.indexWhere((entry) {
      final entryZone = entry.zoneCtrl.text.trim().toUpperCase();
      final entryFloor = entry.floorCtrl.text.trim();
      final entryRow = entry.rowCtrl.text.trim();
      final entrySeat = _seatFromText(entry.seatCtrl.text);
      return entryZone == normalizedZone &&
          entryFloor == normalizedFloor &&
          entryRow == normalizedRow &&
          entrySeat == normalizedSeat;
    });
  }

  bool _hasSavedRepresentativeView(
    Map<String, VenueZoneView> existingViews, {
    required String zone,
    required String floor,
  }) {
    final normalizedZone = zone.trim().toUpperCase();
    final normalizedFloor = floor.trim();
    return existingViews.values.any((view) {
      final matchesZone = view.zone.trim().toUpperCase() == normalizedZone;
      final matchesFloor = view.floor.trim() == normalizedFloor;
      final isRepresentative =
          (view.row == null || view.row!.trim().isEmpty) && view.seat == null;
      return matchesZone && matchesFloor && isRepresentative;
    });
  }

  bool _hasSavedSeatView(
    Map<String, VenueZoneView> existingViews, {
    required String zone,
    required String floor,
    required String row,
    required int seat,
  }) {
    final normalizedZone = zone.trim().toUpperCase();
    final normalizedFloor = floor.trim();
    final normalizedRow = row.trim();
    return existingViews.values.any((view) {
      final matchesZone = view.zone.trim().toUpperCase() == normalizedZone;
      final matchesFloor = view.floor.trim() == normalizedFloor;
      final viewRow = (view.row ?? '').trim();
      return matchesZone &&
          matchesFloor &&
          viewRow == normalizedRow &&
          view.seat == seat;
    });
  }

  Future<void> _addEntryFromMapBlock({
    required VenueFloor floor,
    required VenueBlock block,
  }) async {
    final pendingIdx = _findPendingEntryIndex(block.name, floor.name, null);
    if (pendingIdx >= 0) {
      await _pickImage(pendingIdx);
      return;
    }

    setState(() {
      _entries.add(
        _ZoneViewEntry(
          zone: block.name,
          floor: floor.name,
          description: '${floor.name} ${block.name}구역 대표 시야',
        ),
      );
    });

    final createdIndex = _entries.length - 1;
    await _pickImage(createdIndex);
  }

  Future<void> _addEntryFromMapSeat({
    required VenueFloor floor,
    required VenueBlock block,
    required String rowLabel,
    required int seatNumber,
  }) async {
    final normalizedRow = rowLabel.trim();
    final pendingIdx = _findPendingEntryIndex(
      block.name,
      floor.name,
      normalizedRow,
      seatNumber,
    );
    if (pendingIdx >= 0) {
      await _pickImage(pendingIdx);
      return;
    }

    setState(() {
      _entries.add(
        _ZoneViewEntry(
          zone: block.name,
          floor: floor.name,
          row: normalizedRow,
          seat: '$seatNumber',
          description:
              '${floor.name} ${block.name}구역 $normalizedRow행 $seatNumber번 시야',
        ),
      );
    });

    final createdIndex = _entries.length - 1;
    await _pickImage(createdIndex);
  }

  Future<void> _pickImage(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes != null) {
        setState(() {
          _entries[index].imageBytes = file.bytes;
          _entries[index].fileName = file.name;
        });
      }
    }
  }

  Future<void> _deleteExistingView(String key, VenueZoneView view) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '시점 이미지 삭제',
          style: GoogleFonts.notoSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          '${view.displayName} (${view.floor}) 시점 이미지를 삭제하시겠습니까?',
          style: GoogleFonts.notoSans(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소',
                style: GoogleFonts.notoSans(color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                Text('삭제', style: GoogleFonts.notoSans(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final repo = ref.read(venueViewRepositoryProvider);
        final venueRepo = ref.read(venueRepositoryProvider);
        final storage = ref.read(storageServiceProvider);
        await storage.deleteFile(view.imageUrl);
        await repo.deleteVenueView(
            widget.venueId, view.zone, view.floor, view.row, view.seat);
        final remainingViews = await repo.getVenueViews(widget.venueId);
        await venueRepo.updateVenue(
          widget.venueId,
          {'hasSeatView': remainingViews.isNotEmpty},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('삭제되었습니다'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('삭제 실패: $e'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _uploadAll() async {
    // Validate
    final valid = _entries.every((e) {
      final hasRequired =
          e.zoneCtrl.text.trim().isNotEmpty && e.imageBytes != null;
      final seatText = e.seatCtrl.text.trim();
      final seatValid = seatText.isEmpty || int.tryParse(seatText) != null;
      return hasRequired && seatValid;
    });
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('구역명/이미지를 입력하고 좌석 번호는 숫자로 입력해주세요'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = '업로드 준비 중...';
    });

    try {
      final storage = ref.read(storageServiceProvider);
      final repo = ref.read(venueViewRepositoryProvider);
      final venueRepo = ref.read(venueRepositoryProvider);
      final views = <VenueZoneView>[];

      for (int i = 0; i < _entries.length; i++) {
        final entry = _entries[i];
        setState(() {
          _uploadStatus =
              '${i + 1}/${_entries.length} 업로드 중... (${entry.zoneCtrl.text} 구역)';
        });

        final imageUrl = await storage.uploadVenueViewImage(
          bytes: entry.imageBytes!,
          venueId: widget.venueId,
          zone: entry.zoneCtrl.text.trim(),
          fileName: entry.fileName ?? 'view.jpg',
        );

        final rowText = entry.rowCtrl.text.trim();
        final seatNumber = _seatFromText(entry.seatCtrl.text);
        views.add(VenueZoneView(
          zone: entry.zoneCtrl.text.trim(),
          floor: entry.floorCtrl.text.trim().isEmpty
              ? '1층'
              : entry.floorCtrl.text.trim(),
          row: rowText.isEmpty ? null : rowText,
          seat: seatNumber,
          imageUrl: imageUrl,
          is360: entry.is360,
          description: entry.descCtrl.text.trim().isEmpty
              ? null
              : entry.descCtrl.text.trim(),
        ));
      }

      await repo.setVenueViews(widget.venueId, views);
      await venueRepo.updateVenue(widget.venueId, {'hasSeatView': true});

      setState(() {
        _uploadStatus = '${views.length}개 시점 이미지가 등록되었습니다!';
        _isUploading = false;
        for (final entry in _entries) {
          entry.dispose();
        }
        _entries.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${views.length}개 시점 이미지 등록 완료'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _uploadStatus = '업로드 실패: $e';
        _isUploading = false;
      });
    }
  }
}

class _ZoneViewEntry {
  final TextEditingController zoneCtrl;
  final TextEditingController floorCtrl;
  final TextEditingController rowCtrl;
  final TextEditingController seatCtrl;
  final TextEditingController descCtrl;
  bool is360 = false;
  Uint8List? imageBytes;
  String? fileName;

  _ZoneViewEntry({
    String zone = '',
    String floor = '1층',
    String? row,
    String? seat,
    String? description,
  })  : zoneCtrl = TextEditingController(text: zone),
        floorCtrl = TextEditingController(text: floor),
        rowCtrl = TextEditingController(text: row ?? ''),
        seatCtrl = TextEditingController(text: seat ?? ''),
        descCtrl = TextEditingController(text: description ?? '');

  void dispose() {
    zoneCtrl.dispose();
    floorCtrl.dispose();
    rowCtrl.dispose();
    seatCtrl.dispose();
    descCtrl.dispose();
  }
}

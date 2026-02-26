import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/venue.dart';

// =============================================================================
// MT-042: 좌석 등록 화면 — 도트맵 + CSV 탭 (Interactive Dotmap Seat Registration)
// - 도트맵 탭: 공연장 배치도 기반 인터랙티브 좌석 선택
// - CSV 탭: 기존 CSV 업로드 (폴백)
// =============================================================================

// ── Grade color constants ──
const _gradeColors = {
  'VIP': Color(0xFFC9A84C),
  'R': Color(0xFFE53935),
  'S': Color(0xFF1E88E5),
  'A': Color(0xFF43A047),
};

const _gradeOrder = ['VIP', 'R', 'S', 'A'];

class SeatUploadScreen extends ConsumerStatefulWidget {
  final String eventId;

  const SeatUploadScreen({super.key, required this.eventId});

  @override
  ConsumerState<SeatUploadScreen> createState() => _SeatUploadScreenState();
}

class _SeatUploadScreenState extends ConsumerState<SeatUploadScreen> {
  // ── Tab state: 0 = dotmap, 1 = CSV ──
  int _activeTab = 0;

  // ── CSV state ──
  final _csvController = TextEditingController();
  bool _isLoading = false;
  String? _previewText;
  List<Map<String, dynamic>> _previewSeats = [];

  // ── Dotmap state ──
  VenueSeatLayout? _seatLayout;
  bool _layoutLoading = true;
  String? _layoutError;
  Set<String> _selectedSeatKeys = {};
  String? _gradeFilter; // null = show all

  // ── Upload result state (shared) ──
  bool _uploadSuccess = false;
  int _uploadedCount = 0;
  Map<String, int> _uploadedGradeBreakdown = {};
  Map<String, int> _uploadedZoneBreakdown = {};

  // ── Seat editing state ──
  bool _isEditMode = false;
  Set<String> _editSelectedSeatIds = {};
  String? _editGradeFilter;
  String _editSortBy = 'seatKey'; // seatKey, grade, status
  bool _editSortAsc = true;

  @override
  void initState() {
    super.initState();
    _csvController.text = '''block,floor,row,number,grade
A,1층,1,1,VIP
A,1층,1,2,VIP
A,1층,1,3,VIP
A,1층,1,4,R
A,1층,1,5,R
A,1층,2,1,R
A,1층,2,2,S
A,1층,2,3,S
A,1층,2,4,S
A,1층,2,5,A
B,1층,1,1,A
B,1층,1,2,A
B,1층,1,3,S
B,1층,1,4,S
B,1층,1,5,R''';
    _loadVenueLayout();
  }

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VENUE LAYOUT LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadVenueLayout() async {
    setState(() {
      _layoutLoading = true;
      _layoutError = null;
    });

    try {
      // Get event to find venueId
      final event =
          await ref.read(eventRepositoryProvider).getEvent(widget.eventId);
      if (event == null) {
        setState(() {
          _layoutLoading = false;
          _layoutError = '공연 정보를 찾을 수 없습니다.';
          _activeTab = 1; // fallback to CSV
        });
        return;
      }

      if (event.venueId.isEmpty) {
        setState(() {
          _layoutLoading = false;
          _layoutError = '공연장이 설정되지 않았습니다.';
          _activeTab = 1;
        });
        return;
      }

      // Fetch venue
      final venue =
          await ref.read(venueRepositoryProvider).getVenue(event.venueId);
      if (venue == null) {
        setState(() {
          _layoutLoading = false;
          _layoutError = '공연장 정보를 찾을 수 없습니다.';
          _activeTab = 1;
        });
        return;
      }

      if (venue.seatLayout == null || venue.seatLayout!.seats.isEmpty) {
        setState(() {
          _layoutLoading = false;
          _seatLayout = null;
          _activeTab = 1; // fallback to CSV
        });
        return;
      }

      setState(() {
        _seatLayout = venue.seatLayout;
        _layoutLoading = false;
        _activeTab = 0; // default to dotmap
        // Select all seats by default
        _selectedSeatKeys =
            venue.seatLayout!.seats.map((s) => s.key).toSet();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _layoutLoading = false;
          _layoutError = '로드 실패: $e';
          _activeTab = 1;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CSV PARSING
  // ═══════════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _parseCsv(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.length < 2) return [];

    final headers = lines[0].split(',').map((h) => h.trim()).toList();
    final seats = <Map<String, dynamic>>[];

    for (var i = 1; i < lines.length; i++) {
      final values = lines[i].split(',').map((v) => v.trim()).toList();
      if (values.length != headers.length) continue;

      final seat = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        final key = headers[j];
        final value = values[j];
        if (key == 'number') {
          seat[key] = int.tryParse(value) ?? 0;
        } else {
          seat[key] = value;
        }
      }
      seats.add(seat);
    }

    return seats;
  }

  /// Grade breakdown from parsed seat data
  Map<String, int> _gradeBreakdown(List<Map<String, dynamic>> seats) {
    final map = <String, int>{};
    for (final s in seats) {
      final grade = (s['grade'] as String?) ?? 'N/A';
      map[grade] = (map[grade] ?? 0) + 1;
    }
    return map;
  }

  /// Zone (block) breakdown from parsed seat data
  Map<String, int> _zoneBreakdown(List<Map<String, dynamic>> seats) {
    final map = <String, int>{};
    for (final s in seats) {
      final block = (s['block'] as String?) ?? '?';
      map[block] = (map[block] ?? 0) + 1;
    }
    // Sort alphabetically
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return sorted;
  }

  void _preview() {
    final seats = _parseCsv(_csvController.text);
    setState(() {
      _previewSeats = seats;
      _previewText = '총 ${seats.length}개 좌석\n\n'
          '처음 5개:\n${seats.take(5).map((s) => '${s['block']}구역 ${s['floor']} ${s['row'] ?? ''}열 ${s['number']}번').join('\n')}';
      _uploadSuccess = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIRM REPLACE — existing seats check
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> _confirmReplaceSeats() async {
    final existingSeats =
        await ref.read(seatRepositoryProvider).getSeatsByEvent(widget.eventId);
    if (existingSeats.isEmpty) return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Text(
          '좌석 교체',
          style: AdminTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AdminTheme.textPrimary,
          ),
        ),
        content: Text(
          '기존 ${existingSeats.length}개 좌석이 삭제되고 새로 등록됩니다.\n계속하시겠습니까?',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(
                    fontSize: 13, color: AdminTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('교체',
                style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.gold)),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPLOAD — CSV
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _uploadCsvSeats() async {
    final seats = _parseCsv(_csvController.text);
    if (seats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 좌석 데이터가 없습니다')),
      );
      return;
    }

    if (seats.length > 1500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 1500석까지만 등록 가능합니다')),
      );
      return;
    }

    // Check existing seats and confirm replacement
    if (!await _confirmReplaceSeats()) return;

    setState(() => _isLoading = true);

    try {
      // Delete existing seats first
      await ref.read(seatRepositoryProvider).deleteAllSeats(widget.eventId);

      final count = await ref
          .read(seatRepositoryProvider)
          .createSeatsFromCsv(widget.eventId, seats);

      await ref.read(eventRepositoryProvider).updateEvent(widget.eventId, {
        'totalSeats': count,
        'availableSeats': count,
      });

      if (mounted) {
        setState(() {
          _uploadSuccess = true;
          _uploadedCount = count;
          _uploadedGradeBreakdown = _gradeBreakdown(seats);
          _uploadedZoneBreakdown = _zoneBreakdown(seats);
          _isLoading = false;
        });
        // Refresh the seats stream
        ref.invalidate(seatsStreamProvider(widget.eventId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPLOAD — DOTMAP
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _uploadDotmapSeats() async {
    if (_seatLayout == null || _selectedSeatKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('좌석을 선택해주세요')),
      );
      return;
    }

    final selectedSeats = _seatLayout!.seats
        .where((s) => _selectedSeatKeys.contains(s.key))
        .toList();

    if (selectedSeats.length > 1500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 1500석까지만 등록 가능합니다')),
      );
      return;
    }

    // Check existing seats and confirm replacement
    if (!await _confirmReplaceSeats()) return;

    setState(() => _isLoading = true);

    try {
      // Delete existing seats first
      await ref.read(seatRepositoryProvider).deleteAllSeats(widget.eventId);

      final seatData = selectedSeats.map((ls) {
        return <String, dynamic>{
          'block': ls.zone,
          'floor': ls.floor,
          'row': ls.row.isNotEmpty ? ls.row : null,
          'number': ls.number,
          'grade': ls.grade,
          'gridX': ls.gridX,
          'gridY': ls.gridY,
          'seatType': ls.seatType.name,
        };
      }).toList();

      final count = await ref
          .read(seatRepositoryProvider)
          .createSeatsFromLayout(widget.eventId, seatData);

      await ref.read(eventRepositoryProvider).updateEvent(widget.eventId, {
        'totalSeats': count,
        'availableSeats': count,
      });

      // Build breakdowns
      final gradeMap = <String, int>{};
      final zoneMap = <String, int>{};
      for (final ls in selectedSeats) {
        gradeMap[ls.grade] = (gradeMap[ls.grade] ?? 0) + 1;
        zoneMap[ls.zone] = (zoneMap[ls.zone] ?? 0) + 1;
      }
      final sortedZone = Map.fromEntries(
        zoneMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );

      if (mounted) {
        setState(() {
          _uploadSuccess = true;
          _uploadedCount = count;
          _uploadedGradeBreakdown = gradeMap;
          _uploadedZoneBreakdown = sortedZone;
          _isLoading = false;
        });
        ref.invalidate(seatsStreamProvider(widget.eventId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOTMAP SELECTION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _selectAll() {
    if (_seatLayout == null) return;
    setState(() {
      _selectedSeatKeys = _seatLayout!.seats.map((s) => s.key).toSet();
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedSeatKeys = {};
    });
  }

  void _selectByGrade(String grade) {
    if (_seatLayout == null) return;
    setState(() {
      _selectedSeatKeys = _seatLayout!.seats
          .where((s) => s.grade == grade)
          .map((s) => s.key)
          .toSet();
    });
  }

  void _toggleSeat(String seatKey) {
    setState(() {
      if (_selectedSeatKeys.contains(seatKey)) {
        _selectedSeatKeys.remove(seatKey);
      } else {
        _selectedSeatKeys.add(seatKey);
      }
    });
  }

  /// Get grade breakdown of currently selected seats
  Map<String, int> _selectedGradeBreakdown() {
    if (_seatLayout == null) return {};
    final map = <String, int>{};
    for (final seat in _seatLayout!.seats) {
      if (_selectedSeatKeys.contains(seat.key)) {
        map[seat.grade] = (map[seat.grade] ?? 0) + 1;
      }
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _layoutLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AdminTheme.gold),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.of(context).size.width >= 900 ? 40 : 20,
                      vertical: 32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: _buildContent(),
                      ),
                    ),
                  ),
          ),
          if (_isEditMode)
            _buildEditActionBar()
          else if (!_uploadSuccess)
            _buildBottomBar(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.background.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(
            color: AdminTheme.border,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.west,
                color: AdminTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Editorial Admin',
            style: AdminTheme.serif(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomBar() {
    final bool isDotmapActive = _activeTab == 0 && _seatLayout != null;
    final bool canUpload = isDotmapActive
        ? _selectedSeatKeys.isNotEmpty
        : true; // CSV handles validation in _uploadCsvSeats

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.background.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show selection summary for dotmap
          if (isDotmapActive) ...[
            _buildSelectionSummaryBar(),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading || !canUpload
                  ? null
                  : (isDotmapActive ? _uploadDotmapSeats : _uploadCsvSeats),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
                disabledBackgroundColor:
                    AdminTheme.sage.withValues(alpha: 0.3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AdminTheme.onAccent,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isDotmapActive
                              ? 'UPLOAD ${_selectedSeatKeys.length} SEATS'
                              : 'UPLOAD SEATS',
                          style: AdminTheme.serif(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AdminTheme.onAccent,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionSummaryBar() {
    final breakdown = _selectedGradeBreakdown();
    return Row(
      children: [
        Text(
          '${_selectedSeatKeys.length}석 선택됨',
          style: AdminTheme.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AdminTheme.gold,
          ),
        ),
        Text(
          ' / 총 ${_seatLayout?.seats.length ?? 0}석',
          style: AdminTheme.sans(
            fontSize: 13,
            color: AdminTheme.textTertiary,
          ),
        ),
        const Spacer(),
        ...() {
          final chips = <Widget>[];
          for (final g in _gradeOrder) {
            if (breakdown.containsKey(g)) {
              chips.add(Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _gradeColors[g],
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${breakdown[g]}',
                      style: AdminTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _gradeColors[g] ?? AdminTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ));
            }
          }
          return chips;
        }(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Page Title ──
        Text(
          '좌석 등록',
          style: AdminTheme.serif(
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 12,
          height: 1,
          color: AdminTheme.gold,
        ),
        const SizedBox(height: 32),

        // ── Section 0: Current Registration Status ──
        _buildCurrentStatusSection(),
        const SizedBox(height: 40),

        // ── Upload Success Card (shown after successful upload) ──
        if (_uploadSuccess) ...[
          _buildUploadSuccessCard(),
          const SizedBox(height: 40),
        ],

        // ── Tab switcher (only show when not in success state) ──
        if (!_uploadSuccess) ...[
          _buildTabSwitcher(),
          const SizedBox(height: 28),

          // Tab content
          if (_activeTab == 0)
            _buildDotmapTab()
          else
            _buildCsvTab(),
        ],

        const SizedBox(height: 100),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB SWITCHER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTabSwitcher() {
    final hasDotmap = _seatLayout != null;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              label: 'DOTMAP',
              icon: Icons.grid_on_rounded,
              isActive: _activeTab == 0,
              enabled: hasDotmap,
              onTap: hasDotmap ? () => setState(() => _activeTab = 0) : null,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _tabButton(
              label: 'CSV',
              icon: Icons.upload_file_rounded,
              isActive: _activeTab == 1,
              enabled: true,
              onTap: () => setState(() => _activeTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AdminTheme.gold.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive
                ? AdminTheme.gold.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: !enabled
                  ? AdminTheme.sage.withValues(alpha: 0.3)
                  : isActive
                      ? AdminTheme.gold
                      : AdminTheme.sage,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AdminTheme.label(
                fontSize: 10,
                color: !enabled
                    ? AdminTheme.sage.withValues(alpha: 0.3)
                    : isActive
                        ? AdminTheme.gold
                        : AdminTheme.sage,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AdminTheme.sage.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'N/A',
                  style: AdminTheme.label(
                    fontSize: 7,
                    color: AdminTheme.sage.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOTMAP TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDotmapTab() {
    if (_seatLayout == null) {
      return _buildNoDotmapMessage();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Selection toolbar ──
        _buildDotmapToolbar(),
        const SizedBox(height: 20),

        // ── Stage position indicator ──
        if (_seatLayout!.stagePosition == 'top') ...[
          _buildStageIndicator(),
          const SizedBox(height: 12),
        ],

        // ── Interactive dotmap ──
        _buildDotmapCanvas(),

        // ── Stage indicator (bottom) ──
        if (_seatLayout!.stagePosition == 'bottom') ...[
          const SizedBox(height: 12),
          _buildStageIndicator(),
        ],

        const SizedBox(height: 20),

        // ── Color legend ──
        _buildGradeLegend(),

        const SizedBox(height: 24),

        // ── Selection summary card ──
        if (_selectedSeatKeys.isNotEmpty) _buildDotmapSummaryCard(),
      ],
    );
  }

  Widget _buildNoDotmapMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.grid_off_rounded,
            size: 40,
            color: AdminTheme.sage.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _layoutError ?? '이 공연장에는 도트맵 배치도가 없습니다.',
            style: AdminTheme.sans(
              fontSize: 14,
              color: _layoutError != null
                  ? AdminTheme.error
                  : AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'CSV 탭에서 좌석을 등록해주세요.',
            style: AdminTheme.sans(
              fontSize: 13,
              color: AdminTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDotmapToolbar() {
    final layout = _seatLayout!;
    final allSelected =
        _selectedSeatKeys.length == layout.seats.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Select all / deselect all
          GestureDetector(
            onTap: allSelected ? _deselectAll : _selectAll,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: allSelected
                    ? AdminTheme.gold.withValues(alpha: 0.1)
                    : AdminTheme.background,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: allSelected
                      ? AdminTheme.gold.withValues(alpha: 0.3)
                      : AdminTheme.sage.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    allSelected
                        ? Icons.deselect
                        : Icons.select_all_rounded,
                    size: 14,
                    color: allSelected
                        ? AdminTheme.gold
                        : AdminTheme.sage,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    allSelected ? 'DESELECT ALL' : 'SELECT ALL',
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: allSelected
                          ? AdminTheme.gold
                          : AdminTheme.sage,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Grade filter buttons
          ..._gradeOrder.where((g) {
            return layout.seats.any((s) => s.grade == g);
          }).map((g) {
            final isActive = _gradeFilter == g;
            final color = _gradeColors[g] ?? AdminTheme.sage;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () {
                  if (isActive) {
                    // Deselect filter → select all
                    setState(() => _gradeFilter = null);
                    _selectAll();
                  } else {
                    setState(() => _gradeFilter = g);
                    _selectByGrade(g);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? color.withValues(alpha: 0.15)
                        : AdminTheme.background,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: isActive
                          ? color.withValues(alpha: 0.4)
                          : AdminTheme.sage.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    g,
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: isActive ? color : AdminTheme.sage,
                    ),
                  ),
                ),
              ),
            );
          }),

          const Spacer(),

          // Seat count
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '${_selectedSeatKeys.length} / ${layout.seats.length}',
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminTheme.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AdminTheme.gold.withValues(alpha: 0.0),
              AdminTheme.gold.withValues(alpha: 0.08),
              AdminTheme.gold.withValues(alpha: 0.0),
            ],
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          'STAGE',
          style: AdminTheme.label(
            fontSize: 9,
            color: AdminTheme.gold.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildDotmapCanvas() {
    final layout = _seatLayout!;
    // Calculate canvas height based on grid aspect ratio
    final aspectRatio = layout.gridCols / layout.gridRows;
    final canvasWidth = MediaQuery.of(context).size.width >= 900
        ? 860.0
        : MediaQuery.of(context).size.width - 40;
    final canvasHeight = (canvasWidth / aspectRatio).clamp(300.0, 700.0);

    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: _DotmapInteractiveCanvas(
            layout: layout,
            selectedKeys: _selectedSeatKeys,
            canvasSize: Size(canvasWidth, canvasHeight),
            onSeatTap: _toggleSeat,
          ),
        ),
      ),
    );
  }

  Widget _buildGradeLegend() {
    return Row(
      children: [
        Text(
          'GRADE',
          style: AdminTheme.label(
            fontSize: 9,
            color: AdminTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 16),
        ..._gradeOrder
            .where((g) =>
                _seatLayout?.seats.any((s) => s.grade == g) ?? false)
            .map((g) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _gradeColors[g],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  g,
                  style: AdminTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _gradeColors[g]!,
                  ),
                ),
              ],
            ),
          );
        }),
        const Spacer(),
        // Dimmed = deselected legend
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AdminTheme.sage.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '미선택',
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AdminTheme.gold,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '선택',
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDotmapSummaryCard() {
    final breakdown = _selectedGradeBreakdown();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.gold.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 16, color: AdminTheme.gold.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                'SELECTION SUMMARY',
                style: AdminTheme.label(
                  fontSize: 10,
                  color: AdminTheme.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // Total
          Row(
            children: [
              Text(
                '선택 좌석',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${_selectedSeatKeys.length}석',
                style: AdminTheme.sans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grade breakdown
          Text(
            'GRADE BREAKDOWN',
            style: AdminTheme.label(
              fontSize: 9,
              color: AdminTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          _buildGradeBarChart(breakdown),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CSV TAB (existing functionality)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCsvTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section 1: CSV 형식 안내 ──
        _sectionHeader('형식 안내'),
        const SizedBox(height: 20),
        _buildFormatGuide(),
        const SizedBox(height: 40),

        // ── Section 2: CSV 데이터 입력 ──
        _sectionHeader('CSV 데이터'),
        const SizedBox(height: 20),
        Text(
          'CSV DATA',
          style: AdminTheme.label(
            fontSize: 10,
            color: AdminTheme.sage,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AdminTheme.sage.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: TextFormField(
            controller: _csvController,
            decoration: InputDecoration(
              hintText: 'CSV 데이터를 붙여넣으세요',
              hintStyle: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.sage.withValues(alpha: 0.5),
              ),
              filled: false,
              contentPadding: const EdgeInsets.all(16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            maxLines: 15,
            style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AdminTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Preview Button ──
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _preview,
            style: TextButton.styleFrom(
              foregroundColor: AdminTheme.gold,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
                side: BorderSide(
                  color: AdminTheme.gold.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: Text(
              'PREVIEW',
              style: AdminTheme.label(
                fontSize: 10,
                color: AdminTheme.gold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Section 3: 미리보기 결과 ──
        if (_previewText != null) ...[
          _sectionHeader('미리보기'),
          const SizedBox(height: 20),
          _buildPreviewResult(),
          const SizedBox(height: 24),

          // ── Section 4: Preview Summary Card ──
          if (_previewSeats.isNotEmpty) ...[
            _buildPreviewSummaryCard(),
          ],
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 0: CURRENT REGISTRATION STATUS (Firestore live data)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCurrentStatusSection() {
    final seatsAsync = ref.watch(seatsStreamProvider(widget.eventId));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: seatsAsync.whenOrNull(
                        data: (seats) =>
                            seats.isEmpty ? AdminTheme.sage : AdminTheme.success,
                      ) ??
                      AdminTheme.sage,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CURRENT REGISTRATION',
                style: AdminTheme.label(
                  fontSize: 10,
                  color: AdminTheme.sage,
                ),
              ),
              const Spacer(),
              // Edit mode toggle
              seatsAsync.whenOrNull(
                data: (seats) => seats.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          setState(() {
                            _isEditMode = !_isEditMode;
                            _editSelectedSeatIds.clear();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isEditMode
                                ? AdminTheme.gold.withValues(alpha: 0.12)
                                : AdminTheme.background,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: _isEditMode
                                  ? AdminTheme.gold.withValues(alpha: 0.3)
                                  : AdminTheme.sage.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isEditMode
                                    ? Icons.close_rounded
                                    : Icons.edit_outlined,
                                size: 12,
                                color: _isEditMode
                                    ? AdminTheme.gold
                                    : AdminTheme.sage,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isEditMode ? 'DONE' : 'EDIT',
                                style: AdminTheme.label(
                                  fontSize: 9,
                                  color: _isEditMode
                                      ? AdminTheme.gold
                                      : AdminTheme.sage,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : null,
              ) ?? const SizedBox.shrink(),
              const SizedBox(width: 8),
              seatsAsync.when(
                data: (seats) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: seats.isEmpty
                        ? AdminTheme.sage.withValues(alpha: 0.1)
                        : AdminTheme.gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '${seats.length} SEATS',
                    style: AdminTheme.label(
                      fontSize: 10,
                      color: seats.isEmpty ? AdminTheme.sage : AdminTheme.gold,
                    ),
                  ),
                ),
                loading: () => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AdminTheme.sage,
                  ),
                ),
                error: (_, __) => Text(
                  'ERROR',
                  style: AdminTheme.label(fontSize: 9, color: AdminTheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // Grade breakdown chips
          seatsAsync.when(
            data: (seats) {
              if (seats.isEmpty) {
                return Row(
                  children: [
                    Icon(Icons.event_seat_outlined,
                        size: 16,
                        color: AdminTheme.sage.withValues(alpha: 0.4)),
                    const SizedBox(width: 8),
                    Text(
                      '등록된 좌석이 없습니다. 도트맵 또는 CSV로 업로드해 주세요.',
                      style: AdminTheme.sans(
                        fontSize: 13,
                        color: AdminTheme.textTertiary,
                      ),
                    ),
                  ],
                );
              }

              // Count by grade
              final gradeCounts = <String, int>{};
              final statusCounts = <SeatStatus, int>{};
              for (final seat in seats) {
                final grade = seat.grade ?? 'N/A';
                gradeCounts[grade] = (gradeCounts[grade] ?? 0) + 1;
                statusCounts[seat.status] =
                    (statusCounts[seat.status] ?? 0) + 1;
              }

              // Sort by _gradeOrder
              final sortedGrades = <MapEntry<String, int>>[];
              for (final g in _gradeOrder) {
                if (gradeCounts.containsKey(g)) {
                  sortedGrades.add(MapEntry(g, gradeCounts[g]!));
                }
              }
              // Add any grades not in the standard order
              for (final entry in gradeCounts.entries) {
                if (!_gradeOrder.contains(entry.key)) {
                  sortedGrades.add(entry);
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grade chips row
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: sortedGrades.map((entry) {
                      final color =
                          _gradeColors[entry.key] ?? AdminTheme.sage;
                      return _gradeChip(entry.key, entry.value, color);
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Status bar
                  _buildStatusBar(seats.length, statusCounts),

                  // ── Edit Mode: Seat Table ──
                  if (_isEditMode) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      height: 0.5,
                      color: AdminTheme.sage.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 16),
                    _buildSeatEditSection(seats),
                  ],
                ],
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AdminTheme.sage,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '좌석 데이터 로딩 중...',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            error: (e, _) => Text(
              '데이터 로드 실패: $e',
              style: AdminTheme.sans(fontSize: 13, color: AdminTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEAT EDIT SECTION — table + toolbar
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSeatEditSection(List<Seat> seats) {
    // Apply grade filter
    final filtered = _editGradeFilter != null
        ? seats.where((s) => s.grade == _editGradeFilter).toList()
        : List<Seat>.from(seats);

    // Sort
    filtered.sort((a, b) {
      int cmp;
      switch (_editSortBy) {
        case 'grade':
          final ai = _gradeOrder.indexOf(a.grade ?? '');
          final bi = _gradeOrder.indexOf(b.grade ?? '');
          cmp = (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
          break;
        case 'status':
          cmp = a.status.name.compareTo(b.status.name);
          break;
        default:
          cmp = a.seatKey.compareTo(b.seatKey);
      }
      return _editSortAsc ? cmp : -cmp;
    });

    final allFilteredSelected = filtered.isNotEmpty &&
        filtered.every((s) => _editSelectedSeatIds.contains(s.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Quick select bar ──
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminTheme.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AdminTheme.sage.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 14, color: AdminTheme.gold.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'QUICK SELECT',
                    style: AdminTheme.label(
                        fontSize: 9, color: AdminTheme.gold),
                  ),
                  const Spacer(),
                  if (_editSelectedSeatIds.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _editSelectedSeatIds.clear()),
                      child: Text(
                        'CLEAR',
                        style: AdminTheme.label(
                          fontSize: 9,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Select all
                  _quickSelectChip(
                    label: 'ALL ${seats.length}',
                    isActive: _editSelectedSeatIds.length == seats.length,
                    color: AdminTheme.gold,
                    onTap: () {
                      setState(() {
                        if (_editSelectedSeatIds.length == seats.length) {
                          _editSelectedSeatIds.clear();
                        } else {
                          _editSelectedSeatIds =
                              seats.map((s) => s.id).toSet();
                          _editGradeFilter = null;
                        }
                      });
                    },
                  ),
                  // Per grade select
                  ..._gradeOrder.map((g) {
                    final gradeSeats =
                        seats.where((s) => s.grade == g).toList();
                    if (gradeSeats.isEmpty) return const SizedBox.shrink();
                    final gradeIds = gradeSeats.map((s) => s.id).toSet();
                    final allGradeSelected =
                        gradeIds.every((id) => _editSelectedSeatIds.contains(id));
                    return _quickSelectChip(
                      label: '$g ${gradeSeats.length}',
                      isActive: allGradeSelected,
                      color: _gradeColors[g] ?? AdminTheme.sage,
                      onTap: () {
                        setState(() {
                          if (allGradeSelected) {
                            _editSelectedSeatIds.removeAll(gradeIds);
                          } else {
                            _editSelectedSeatIds.addAll(gradeIds);
                          }
                        });
                      },
                    );
                  }),
                  // Select available only
                  _quickSelectChip(
                    label: 'available',
                    icon: Icons.event_seat_outlined,
                    isActive: false,
                    color: AdminTheme.success,
                    onTap: () {
                      setState(() {
                        final availableIds = seats
                            .where((s) => s.status == SeatStatus.available)
                            .map((s) => s.id)
                            .toSet();
                        _editSelectedSeatIds = availableIds;
                      });
                    },
                  ),
                  // Select reserved only
                  _quickSelectChip(
                    label: 'reserved',
                    icon: Icons.lock_outline_rounded,
                    isActive: false,
                    color: AdminTheme.gold,
                    onTap: () {
                      setState(() {
                        final reservedIds = seats
                            .where((s) => s.status == SeatStatus.reserved)
                            .map((s) => s.id)
                            .toSet();
                        _editSelectedSeatIds = reservedIds;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Filter + sort row ──
        Row(
          children: [
            // Filter by grade
            Text(
              'FILTER',
              style: AdminTheme.label(
                  fontSize: 8, color: AdminTheme.textTertiary),
            ),
            const SizedBox(width: 8),
            _filterChip('ALL', _editGradeFilter == null, () {
              setState(() => _editGradeFilter = null);
            }),
            ..._gradeOrder.map((g) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _filterChip(g, _editGradeFilter == g, () {
                    setState(() {
                      _editGradeFilter = _editGradeFilter == g ? null : g;
                    });
                  }, color: _gradeColors[g]),
                )),
            const Spacer(),
            // Count
            Text(
              '${filtered.length}석',
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Table header ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: AdminTheme.gold.withValues(alpha: 0.04),
            border: Border(
              bottom: BorderSide(
                color: AdminTheme.sage.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Select all checkbox
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (allFilteredSelected) {
                      for (final s in filtered) {
                        _editSelectedSeatIds.remove(s.id);
                      }
                    } else {
                      for (final s in filtered) {
                        _editSelectedSeatIds.add(s.id);
                      }
                    }
                  });
                },
                child: Container(
                  width: 36,
                  height: 24,
                  alignment: Alignment.center,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: allFilteredSelected
                          ? AdminTheme.gold
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: allFilteredSelected
                            ? AdminTheme.gold
                            : AdminTheme.sage.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: allFilteredSelected
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: AdminTheme.onAccent)
                        : null,
                  ),
                ),
              ),
              _sortableHeader('SEAT', 'seatKey', flex: 5),
              _sortableHeader('GRADE', 'grade', flex: 2),
              _sortableHeader('STATUS', 'status', flex: 2),
              const SizedBox(width: 32),
            ],
          ),
        ),

        // ── Seat rows ──
        ...filtered.take(200).map((seat) => _buildSeatEditRow(seat)),
        if (filtered.length > 200)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '... 외 ${filtered.length - 200}개',
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ),
          ),

        const SizedBox(height: 16),

        // ── Delete all button ──
        Row(
          children: [
            const Spacer(),
            GestureDetector(
              onTap: () => _deleteAllSeats(seats.length),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AdminTheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: AdminTheme.error.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_forever_rounded,
                        size: 14, color: AdminTheme.error),
                    const SizedBox(width: 6),
                    Text(
                      'DELETE ALL ${seats.length} SEATS',
                      style: AdminTheme.label(
                        fontSize: 9,
                        color: AdminTheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickSelectChip({
    required String label,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.18)
              : AdminTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? color.withValues(alpha: 0.5)
                : AdminTheme.sage.withValues(alpha: 0.15),
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive) ...[
              Icon(Icons.check_rounded, size: 13, color: color),
              const SizedBox(width: 4),
            ] else if (icon != null) ...[
              Icon(icon, size: 12, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? color : AdminTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool isActive, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? AdminTheme.gold;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? c.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive
                ? c.withValues(alpha: 0.4)
                : AdminTheme.sage.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AdminTheme.label(
            fontSize: 9,
            color: isActive ? c : AdminTheme.sage,
          ),
        ),
      ),
    );
  }

  Widget _sortableHeader(String label, String sortKey, {int flex = 1}) {
    final isActive = _editSortBy == sortKey;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_editSortBy == sortKey) {
              _editSortAsc = !_editSortAsc;
            } else {
              _editSortBy = sortKey;
              _editSortAsc = true;
            }
          });
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AdminTheme.label(
                fontSize: 9,
                color: isActive ? AdminTheme.gold : AdminTheme.sage,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                _editSortAsc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 10,
                color: AdminTheme.gold,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeatEditRow(Seat seat) {
    final isSelected = _editSelectedSeatIds.contains(seat.id);
    final gradeColor = _gradeColors[seat.grade] ?? AdminTheme.sage;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _editSelectedSeatIds.remove(seat.id);
          } else {
            _editSelectedSeatIds.add(seat.id);
          }
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AdminTheme.gold.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: AdminTheme.sage.withValues(alpha: 0.08),
              width: 0.5,
            ),
            left: BorderSide(
              color: isSelected
                  ? AdminTheme.gold
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            Container(
              width: 36,
              height: 24,
              alignment: Alignment.center,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AdminTheme.gold
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isSelected
                        ? AdminTheme.gold
                        : AdminTheme.sage.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: AdminTheme.onAccent)
                    : null,
              ),
            ),
            // Seat name
            Expanded(
              flex: 5,
              child: Text(
                seat.displayName,
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AdminTheme.textPrimary
                      : AdminTheme.textSecondary,
                ),
              ),
            ),
            // Grade (editable via popup)
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () {}, // prevent row tap
                child: PopupMenuButton<String>(
                  tooltip: '등급 변경',
                  onSelected: (grade) => _changeSeatGrade(seat.id, grade),
                  color: AdminTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(
                      color: AdminTheme.sage.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  itemBuilder: (_) => _gradeOrder.map((g) {
                    return PopupMenuItem(
                      value: g,
                      height: 36,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _gradeColors[g],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            g,
                            style: AdminTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _gradeColors[g] ?? AdminTheme.textPrimary,
                            ),
                          ),
                          if (seat.grade == g) ...[
                            const Spacer(),
                            Icon(Icons.check_rounded,
                                size: 14, color: _gradeColors[g]),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: gradeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: gradeColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          seat.grade ?? 'N/A',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: gradeColor,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.unfold_more_rounded,
                            size: 12, color: gradeColor.withValues(alpha: 0.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Status
            Expanded(
              flex: 2,
              child: _seatStatusBadge(seat.status),
            ),
            // Delete single seat
            SizedBox(
              width: 32,
              child: GestureDetector(
                onTap: () => _deleteSingleSeat(seat),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AdminTheme.sage.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seatStatusBadge(SeatStatus status) {
    Color color;
    String label;
    switch (status) {
      case SeatStatus.available:
        color = AdminTheme.success;
        label = 'available';
        break;
      case SeatStatus.reserved:
        color = AdminTheme.gold;
        label = 'reserved';
        break;
      case SeatStatus.used:
        color = AdminTheme.info;
        label = 'used';
        break;
      case SeatStatus.blocked:
        color = AdminTheme.error;
        label = 'blocked';
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT ACTION BAR — fixed at bottom when seats selected
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEditActionBar() {
    final count = _editSelectedSeatIds.length;
    final hasSelection = count > 0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: const Border(
          top: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: hasSelection
          ? Row(
              children: [
                // Selection count
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AdminTheme.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AdminTheme.gold.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 14, color: AdminTheme.gold),
                      const SizedBox(width: 5),
                      Text(
                        '$count석 선택됨',
                        style: AdminTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.gold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _editSelectedSeatIds.clear()),
                  child: Text(
                    '해제',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                ),
                const Spacer(),
                // Grade change buttons
                ..._gradeOrder.map((g) {
                  final color = _gradeColors[g]!;
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: GestureDetector(
                      onTap: () => _bulkChangeGrade(g),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: color.withValues(alpha: 0.35),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                g,
                                style: AdminTheme.sans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                // Delete button
                GestureDetector(
                  onTap: _bulkDeleteSeats,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AdminTheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AdminTheme.error.withValues(alpha: 0.35),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 15, color: AdminTheme.error),
                          const SizedBox(width: 4),
                          Text(
                            'DELETE',
                            style: AdminTheme.label(
                                fontSize: 10, color: AdminTheme.error),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.edit_rounded,
                    size: 14, color: AdminTheme.gold.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Text(
                  '좌석을 선택하여 등급 변경 또는 삭제',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textTertiary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isEditMode = false;
                      _editSelectedSeatIds.clear();
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AdminTheme.gold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DONE',
                        style: AdminTheme.label(
                          fontSize: 10,
                          color: AdminTheme.onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEAT EDIT ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _changeSeatGrade(String seatId, String grade) async {
    try {
      await ref.read(seatRepositoryProvider).updateSeat(seatId, {'grade': grade});
      ref.invalidate(seatsStreamProvider(widget.eventId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등급 변경 실패: $e')),
        );
      }
    }
  }

  Future<void> _bulkChangeGrade(String grade) async {
    if (_editSelectedSeatIds.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(seatRepositoryProvider)
          .updateSeatsGrade(_editSelectedSeatIds.toList(), grade);
      ref.invalidate(seatsStreamProvider(widget.eventId));
      setState(() {
        _editSelectedSeatIds.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('일괄 등급 변경 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSingleSeat(Seat seat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Text(
          '좌석 삭제',
          style: AdminTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AdminTheme.textPrimary,
          ),
        ),
        content: Text(
          '${seat.displayName}을(를) 삭제하시겠습니까?',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(
                    fontSize: 13, color: AdminTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제',
                style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(seatRepositoryProvider).deleteSeat(seat.id);
      ref.invalidate(seatsStreamProvider(widget.eventId));
      _editSelectedSeatIds.remove(seat.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  Future<void> _bulkDeleteSeats() async {
    if (_editSelectedSeatIds.isEmpty) return;
    final count = _editSelectedSeatIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Text(
          '좌석 일괄 삭제',
          style: AdminTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AdminTheme.textPrimary,
          ),
        ),
        content: Text(
          '선택한 $count개 좌석을 삭제하시겠습니까?',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(
                    fontSize: 13, color: AdminTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('$count개 삭제',
                style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(seatRepositoryProvider)
          .deleteSeats(_editSelectedSeatIds.toList());
      ref.invalidate(seatsStreamProvider(widget.eventId));
      setState(() {
        _editSelectedSeatIds.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('일괄 삭제 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteAllSeats(int totalCount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Text(
          '전체 좌석 삭제',
          style: AdminTheme.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AdminTheme.textPrimary,
          ),
        ),
        content: Text(
          '등록된 $totalCount개 좌석을 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(
                    fontSize: 13, color: AdminTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('전체 삭제',
                style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(seatRepositoryProvider)
          .deleteAllSeats(widget.eventId);
      await ref.read(eventRepositoryProvider).updateEvent(widget.eventId, {
        'totalSeats': 0,
        'availableSeats': 0,
      });
      ref.invalidate(seatsStreamProvider(widget.eventId));
      setState(() {
        _isEditMode = false;
        _editSelectedSeatIds.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('전체 삭제 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _gradeChip(String grade, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            grade,
            style: AdminTheme.label(
              fontSize: 10,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: AdminTheme.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(int total, Map<SeatStatus, int> statusCounts) {
    final available = statusCounts[SeatStatus.available] ?? 0;
    final reserved = statusCounts[SeatStatus.reserved] ?? 0;
    final used = statusCounts[SeatStatus.used] ?? 0;
    final blocked = statusCounts[SeatStatus.blocked] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stacked progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: SizedBox(
            height: 4,
            child: Row(
              children: [
                if (available > 0)
                  Expanded(
                    flex: available,
                    child: Container(color: AdminTheme.success),
                  ),
                if (reserved > 0)
                  Expanded(
                    flex: reserved,
                    child: Container(color: AdminTheme.gold),
                  ),
                if (used > 0)
                  Expanded(
                    flex: used,
                    child: Container(color: AdminTheme.info),
                  ),
                if (blocked > 0)
                  Expanded(
                    flex: blocked,
                    child: Container(color: AdminTheme.error),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Legend row
        Row(
          children: [
            _statusLegend('available', available, AdminTheme.success),
            const SizedBox(width: 14),
            _statusLegend('reserved', reserved, AdminTheme.gold),
            const SizedBox(width: 14),
            _statusLegend('used', used, AdminTheme.info),
            const SizedBox(width: 14),
            _statusLegend('blocked', blocked, AdminTheme.error),
          ],
        ),
      ],
    );
  }

  Widget _statusLegend(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: AdminTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AdminTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 1: FORMAT GUIDE (Mini table visualization)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFormatGuide() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_chart_outlined,
                  size: 16, color: AdminTheme.sage.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Text(
                'CSV FORMAT',
                style: AdminTheme.label(
                  fontSize: 10,
                  color: AdminTheme.sage,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminTheme.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'MAX 1,500',
                  style: AdminTheme.label(
                    fontSize: 9,
                    color: AdminTheme.info,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // ── Mini table visualization ──
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.background,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: AdminTheme.sage.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                // Header row
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AdminTheme.gold.withValues(alpha: 0.06),
                    border: Border(
                      bottom: BorderSide(
                        color: AdminTheme.sage.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _formatCol('block', flex: 2, isHeader: true),
                      _formatCol('floor', flex: 2, isHeader: true),
                      _formatCol('row', flex: 2, isHeader: true),
                      _formatCol('number', flex: 2, isHeader: true),
                      _formatCol('grade', flex: 2, isHeader: true),
                    ],
                  ),
                ),
                // Data rows
                _formatDataRow(['A', '1층', '1', '1', 'VIP']),
                _formatDataRow(['A', '1층', '1', '2', 'R']),
                _formatDataRow(['B', '2층', '', '5', 'S'],
                    highlight: true),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Column descriptions ──
          _formatField(
            'block',
            '구역명 (A, B, C, VIP 등)',
            required: true,
          ),
          const SizedBox(height: 6),
          _formatField(
            'floor',
            '층 (1층, 2층 등)',
            required: true,
          ),
          const SizedBox(height: 6),
          _formatField(
            'row',
            '열 번호 (생략 가능)',
            required: false,
          ),
          const SizedBox(height: 6),
          _formatField(
            'number',
            '좌석 번호 (정수)',
            required: true,
          ),
          const SizedBox(height: 6),
          _formatField(
            'grade',
            '좌석 등급 (VIP, R, S, A)',
            required: false,
          ),

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),

          // Grade color legend
          Row(
            children: [
              Text(
                'GRADES',
                style: AdminTheme.label(
                  fontSize: 9,
                  color: AdminTheme.textTertiary,
                ),
              ),
              const SizedBox(width: 16),
              ..._gradeOrder.map((g) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _gradeColors[g],
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          g,
                          style: AdminTheme.sans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _gradeColors[g]!,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formatCol(String text, {int flex = 1, bool isHeader = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: isHeader
            ? AdminTheme.label(
                fontSize: 9,
                color: AdminTheme.gold.withValues(alpha: 0.8),
              )
            : AdminTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AdminTheme.textPrimary,
              ),
      ),
    );
  }

  Widget _formatDataRow(List<String> values, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: highlight
            ? AdminTheme.gold.withValues(alpha: 0.03)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: AdminTheme.sage.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _formatCol(values[0], flex: 2),
          _formatCol(values[1], flex: 2),
          Expanded(
            flex: 2,
            child: values[2].isEmpty
                ? Text(
                    '(생략)',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AdminTheme.textTertiary,
                    ),
                  )
                : Text(
                    values[2],
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
          ),
          _formatCol(values[3], flex: 2),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                if (_gradeColors.containsKey(values[4]))
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: _gradeColors[values[4]],
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                Text(
                  values[4],
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _gradeColors[values[4]] ?? AdminTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatField(String name, String desc, {required bool required}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 70,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AdminTheme.background,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            name,
            style: AdminTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            desc,
            style: AdminTheme.sans(
              fontSize: 12,
              color: AdminTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ),
        if (required)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AdminTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'REQUIRED',
              style: AdminTheme.label(
                fontSize: 8,
                color: AdminTheme.error.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 3: PREVIEW RESULT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreviewResult() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
        boxShadow: AdminShadows.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AdminTheme.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  '${_previewSeats.length} SEATS',
                  style: AdminTheme.label(
                    fontSize: 10,
                    color: AdminTheme.gold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'PREVIEW RESULT',
                style: AdminTheme.label(
                  fontSize: 9,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // ── Preview table ──
          if (_previewSeats.isNotEmpty) ...[
            // Table header
            Row(
              children: [
                _tableHeader('BLOCK', flex: 2),
                _tableHeader('FLOOR', flex: 2),
                _tableHeader('ROW', flex: 1),
                _tableHeader('NO.', flex: 1),
                _tableHeader('GRADE', flex: 1),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 0.5,
              color: AdminTheme.sage.withValues(alpha: 0.1),
            ),
            // Table rows (first 8)
            ..._previewSeats.take(8).map((seat) {
              final grade = seat['grade'] as String?;
              final gradeColor =
                  _gradeColors[grade] ?? AdminTheme.textTertiary;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AdminTheme.sage.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _tableCell('${seat['block']}', flex: 2),
                    _tableCell('${seat['floor']}', flex: 2),
                    _tableCell('${seat['row'] ?? '-'}', flex: 1),
                    _tableCell('${seat['number']}', flex: 1),
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          if (grade != null && grade.isNotEmpty) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: gradeColor,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            grade ?? '-',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: gradeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_previewSeats.length > 8) ...[
              const SizedBox(height: 12),
              Text(
                '... 외 ${_previewSeats.length - 8}개',
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREVIEW SUMMARY CARD (grade + zone breakdown)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreviewSummaryCard() {
    final grades = _gradeBreakdown(_previewSeats);
    final zones = _zoneBreakdown(_previewSeats);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.gold.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 16, color: AdminTheme.gold.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                'SUMMARY',
                style: AdminTheme.label(
                  fontSize: 10,
                  color: AdminTheme.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // Total
          Row(
            children: [
              Text(
                '총 좌석',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${_previewSeats.length}석',
                style: AdminTheme.sans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grade breakdown
          Text(
            'GRADE BREAKDOWN',
            style: AdminTheme.label(
              fontSize: 9,
              color: AdminTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          _buildGradeBarChart(grades),
          const SizedBox(height: 20),

          // Zone breakdown
          Text(
            'ZONE BREAKDOWN',
            style: AdminTheme.label(
              fontSize: 9,
              color: AdminTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: zones.entries.map((entry) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AdminTheme.background,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AdminTheme.sage.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${entry.key}구역',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AdminTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.value}석',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.gold,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeBarChart(Map<String, int> grades) {
    final total = grades.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    // Sort by grade order
    final sorted = <MapEntry<String, int>>[];
    for (final g in _gradeOrder) {
      if (grades.containsKey(g)) {
        sorted.add(MapEntry(g, grades[g]!));
      }
    }
    for (final entry in grades.entries) {
      if (!_gradeOrder.contains(entry.key)) {
        sorted.add(entry);
      }
    }

    return Column(
      children: sorted.map((entry) {
        final color = _gradeColors[entry.key] ?? AdminTheme.sage;
        final ratio = entry.value / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  entry.key,
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: AdminTheme.background,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: Text(
                  '${entry.value}석',
                  textAlign: TextAlign.right,
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPLOAD SUCCESS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildUploadSuccessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.success.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AdminTheme.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 18,
                  color: AdminTheme.success,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UPLOAD COMPLETE',
                    style: AdminTheme.label(
                      fontSize: 10,
                      color: AdminTheme.success,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_uploadedCount개 좌석이 성공적으로 등록되었습니다',
                    style: AdminTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.success.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // Grade breakdown
          if (_uploadedGradeBreakdown.isNotEmpty) ...[
            Text(
              'GRADE BREAKDOWN',
              style: AdminTheme.label(
                fontSize: 9,
                color: AdminTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: () {
                final sorted = <MapEntry<String, int>>[];
                for (final g in _gradeOrder) {
                  if (_uploadedGradeBreakdown.containsKey(g)) {
                    sorted.add(
                        MapEntry(g, _uploadedGradeBreakdown[g]!));
                  }
                }
                for (final entry in _uploadedGradeBreakdown.entries) {
                  if (!_gradeOrder.contains(entry.key)) {
                    sorted.add(entry);
                  }
                }
                return sorted.map((entry) {
                  final color =
                      _gradeColors[entry.key] ?? AdminTheme.sage;
                  return _gradeChip(entry.key, entry.value, color);
                }).toList();
              }(),
            ),
            const SizedBox(height: 16),
          ],

          // Zone breakdown
          if (_uploadedZoneBreakdown.isNotEmpty) ...[
            Text(
              'ZONE BREAKDOWN',
              style: AdminTheme.label(
                fontSize: 9,
                color: AdminTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _uploadedZoneBreakdown.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AdminTheme.background,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: AdminTheme.sage.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.key}구역',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AdminTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value}석',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.gold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _uploadSuccess = false;
                      _previewSeats = [];
                      _previewText = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminTheme.textSecondary,
                    side: BorderSide(
                      color: AdminTheme.sage.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    '추가 업로드',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go('/');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.gold,
                    foregroundColor: AdminTheme.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    '완료',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION HEADER -- Serif italic + thin line
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: AdminTheme.serif(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AdminTheme.label(
          fontSize: 9,
          color: AdminTheme.sage,
        ),
      ),
    );
  }

  Widget _tableCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AdminTheme.sans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AdminTheme.textPrimary,
        ),
      ),
    );
  }
}

// =============================================================================
// DOTMAP INTERACTIVE CANVAS — CustomPaint + GestureDetector
// =============================================================================

class _DotmapInteractiveCanvas extends StatelessWidget {
  final VenueSeatLayout layout;
  final Set<String> selectedKeys;
  final Size canvasSize;
  final void Function(String seatKey) onSeatTap;

  const _DotmapInteractiveCanvas({
    required this.layout,
    required this.selectedKeys,
    required this.canvasSize,
    required this.onSeatTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final tapped = _hitTestSeat(details.localPosition);
        if (tapped != null) {
          onSeatTap(tapped.key);
        }
      },
      child: CustomPaint(
        size: canvasSize,
        painter: _DotmapPainter(
          layout: layout,
          selectedKeys: selectedKeys,
        ),
      ),
    );
  }

  LayoutSeat? _hitTestSeat(Offset position) {
    if (layout.seats.isEmpty) return null;

    int minX = 999999, maxX = -999999;
    int minY = 999999, maxY = -999999;

    for (final seat in layout.seats) {
      if (seat.gridX < minX) minX = seat.gridX;
      if (seat.gridX > maxX) maxX = seat.gridX;
      if (seat.gridY < minY) minY = seat.gridY;
      if (seat.gridY > maxY) maxY = seat.gridY;
    }

    final rangeX = (maxX - minX).clamp(1, 999999);
    final rangeY = (maxY - minY).clamp(1, 999999);

    const padding = 24.0;
    final drawW = canvasSize.width - padding * 2;
    final drawH = canvasSize.height - padding * 2;

    final cellW = drawW / (rangeX + 1);
    final cellH = drawH / (rangeY + 1);
    final hitRadius = (cellW < cellH ? cellW : cellH) * 0.5;

    for (final seat in layout.seats) {
      final cx = padding + (seat.gridX - minX) * cellW + cellW / 2;
      final cy = padding + (seat.gridY - minY) * cellH + cellH / 2;

      if ((position - Offset(cx, cy)).distance <= hitRadius) {
        return seat;
      }
    }
    return null;
  }
}

// =============================================================================
// CUSTOM PAINTER — Dotmap for seat registration
// =============================================================================

class _DotmapPainter extends CustomPainter {
  final VenueSeatLayout layout;
  final Set<String> selectedKeys;

  _DotmapPainter({
    required this.layout,
    required this.selectedKeys,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.seats.isEmpty) return;

    int minX = 999999, maxX = -999999;
    int minY = 999999, maxY = -999999;

    for (final seat in layout.seats) {
      if (seat.gridX < minX) minX = seat.gridX;
      if (seat.gridX > maxX) maxX = seat.gridX;
      if (seat.gridY < minY) minY = seat.gridY;
      if (seat.gridY > maxY) maxY = seat.gridY;
    }

    final rangeX = (maxX - minX).clamp(1, 999999);
    final rangeY = (maxY - minY).clamp(1, 999999);

    const padding = 24.0;
    final drawW = size.width - padding * 2;
    final drawH = size.height - padding * 2;

    final cellW = drawW / (rangeX + 1);
    final cellH = drawH / (rangeY + 1);
    final dotRadius = ((cellW < cellH ? cellW : cellH) * 0.35).clamp(2.0, 8.0);

    for (final seat in layout.seats) {
      final cx = padding + (seat.gridX - minX) * cellW + cellW / 2;
      final cy = padding + (seat.gridY - minY) * cellH + cellH / 2;

      final isSelected = selectedKeys.contains(seat.key);
      final gradeColor = _gradeColorForPaint(seat.grade);

      if (isSelected) {
        // Draw filled dot with grade color
        final paint = Paint()
          ..color = gradeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(cx, cy), dotRadius, paint);

        // Draw selection ring
        final ringPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset(cx, cy), dotRadius + 2, ringPaint);
      } else {
        // Dimmed unselected dot
        final paint = Paint()
          ..color = gradeColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(cx, cy), dotRadius, paint);
      }
    }
  }

  Color _gradeColorForPaint(String grade) {
    switch (grade) {
      case 'VIP':
        return const Color(0xFFC9A84C);
      case 'R':
        return const Color(0xFFE53935);
      case 'S':
        return const Color(0xFF1E88E5);
      case 'A':
        return const Color(0xFF43A047);
      default:
        return const Color(0xFF888894);
    }
  }

  @override
  bool shouldRepaint(covariant _DotmapPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.selectedKeys != selectedKeys;
  }

  @override
  bool? hitTest(Offset position) => true;
}

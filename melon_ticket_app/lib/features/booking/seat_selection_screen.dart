import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/data/repositories/venue_view_repository.dart';
import 'package:melon_core/services/auth_service.dart';

// =============================================================================
// 좌석 선택 화면 (모바일 최적화 - AI추천 / 구역선택 / 빠른예매)
// =============================================================================

enum _SeatMode { ai, zone, quick }

class _SeatRecommendation {
  final List<Seat> seats;
  final double score;
  final int totalPrice;
  final String zone;
  final String row;
  final String seatRange;

  const _SeatRecommendation({
    required this.seats,
    required this.score,
    required this.totalPrice,
    required this.zone,
    required this.row,
    required this.seatRange,
  });
}

class SeatSelectionScreen extends ConsumerStatefulWidget {
  final String eventId;
  final bool openAIFirst;
  final int? initialAIQuantity;
  final int? initialAIMaxBudget;
  final String? initialAIInstrument;

  const SeatSelectionScreen({
    super.key,
    required this.eventId,
    this.openAIFirst = false,
    this.initialAIQuantity,
    this.initialAIMaxBudget,
    this.initialAIInstrument,
  });

  @override
  ConsumerState<SeatSelectionScreen> createState() =>
      _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends ConsumerState<SeatSelectionScreen> {
  // ── Mode ──
  _SeatMode _mode = _SeatMode.ai;

  // ── Shared ──
  final Set<String> _selectedSeatIds = {};
  String? _selectedFloor;

  // ── AI Mode ──
  int _aiQuantity = 2;
  String _aiGrade = '상관없음';
  String _aiPosition = '가운데';
  int _aiMaxBudget = 0; // 0이면 제한 없음
  String _aiInstrument = '상관없음';
  List<_SeatRecommendation>? _aiResults;
  String? _lastAISignature;
  bool _isAIRefreshQueued = false;

  // ── Zone Mode ──
  String? _selectedZone;

  // ── Quick Mode ──
  String _quickGrade = '자동';
  int _quickQuantity = 2;

  // ── Desktop ──
  final TransformationController _transformController =
      TransformationController();
  double _currentScale = 1.0;

  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFF30D158),
    'S': Color(0xFF0A84FF),
    'A': Color(0xFFFF9F0A),
    'B': Color(0xFF8E8E93),
  };

  Color _getGradeColor(String? grade) {
    if (grade == null) return AppTheme.textTertiary;
    return _gradeColors[grade.toUpperCase()] ?? AppTheme.textTertiary;
  }

  int _getGradePrice(String? grade, Event event) {
    if (grade == null) return event.price;
    if (event.priceByGrade != null && event.priceByGrade!.containsKey(grade)) {
      return event.priceByGrade![grade]!;
    }
    switch (grade.toUpperCase()) {
      case 'VIP':
        return (event.price * 1.5).round();
      case 'R':
        return event.price;
      case 'S':
        return (event.price * 0.8).round();
      case 'A':
        return (event.price * 0.6).round();
      case 'B':
        return (event.price * 0.5).round();
      default:
        return event.price;
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.openAIFirst) {
      _mode = _SeatMode.ai;
    }

    final qty = widget.initialAIQuantity;
    if (qty != null && qty > 0) {
      _aiQuantity = qty.clamp(1, 10);
    }

    final budget = widget.initialAIMaxBudget;
    if (budget != null && budget > 0) {
      _aiMaxBudget = budget;
    }

    final instrument = _normalizeInstrument(widget.initialAIInstrument);
    if (instrument != null) {
      _aiInstrument = instrument;
      _aiPosition = _suggestPositionForInstrument(instrument);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _switchMode(_SeatMode newMode) {
    setState(() {
      _mode = newMode;
      _selectedSeatIds.clear();
      _aiResults = null;
      _selectedZone = null;
    });
  }

  void _toggleSeat(Seat seat, Event event) {
    setState(() {
      if (_selectedSeatIds.contains(seat.id)) {
        _selectedSeatIds.remove(seat.id);
      } else {
        if (_selectedSeatIds.length < event.maxTicketsPerOrder) {
          _selectedSeatIds.add(seat.id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('최대 ${event.maxTicketsPerOrder}장까지 선택 가능합니다'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));
    final seatsAsync = ref.watch(seatsStreamProvider(widget.eventId));
    final authState = ref.watch(authStateProvider);
    final isLoggedIn = authState.valueOrNull != null;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: eventAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.gold)),
        error: (e, _) => Center(
            child: Text('오류: $e',
                style: GoogleFonts.notoSans(color: AppTheme.error))),
        data: (event) {
          if (event == null) {
            return Center(
                child: Text('공연을 찾을 수 없습니다',
                    style:
                        GoogleFonts.notoSans(color: AppTheme.textSecondary)));
          }

          // 공연장 시점 이미지 로드
          final venueViewsAsync = ref.watch(venueViewsProvider(event.venueId));
          final venueViews = venueViewsAsync.valueOrNull ?? {};
          final venueAsync = ref.watch(venueStreamProvider(event.venueId));
          final stagePosition =
              venueAsync.valueOrNull?.stagePosition.toLowerCase() ?? 'top';
          final isStageBottom = stagePosition == 'bottom';

          return seatsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.gold)),
            error: (e, _) => Center(
                child: Text('좌석 로딩 오류',
                    style: GoogleFonts.notoSans(color: AppTheme.error))),
            data: (seats) {
              final floors = seats.map((s) => s.floor).toSet().toList()..sort();
              if (_selectedFloor == null && floors.isNotEmpty) {
                _selectedFloor = floors.first;
              }

              if (isMobile) {
                return _buildMobileLayout(event, seats, floors, isLoggedIn,
                    venueViews, isStageBottom);
              }
              return _buildDesktopLayout(event, seats, floors, isLoggedIn);
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout(
      Event event,
      List<Seat> seats,
      List<String> floors,
      bool isLoggedIn,
      Map<String, VenueZoneView> venueViews,
      bool isStageBottom) {
    final selectedSeats =
        seats.where((s) => _selectedSeatIds.contains(s.id)).toList();
    final totalPrice = selectedSeats.fold<int>(
        0, (sum, s) => sum + _getGradePrice(s.grade, event));

    return Column(
      children: [
        _buildHeader(event),
        _buildModeSelector(),
        if (floors.length > 1 && _mode == _SeatMode.zone)
          _buildFloorTabs(floors),
        Expanded(
          child: _mode == _SeatMode.ai
              ? _buildAIMode(
                  seats, event, venueViews, isLoggedIn, isStageBottom)
              : _mode == _SeatMode.zone
                  ? _buildZoneMode(seats, event, venueViews)
                  : _buildQuickMode(seats, event, isStageBottom),
        ),
        _buildBottomBar(event, selectedSeats, totalPrice, isLoggedIn),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(Event event) {
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
            onPressed: () {
              if (_selectedZone != null) {
                setState(() => _selectedZone = null);
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 22),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '좌석을 선택해주세요 (최대 ${event.maxTicketsPerOrder}석)',
                  style: GoogleFonts.notoSans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE SELECTOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _modeTab(_SeatMode.ai, Icons.auto_awesome_rounded, 'AI 추천'),
          const SizedBox(width: 8),
          _modeTab(_SeatMode.zone, Icons.grid_view_rounded, '구역 선택'),
          const SizedBox(width: 8),
          _modeTab(_SeatMode.quick, Icons.bolt_rounded, '빠른 예매'),
        ],
      ),
    );
  }

  Widget _modeTab(_SeatMode mode, IconData icon, String label) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isActive ? AppTheme.goldGradient : null,
            color: isActive ? null : AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? null
                : Border.all(color: AppTheme.border, width: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: isActive
                      ? const Color(0xFFFDF3F6)
                      : AppTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? const Color(0xFFFDF3F6)
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI MODE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAIMode(
      List<Seat> seats,
      Event event,
      Map<String, VenueZoneView> venueViews,
      bool isLoggedIn,
      bool isStageBottom) {
    final signature =
        '${_aiQuantity}_${_aiGrade}_${_aiPosition}_${_aiMaxBudget}_${_aiInstrument}_'
        '${seats.where((s) => s.status == SeatStatus.available).length}';
    if ((_aiResults == null || _lastAISignature != signature) &&
        !_isAIRefreshQueued) {
      _lastAISignature = signature;
      _isAIRefreshQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _aiResults = _generateRecommendations(seats, event, isStageBottom);
          _isAIRefreshQueued = false;
        });
      });
    }

    final availableGrades = seats
        .where((s) => s.status == SeatStatus.available)
        .map((s) => s.grade)
        .where((g) => g != null)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    final fmt = NumberFormat('#,###');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.goldSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.gold.withOpacity(0.28)),
            ),
            child: Text(
              '추천 카드에서 좌석을 고르고, 시야를 확인한 뒤 바로 결제할 수 있습니다.',
              style: GoogleFonts.notoSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.gold,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildAIConditionSummary(event),
          const SizedBox(height: 16),

          // ── 인원 ──
          _sectionLabel('인원'),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              event.maxTicketsPerOrder,
              (i) {
                final n = i + 1;
                final isActive = _aiQuantity == n;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _aiQuantity = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: isActive ? AppTheme.goldGradient : null,
                        color: isActive ? null : AppTheme.card,
                        borderRadius: BorderRadius.circular(10),
                        border: isActive
                            ? null
                            : Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Center(
                        child: Text(
                          '$n',
                          style: GoogleFonts.notoSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? const Color(0xFFFDF3F6)
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // ── 등급 ──
          _sectionLabel('등급'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['상관없음', ...availableGrades].map((g) {
              final isActive = _aiGrade == g;
              final color =
                  g == '상관없음' ? AppTheme.textSecondary : _getGradeColor(g);
              return GestureDetector(
                onTap: () => setState(() => _aiGrade = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? color.withOpacity(0.2) : AppTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? color : AppTheme.border,
                      width: isActive ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (g != '상관없음') ...[
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        g == '상관없음' ? '상관없음' : '$g석',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      if (g != '상관없음') ...[
                        const SizedBox(width: 4),
                        Text(
                          '${fmt.format(_getGradePrice(g, event))}원',
                          style: GoogleFonts.notoSans(
                              fontSize: 11, color: AppTheme.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // ── 좌석 선호 ──
          _sectionLabel('좌석 선호'),
          const SizedBox(height: 8),
          Row(
            children: ['가운데', '앞쪽', '통로', '상관없음'].map((p) {
              final isActive = _aiPosition == p;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _aiPosition = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: isActive ? AppTheme.goldGradient : null,
                        color: isActive ? null : AppTheme.card,
                        borderRadius: BorderRadius.circular(8),
                        border: isActive
                            ? null
                            : Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Center(
                        child: Text(
                          p,
                          style: GoogleFonts.notoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? const Color(0xFFFDF3F6)
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),

          // ── AI 추천 버튼 ──
          SizedBox(
            width: double.infinity,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final results =
                        _generateRecommendations(seats, event, isStageBottom);
                    setState(() {
                      _aiResults = results;
                      _selectedSeatIds.clear();
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 18, color: Color(0xFFFDF3F6)),
                      const SizedBox(width: 8),
                      Text(
                        'AI 추천 받기',
                        style: GoogleFonts.notoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFDF3F6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 결과 ──
          if (_aiResults != null) ...[
            const SizedBox(height: 24),
            if (_aiResults!.isEmpty)
              _buildNoResults()
            else
              ..._aiResults!.asMap().entries.map((entry) =>
                  _buildRecommendationCard(
                      entry.key, entry.value, event, venueViews, isLoggedIn)),
          ],
        ],
      ),
    );
  }

  Widget _buildAIConditionSummary(Event event) {
    final fmt = NumberFormat('#,###');
    final budgetText =
        _aiMaxBudget > 0 ? '${fmt.format(_aiMaxBudget)}원 이하' : '제한 없음';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildConditionChip('인원', '$_aiQuantity명'),
          _buildConditionChip('예산', budgetText),
          _buildConditionChip('악기', _aiInstrument),
          _buildConditionChip('선호', _aiPosition),
        ],
      ),
    );
  }

  Widget _buildConditionChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.notoSans(fontSize: 11),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 40, color: AppTheme.textTertiary.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('조건에 맞는 연석 좌석이 없습니다',
              style: GoogleFonts.notoSans(
                  fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text('등급이나 인원을 변경해보세요',
              style: GoogleFonts.notoSans(
                  fontSize: 12, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(int index, _SeatRecommendation rec,
      Event event, Map<String, VenueZoneView> venueViews, bool isLoggedIn) {
    final isSelected = _selectedSeatIds.containsAll(rec.seats.map((s) => s.id));
    final fmt = NumberFormat('#,###');
    final stars = (rec.score / 25).clamp(1, 5).round();
    final labels = ['BEST', '추천', '추천'];
    final colors = [
      AppTheme.gold,
      AppTheme.success,
      const Color(0xFF0A84FF),
    ];
    final primarySeat = rec.seats.first;
    final previewView = _findBestView(venueViews, primarySeat);
    final seatColor = _getGradeColor(primarySeat.grade);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          _applyRecommendation(rec);
          if (previewView != null) {
            _showSeatView(
              previewView,
              rec.zone,
              primarySeat.grade,
              seatColor,
              primarySeat.row,
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.goldSubtle : AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppTheme.gold : AppTheme.border,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors[index.clamp(0, 2)].withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${index + 1}위 ${labels[index.clamp(0, 2)]}',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors[index.clamp(0, 2)],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: List.generate(
                        5,
                        (i) => Icon(
                              i < stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 14,
                              color: i < stars
                                  ? AppTheme.gold
                                  : AppTheme.textTertiary.withOpacity(0.3),
                            )),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _getGradeColor(rec.seats.first.grade),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rec.seats.first.grade ?? "일반"}석 · ${rec.zone}',
                          style: GoogleFonts.notoSans(
                              fontSize: 12, color: AppTheme.textTertiary),
                        ),
                        Text(
                          '${rec.row}열 ${rec.seatRange}번',
                          style: GoogleFonts.notoSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (_aiInstrument != '상관없음')
                          Text(
                            '악기 선호 반영: $_aiInstrument',
                            style: GoogleFonts.notoSans(
                              fontSize: 11,
                              color: AppTheme.goldLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${fmt.format(rec.totalPrice)}원',
                    style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
                ],
              ),
              if (previewView != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _showSeatView(
                    previewView,
                    rec.zone,
                    primarySeat.grade,
                    seatColor,
                    primarySeat.row,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.gold.withOpacity(0.35),
                        width: 0.7,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          previewView.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.surface,
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported_rounded,
                                size: 18,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  previewView.is360
                                      ? Icons.threesixty_rounded
                                      : Icons.visibility_rounded,
                                  size: 11,
                                  color: AppTheme.gold,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  previewView.is360 ? '360° 시야' : '시야 보기',
                                  style: GoogleFonts.notoSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: previewView == null
                          ? null
                          : () => _showSeatView(
                                previewView,
                                rec.zone,
                                primarySeat.grade,
                                seatColor,
                                primarySeat.row,
                              ),
                      child: Text(
                        previewView == null ? '시야 없음' : '시야 확인',
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _applyRecommendation(rec);
                        _goCheckoutWithSeats(
                          rec.seats.map((s) => s.id).toList(),
                          rec.seats.length,
                          isLoggedIn,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: const Color(0xFFFDF3F6),
                      ),
                      child: Text(
                        isLoggedIn ? '이 좌석 결제' : '로그인 후 결제',
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: AppTheme.gold),
                      const SizedBox(width: 6),
                      Text(
                        '선택됨',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI Recommendation Logic ──

  List<_SeatRecommendation> _generateRecommendations(
      List<Seat> allSeats, Event event, bool isStageBottom) {
    final available =
        allSeats.where((s) => s.status == SeatStatus.available).toList();
    final filtered = _aiGrade == '상관없음'
        ? available
        : available.where((s) => s.grade?.toUpperCase() == _aiGrade).toList();

    // Group by block + row
    final groups = <String, List<Seat>>{};
    for (final seat in filtered) {
      final key = '${seat.block}_${seat.floor}_${seat.row ?? "1"}';
      groups.putIfAbsent(key, () => []).add(seat);
    }

    final candidates = <_SeatRecommendation>[];

    for (final entry in groups.entries) {
      final seats = entry.value..sort((a, b) => a.number.compareTo(b.number));

      for (var i = 0; i <= seats.length - _aiQuantity; i++) {
        final seq = seats.sublist(i, i + _aiQuantity);

        // Check consecutive
        bool consecutive = true;
        for (var j = 1; j < seq.length; j++) {
          if (seq[j].number != seq[j - 1].number + 1) {
            consecutive = false;
            break;
          }
        }
        if (!consecutive) continue;

        final totalPrice =
            seq.fold<int>(0, (sum, s) => sum + _getGradePrice(s.grade, event));
        if (_aiMaxBudget > 0 && totalPrice > _aiMaxBudget) {
          continue;
        }
        final score = _scoreSequence(seq, seats, _aiPosition, isStageBottom) +
            _instrumentZoneBonus(seq.first.block, filtered, _aiInstrument);
        final firstNum = seq.first.number;
        final lastNum = seq.last.number;

        candidates.add(_SeatRecommendation(
          seats: seq,
          score: score,
          totalPrice: totalPrice,
          zone: seq.first.block,
          row: seq.first.row ?? '1',
          seatRange: firstNum == lastNum ? '$firstNum' : '$firstNum-$lastNum',
        ));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    // Return top 3 with zone variety
    final result = <_SeatRecommendation>[];
    final seenZones = <String>{};
    for (final c in candidates) {
      if (result.length >= 3) break;
      if (!seenZones.contains(c.zone) || result.length < 2) {
        result.add(c);
        seenZones.add(c.zone);
      }
    }
    if (result.length < 3) {
      for (final c in candidates) {
        if (result.length >= 3) break;
        if (!result.contains(c)) result.add(c);
      }
    }

    return result;
  }

  double _scoreSequence(List<Seat> sequence, List<Seat> allBlockSeats,
      String positionPref, bool isStageBottom) {
    final rowSeats =
        allBlockSeats.where((s) => s.row == sequence.first.row).toList();
    final numbers = rowSeats.map((s) => s.number).toList();
    final minNum = numbers.reduce(min);
    final maxNum = numbers.reduce(max);
    final center = (minNum + maxNum) / 2;
    final rowWidth = (maxNum - minNum).toDouble();
    final allRows = allBlockSeats
        .map((s) => int.tryParse(s.row ?? '1') ?? 1)
        .toSet()
        .toList()
      ..sort();

    double score = 0;

    for (final seat in sequence) {
      // Center score (0-40)
      if (rowWidth > 0) {
        final centerOffset = (seat.number - center).abs() / (rowWidth / 2);
        score += (1 - centerOffset) * 40;
      } else {
        score += 40;
      }

      // Row position (0-25)
      final rowNum = int.tryParse(seat.row ?? '1') ?? 1;
      if (allRows.length > 1) {
        final orderedRows = List<int>.from(allRows);
        if (isStageBottom) {
          orderedRows
            ..clear()
            ..addAll(allRows.reversed);
        }
        final rowIndex = orderedRows.indexOf(rowNum);
        final idealIdx =
            (orderedRows.length * 0.3).round().clamp(0, orderedRows.length - 1);
        final maxIndex = max(1, orderedRows.length - 1);
        final rowOffset = (rowIndex - idealIdx).abs() / maxIndex;
        score += (1 - rowOffset) * 25;
      } else {
        score += 25;
      }

      // Grade bonus (0-15)
      switch (seat.grade?.toUpperCase()) {
        case 'VIP':
          score += 15;
        case 'R':
          score += 12;
        case 'S':
          score += 8;
        case 'A':
          score += 4;
      }

      // Position preference (0-15)
      if (positionPref == '가운데' && rowWidth > 0) {
        final centerOffset = (seat.number - center).abs() / (rowWidth / 2);
        score += (1 - centerOffset) * 15;
      } else if (positionPref == '앞쪽' && allRows.length > 1) {
        final orderedRows = List<int>.from(allRows);
        if (isStageBottom) {
          orderedRows
            ..clear()
            ..addAll(allRows.reversed);
        }
        final rowIndex = orderedRows.indexOf(rowNum);
        final frontRatio = rowIndex / max(1, orderedRows.length - 1);
        score += (1 - frontRatio) * 15;
      } else if (positionPref == '통로') {
        if (seat.number <= minNum + 1 || seat.number >= maxNum - 1) {
          score += 15;
        }
      } else {
        score += 7;
      }
    }

    return score / sequence.length + 5;
  }

  double _instrumentZoneBonus(
    String zone,
    List<Seat> seats,
    String instrument,
  ) {
    if (instrument == '상관없음') return 0;

    final zones =
        seats.map((s) => s.block.trim().toUpperCase()).toSet().toList()..sort();
    if (zones.length <= 1) return 0;

    final currentIndex = zones.indexOf(zone.trim().toUpperCase());
    if (currentIndex < 0) return 0;

    final centerIndex = (zones.length - 1) / 2;
    final maxDistance = max(1.0, centerIndex);
    final distance = (currentIndex - centerIndex).abs();
    final centerAffinity = (1 - (distance / maxDistance)).clamp(0.0, 1.0);
    final sideAffinity = (distance / maxDistance).clamp(0.0, 1.0);

    switch (instrument) {
      case '현악':
      case '그랜드피아노':
        return centerAffinity * 18;
      case '하프':
        return sideAffinity * 16;
      case '밴드':
        return sideAffinity * 18;
      case '목관':
        return (centerAffinity * 0.7 + sideAffinity * 0.3) * 14;
      case '금관':
        return (centerAffinity * 0.4 + sideAffinity * 0.6) * 14;
      case '관악':
        return (centerAffinity * 0.6 + sideAffinity * 0.4) * 14;
      default:
        return centerAffinity * 10;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ZONE MODE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildZoneMode(
      List<Seat> seats, Event event, Map<String, VenueZoneView> venueViews) {
    final floorSeats = seats.where((s) => s.floor == _selectedFloor).toList();

    if (_selectedZone != null) {
      final zoneSeats =
          floorSeats.where((s) => s.block == _selectedZone).toList();
      return _buildZoneDetail(_selectedZone!, zoneSeats, event, venueViews);
    }

    return _buildZoneOverview(floorSeats, event, venueViews);
  }

  Widget _buildZoneOverview(List<Seat> floorSeats, Event event,
      Map<String, VenueZoneView> venueViews) {
    final zones = <String, List<Seat>>{};
    for (final seat in floorSeats) {
      zones.putIfAbsent(seat.block, () => []).add(seat);
    }
    final sortedZones = zones.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Stage
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            margin: const EdgeInsets.only(bottom: 20),
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
              style: GoogleFonts.notoSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFDF3F6),
                letterSpacing: 3,
              ),
            ),
          ),

          // Zone cards
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: sortedZones.length,
            itemBuilder: (context, index) {
              final zone = sortedZones[index];
              return _buildZoneCard(zone, zones[zone]!, event, venueViews);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildZoneCard(String zone, List<Seat> zoneSeats, Event event,
      Map<String, VenueZoneView> venueViews) {
    final available =
        zoneSeats.where((s) => s.status == SeatStatus.available).length;
    final total = zoneSeats.length;
    final grade = zoneSeats
        .firstWhere((s) => s.grade != null, orElse: () => zoneSeats.first)
        .grade;
    final color = _getGradeColor(grade);
    final price = _getGradePrice(grade, event);
    final fmt = NumberFormat('#,###');
    final ratio = total > 0 ? available / total : 0.0;
    final floor = _selectedFloor ?? '1층';
    // 구역 대표 시야 찾기 (buildKey 정규화 사용)
    final viewKey = VenueSeatView.buildKey(zone: zone, floor: floor);
    final zoneView = venueViews[viewKey] ??
        venueViews.values.cast<VenueSeatView?>().firstWhere(
              (v) =>
                  v != null &&
                  v.zone.trim().toUpperCase() == zone.trim().toUpperCase() &&
                  v.floor.trim() == floor.trim() &&
                  (v.row ?? '').trim().isEmpty &&
                  v.seat == null,
              orElse: () => null,
            );
    final hasView = zoneView != null;

    return GestureDetector(
      onTap: available > 0 ? () => setState(() => _selectedZone = zone) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: available > 0 ? AppTheme.card : AppTheme.card.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: available > 0 ? color.withOpacity(0.4) : AppTheme.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: available > 0 ? color : AppTheme.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zone,
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: available > 0
                          ? AppTheme.textPrimary
                          : AppTheme.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasView)
                  GestureDetector(
                    onTap: () =>
                        _showSeatView(zoneView, zone, grade, color),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.visibility_rounded,
                        size: 16,
                        color: AppTheme.gold,
                      ),
                    ),
                  ),
              ],
            ),

            // 시점 미리보기 썸네일
            if (hasView)
              GestureDetector(
                onTap: () =>
                    _showSeatView(zoneView, zone, grade, color),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.gold.withOpacity(0.3), width: 0.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        zoneView.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppTheme.surface,
                          child: const Icon(Icons.image_not_supported,
                              size: 16, color: AppTheme.textTertiary),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.visibility_rounded,
                                  size: 8, color: AppTheme.gold),
                              const SizedBox(width: 2),
                              Text('시야',
                                  style: GoogleFonts.notoSans(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.gold,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: AppTheme.border,
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '잔여 $available / $total석',
                  style: GoogleFonts.notoSans(
                      fontSize: 11, color: AppTheme.textTertiary),
                ),
                Text(
                  '${fmt.format(price)}원',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: available > 0 ? color : AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneDetail(String zone, List<Seat> zoneSeats, Event event,
      Map<String, VenueZoneView> venueViews) {
    final rowMap = <String, List<Seat>>{};
    for (final seat in zoneSeats) {
      final row = seat.row ?? '1';
      rowMap.putIfAbsent(row, () => []).add(seat);
    }
    final sortedRows = rowMap.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    final available =
        zoneSeats.where((s) => s.status == SeatStatus.available).length;
    final grade = zoneSeats
        .firstWhere((s) => s.grade != null, orElse: () => zoneSeats.first)
        .grade;
    final color = _getGradeColor(grade);
    final floor = _selectedFloor ?? '1층';
    final detailViewKey = VenueSeatView.buildKey(zone: zone, floor: floor);
    final zoneView = venueViews[detailViewKey] ??
        venueViews.values.cast<VenueSeatView?>().firstWhere(
              (v) =>
                  v != null &&
                  v.zone.trim().toUpperCase() == zone.trim().toUpperCase() &&
                  v.floor.trim() == floor.trim() &&
                  (v.row ?? '').trim().isEmpty &&
                  v.seat == null,
              orElse: () => null,
            );
    final hasView = zoneView != null;

    return Column(
      children: [
        // Zone header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border:
                Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedZone = null),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text('구역목록',
                          style: GoogleFonts.notoSans(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(zone,
                  style: GoogleFonts.notoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(width: 8),
              Text('잔여 $available석',
                  style: GoogleFonts.notoSans(
                      fontSize: 12, color: AppTheme.textTertiary)),
              const Spacer(),
              if (hasView)
                GestureDetector(
                  onTap: () =>
                      _showSeatView(zoneView, zone, grade, color),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        Text('시야 보기',
                            style: GoogleFonts.notoSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFDF3F6),
                            )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Stage indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            color: AppTheme.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: AppTheme.gold.withOpacity(0.3), width: 0.5),
          ),
          child: Text(
            '← STAGE →',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.gold,
              letterSpacing: 2,
            ),
          ),
        ),

        // Seat grid
        Expanded(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(50),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sortedRows.map((row) {
                    final seats = rowMap[row]!
                      ..sort((a, b) => a.number.compareTo(b.number));
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '$row열',
                              style: GoogleFonts.notoSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                          ...seats.map(
                              (s) => _buildLargeSeat(s, event, venueViews)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),

        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(color.withOpacity(0.15), color, '선택 가능'),
              const SizedBox(width: 16),
              _legendItem(AppTheme.gold, AppTheme.gold, '선택됨'),
              const SizedBox(width: 16),
              _legendItem(AppTheme.border, AppTheme.border, '선택 불가'),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEAT VIEW POPUP - 좌석 시점 보기 (360°)
  // ═══════════════════════════════════════════════════════════════════════════

  /// 좌석에서 가장 가까운 시점 이미지 찾기
  /// 우선순위:
  /// 1) 같은 구역+층+행+좌석
  /// 2) 같은 구역+층+행
  /// 3) 같은 구역+층+가까운 행
  /// 4) 같은 구역+층+좌석
  /// 5) 같은 구역+층 대표
  VenueSeatView? _findBestView(Map<String, VenueSeatView> views, Seat seat) {
    final floor = seat.floor.trim();
    final zone = seat.block.trim().toUpperCase();
    final row = (seat.row ?? '').trim();
    final seatNumber = seat.number;

    bool matchesZoneFloor(VenueSeatView view) {
      return view.zone.trim().toUpperCase() == zone &&
          view.floor.trim() == floor;
    }

    // 1. 같은 구역+층+행+좌석
    for (final view in views.values) {
      if (!matchesZoneFloor(view)) continue;
      if (view.seat != seatNumber) continue;
      final viewRow = (view.row ?? '').trim();
      if (viewRow == row) return view;
    }

    // 2. 같은 구역+층+행
    if (row.isNotEmpty) {
      for (final view in views.values) {
        if (!matchesZoneFloor(view)) continue;
        final viewRow = (view.row ?? '').trim();
        if (view.seat == null && viewRow == row) return view;
      }
    }

    // 3. 같은 구역+층+가까운 행
    if (row.isNotEmpty) {
      final rowNum = int.tryParse(row);
      if (rowNum != null) {
        VenueSeatView? closest;
        int minDist = 999;
        for (final view in views.values) {
          if (!matchesZoneFloor(view)) continue;
          if (view.seat != null || view.row == null) continue;
          final vRow = int.tryParse(view.row!.trim());
          if (vRow == null) continue;
          final dist = (vRow - rowNum).abs();
          if (dist < minDist) {
            minDist = dist;
            closest = view;
          }
        }
        if (closest != null) return closest;
      }
    }

    // 4. 같은 구역+층+좌석 (행 미기재 데이터 대응)
    for (final view in views.values) {
      if (!matchesZoneFloor(view)) continue;
      if (view.seat != seatNumber) continue;
      final viewRow = (view.row ?? '').trim();
      if (viewRow.isEmpty) return view;
    }

    // 5. 같은 구역+층 대표
    for (final view in views.values) {
      if (!matchesZoneFloor(view)) continue;
      final viewRow = (view.row ?? '').trim();
      if (viewRow.isEmpty && view.seat == null) return view;
    }

    return null;
  }

  void _showSeatView(
      VenueSeatView view, String zone, String? grade, Color color,
      [String? row]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SeatViewBottomSheet(
        view: view,
        zone: zone,
        grade: grade,
        color: color,
        row: row,
      ),
    );
  }

  void _showSeatViewForSeat(
      Seat seat, Map<String, VenueSeatView> venueViews, Event event) {
    final view = _findBestView(venueViews, seat);
    if (view == null) return;
    final color = _getGradeColor(seat.grade);
    _showSeatView(view, seat.block, seat.grade, color, seat.row);
  }

  Widget _legendItem(Color bg, Color border, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.notoSans(
                fontSize: 11, color: AppTheme.textTertiary)),
      ],
    );
  }

  Widget _buildLargeSeat(
      Seat seat, Event event, Map<String, VenueSeatView> venueViews) {
    final isAvailable = seat.status == SeatStatus.available;
    final isSelected = _selectedSeatIds.contains(seat.id);
    final color = _getGradeColor(seat.grade);
    final hasView = _findBestView(venueViews, seat) != null;

    Color bg;
    Color borderColor;

    if (isSelected) {
      bg = AppTheme.gold;
      borderColor = AppTheme.gold;
    } else if (!isAvailable) {
      bg = AppTheme.border;
      borderColor = AppTheme.border;
    } else {
      bg = color.withOpacity(0.15);
      borderColor = color.withOpacity(0.5);
    }

    return GestureDetector(
      onTap: isAvailable ? () => _toggleSeat(seat, event) : null,
      onLongPress:
          hasView ? () => _showSeatViewForSeat(seat, venueViews, event) : null,
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Stack(
          children: [
            Center(
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Color(0xFFFDF3F6))
                  : Text(
                      '${seat.number}',
                      style: GoogleFonts.notoSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: isAvailable
                            ? color
                            : AppTheme.textTertiary.withOpacity(0.3),
                      ),
                    ),
            ),
            // 360° view indicator dot
            if (hasView && isAvailable && !isSelected)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: bg, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUICK MODE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickMode(List<Seat> seats, Event event, bool isStageBottom) {
    final available =
        seats.where((s) => s.status == SeatStatus.available).toList();
    final availableGrades = available
        .map((s) => s.grade)
        .where((g) => g != null)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    final fmt = NumberFormat('#,###');

    final previewSeats =
        _autoAssignSeats(available, _quickQuantity, _quickGrade, isStageBottom);
    final previewPrice = previewSeats.fold<int>(
        0, (sum, s) => sum + _getGradePrice(s.grade, event));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      size: 28, color: AppTheme.gold),
                ),
                const SizedBox(height: 12),
                Text(
                  '빠른 예매',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '최적의 좌석을 자동으로 배정합니다',
                  style: GoogleFonts.notoSans(
                      fontSize: 13, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Grade
          _sectionLabel('등급'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['자동', ...availableGrades].map((g) {
              final isActive = _quickGrade == g;
              final color = g == '자동' ? AppTheme.gold : _getGradeColor(g);
              return GestureDetector(
                onTap: () => setState(() => _quickGrade = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? color.withOpacity(0.2) : AppTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? color : AppTheme.border,
                      width: isActive ? 1.5 : 0.5,
                    ),
                  ),
                  child: Text(
                    g == '자동' ? '자동 배정' : '$g석',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Quantity
          _sectionLabel('인원'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _quickQtyBtn(Icons.remove, () {
                if (_quickQuantity > 1) {
                  setState(() => _quickQuantity--);
                }
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '$_quickQuantity명',
                  style: GoogleFonts.notoSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              _quickQtyBtn(Icons.add, () {
                if (_quickQuantity < event.maxTicketsPerOrder) {
                  setState(() => _quickQuantity++);
                }
              }),
            ],
          ),
          const SizedBox(height: 24),

          // Preview
          if (previewSeats.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.goldSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.gold.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_seat_rounded,
                          size: 16, color: AppTheme.gold),
                      const SizedBox(width: 8),
                      Text(
                        '배정될 좌석',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...previewSeats.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getGradeColor(s.grade),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${s.grade ?? "일반"}석 ${s.block} ${s.row ?? ""}열 ${s.number}번',
                            style: GoogleFonts.notoSans(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${fmt.format(_getGradePrice(s.grade, event))}원',
                            style: GoogleFonts.notoSans(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 0.5, color: AppTheme.gold.withOpacity(0.2)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '합계',
                        style: GoogleFonts.notoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        '${fmt.format(previewPrice)}원',
                        style: GoogleFonts.notoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Quick book button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                gradient:
                    previewSeats.isNotEmpty ? AppTheme.goldGradient : null,
                color: previewSeats.isEmpty ? AppTheme.border : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: previewSeats.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _selectedSeatIds.clear();
                            for (final s in previewSeats) {
                              _selectedSeatIds.add(s.id);
                            }
                          });
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 18,
                          color: previewSeats.isEmpty
                              ? AppTheme.textTertiary
                              : const Color(0xFFFDF3F6)),
                      const SizedBox(width: 8),
                      Text(
                        previewSeats.isEmpty ? '선택 가능한 좌석이 없습니다' : '이 좌석으로 선택',
                        style: GoogleFonts.notoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: previewSeats.isEmpty
                              ? AppTheme.textTertiary
                              : const Color(0xFFFDF3F6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickQtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Icon(icon, size: 20, color: AppTheme.textSecondary),
      ),
    );
  }

  List<Seat> _autoAssignSeats(List<Seat> available, int quantity,
      String gradePreference, bool isStageBottom) {
    final filtered = gradePreference == '자동'
        ? available
        : available
            .where((s) => s.grade?.toUpperCase() == gradePreference)
            .toList();

    if (filtered.length < quantity) {
      return _findBestConsecutive(available, quantity, isStageBottom);
    }
    return _findBestConsecutive(filtered, quantity, isStageBottom);
  }

  List<Seat> _findBestConsecutive(
      List<Seat> seats, int quantity, bool isStageBottom) {
    final groups = <String, List<Seat>>{};
    for (final s in seats) {
      final key = '${s.block}_${s.floor}_${s.row ?? "1"}';
      groups.putIfAbsent(key, () => []).add(s);
    }

    double bestScore = -1;
    List<Seat>? bestSeats;

    for (final group in groups.values) {
      group.sort((a, b) => a.number.compareTo(b.number));

      for (var i = 0; i <= group.length - quantity; i++) {
        final seq = group.sublist(i, i + quantity);

        bool consecutive = true;
        for (var j = 1; j < seq.length; j++) {
          if (seq[j].number != seq[j - 1].number + 1) {
            consecutive = false;
            break;
          }
        }
        if (!consecutive) continue;

        final score = _scoreSequence(seq, group, '가운데', isStageBottom);
        if (score > bestScore) {
          bestScore = score;
          bestSeats = seq;
        }
      }
    }

    if (bestSeats != null) return bestSeats;
    if (quantity <= 1 && seats.isNotEmpty) return [seats.first];
    return [];
  }

  void _applyRecommendation(_SeatRecommendation rec) {
    setState(() {
      _selectedSeatIds.clear();
      for (final s in rec.seats) {
        _selectedSeatIds.add(s.id);
      }
    });
  }

  void _goCheckoutWithSeats(
      List<String> seatIds, int quantity, bool isLoggedIn) {
    if (!isLoggedIn) {
      context.push('/login');
      return;
    }
    context.push(
      '/checkout/${widget.eventId}',
      extra: {
        'seatIds': seatIds,
        'quantity': quantity,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomBar(
      Event event, List<Seat> selectedSeats, int totalPrice, bool isLoggedIn) {
    final fmt = NumberFormat('#,###');

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedSeats.isEmpty
                      ? '좌석을 선택하세요'
                      : '${selectedSeats.length}석 선택',
                  style: GoogleFonts.notoSans(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                if (selectedSeats.isNotEmpty)
                  Text(
                    '${fmt.format(totalPrice)}원',
                    style: GoogleFonts.notoSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient:
                    selectedSeats.isNotEmpty ? AppTheme.goldGradient : null,
                color: selectedSeats.isEmpty ? AppTheme.border : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: selectedSeats.isEmpty
                      ? null
                      : () => _goCheckoutWithSeats(
                            _selectedSeatIds.toList(),
                            selectedSeats.length,
                            isLoggedIn,
                          ),
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      selectedSeats.isEmpty ? '좌석을 선택하세요' : '선택 완료',
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selectedSeats.isEmpty
                            ? AppTheme.textTertiary
                            : const Color(0xFFFDF3F6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════���════════════════════════════════════════════════════════
  // FLOOR TABS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFloorTabs(List<String> floors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: floors.map((floor) {
          final isSelected = floor == _selectedFloor;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedFloor = floor;
                _selectedZone = null;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppTheme.goldGradient : null,
                  color: isSelected ? null : AppTheme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? null
                      : Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Text(
                  floor,
                  style: GoogleFonts.notoSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isSelected
                        ? const Color(0xFFFDF3F6)
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  String? _normalizeInstrument(String? raw) {
    final normalized = (raw ?? '').trim();
    if (normalized.isEmpty) return null;

    const allowed = {
      '상관없음',
      '현악',
      '목관',
      '금관',
      '관악',
      '하프',
      '그랜드피아노',
      '밴드',
    };
    if (allowed.contains(normalized)) {
      return normalized;
    }
    return '상관없음';
  }

  String _suggestPositionForInstrument(String instrument) {
    switch (instrument) {
      case '현악':
      case '그랜드피아노':
      case '목관':
      case '관악':
        return '가운데';
      case '하프':
      case '금관':
      case '밴드':
        return '통로';
      default:
        return '가운데';
    }
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.notoSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textTertiary,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT (기존 PC 레이아웃 유지)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout(
      Event event, List<Seat> seats, List<String> floors, bool isLoggedIn) {
    final priceFormat = NumberFormat('#,###');
    final floorSeats = seats.where((s) => s.floor == _selectedFloor).toList();
    final blocks = floorSeats.map((s) => s.block).toSet().toList()..sort();
    final grades =
        seats.map((s) => s.grade).where((g) => g != null).toSet().toList();

    final selectedSeats =
        seats.where((s) => _selectedSeatIds.contains(s.id)).toList();
    final totalPrice = selectedSeats.fold<int>(
        0, (sum, seat) => sum + _getGradePrice(seat.grade, event));

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildHeader(event),
              if (floors.length > 1) _buildFloorTabs(floors),
              Expanded(
                child: Stack(
                  children: [
                    InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.5,
                      maxScale: 3.0,
                      boundaryMargin: const EdgeInsets.all(100),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _buildDesktopStage(),
                              const SizedBox(height: 30),
                              _buildDesktopSeatLayout(
                                  blocks, floorSeats, event),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: _buildDesktopLegend(grades, event),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _buildZoomControls(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 280,
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border:
                Border(left: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: _buildDesktopPanel(
              event, selectedSeats, totalPrice, isLoggedIn, priceFormat),
        ),
      ],
    );
  }

  Widget _buildDesktopStage() {
    return Container(
      width: 400,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        gradient: AppTheme.goldGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(100),
          bottomRight: Radius.circular(100),
        ),
      ),
      child: Text(
        'STAGE',
        textAlign: TextAlign.center,
        style: GoogleFonts.notoSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFDF3F6),
          letterSpacing: 4,
        ),
      ),
    );
  }

  Widget _buildDesktopSeatLayout(
      List<String> blocks, List<Seat> floorSeats, Event event) {
    final blockSeatsMap = <String, List<Seat>>{};
    for (final seat in floorSeats) {
      blockSeatsMap.putIfAbsent(seat.block, () => []).add(seat);
    }

    final rows = <List<String>>[];
    for (var i = 0; i < blocks.length; i += 3) {
      rows.add(blocks.sublist(i, (i + 3).clamp(0, blocks.length)));
    }

    return Column(
      children: rows
          .map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: row
                      .map((block) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _buildDesktopBlock(
                                block, blockSeatsMap[block] ?? [], event),
                          ))
                      .toList(),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildDesktopBlock(String blockName, List<Seat> seats, Event event) {
    final rowSeatsMap = <String, List<Seat>>{};
    for (final seat in seats) {
      final rowKey = seat.row ?? '1';
      rowSeatsMap.putIfAbsent(rowKey, () => []).add(seat);
    }

    final sortedRows = rowSeatsMap.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.cardElevated,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            blockName,
            style: GoogleFonts.notoSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        ...sortedRows.map((row) {
          final rowSeats = rowSeatsMap[row]!
            ..sort((a, b) => a.number.compareTo(b.number));
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: rowSeats
                  .map((seat) => _buildDesktopSeat(seat, event))
                  .toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDesktopSeat(Seat seat, Event event) {
    final isAvailable = seat.status == SeatStatus.available;
    final isSelected = _selectedSeatIds.contains(seat.id);
    final gradeColor = _getGradeColor(seat.grade);

    Color backgroundColor;
    Color borderColor;

    if (isSelected) {
      backgroundColor = AppTheme.gold;
      borderColor = AppTheme.gold;
    } else if (!isAvailable) {
      backgroundColor = AppTheme.border;
      borderColor = AppTheme.border;
    } else {
      backgroundColor = gradeColor.withOpacity(0.2);
      borderColor = gradeColor;
    }

    return GestureDetector(
      onTap: isAvailable ? () => _toggleSeat(seat, event) : null,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 10, color: Color(0xFFFDF3F6))
            : null,
      ),
    );
  }

  Widget _buildDesktopLegend(List<String?> grades, Event event) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('등급별 가격',
              style: GoogleFonts.notoSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          ...grades.where((g) => g != null).map(
                (grade) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _getGradeColor(grade).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: _getGradeColor(grade), width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$grade석',
                          style: GoogleFonts.notoSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary)),
                      const SizedBox(width: 8),
                      Text(
                          '${NumberFormat('#,###').format(_getGradePrice(grade, event))}원',
                          style: GoogleFonts.notoSans(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text('선택불가',
                  style: GoogleFonts.notoSans(
                      fontSize: 12, color: AppTheme.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _currentScale = (_currentScale * 1.3).clamp(0.5, 3.0);
                _transformController.value = Matrix4.identity()
                  ..scale(_currentScale);
              });
            },
            icon: const Icon(Icons.add, size: 18, color: AppTheme.textPrimary),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Container(height: 0.5, width: 24, color: AppTheme.border),
          IconButton(
            onPressed: () {
              setState(() {
                _currentScale = (_currentScale / 1.3).clamp(0.5, 3.0);
                _transformController.value = Matrix4.identity()
                  ..scale(_currentScale);
              });
            },
            icon:
                const Icon(Icons.remove, size: 18, color: AppTheme.textPrimary),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Container(height: 0.5, width: 24, color: AppTheme.border),
          IconButton(
            onPressed: () {
              setState(() {
                _currentScale = 1.0;
                _transformController.value = Matrix4.identity();
              });
            },
            icon: const Icon(Icons.fullscreen_exit,
                size: 18, color: AppTheme.textPrimary),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopPanel(Event event, List<Seat> selectedSeats,
      int totalPrice, bool isLoggedIn, NumberFormat priceFormat) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border:
                Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('선택 좌석',
                  style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              if (selectedSeats.isNotEmpty)
                Text('${selectedSeats.length}석',
                    style: GoogleFonts.notoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.gold)),
            ],
          ),
        ),
        Expanded(
          child: selectedSeats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_seat_outlined,
                          size: 40, color: AppTheme.gold.withOpacity(0.2)),
                      const SizedBox(height: 12),
                      Text('좌석을 선택해주세요',
                          style: GoogleFonts.notoSans(
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: selectedSeats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final seat = selectedSeats[index];
                    final price = _getGradePrice(seat.grade, event);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _getGradeColor(seat.grade),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${seat.grade ?? '일반'}석',
                                    style: GoogleFonts.notoSans(
                                        fontSize: 11,
                                        color: AppTheme.textTertiary)),
                                Text(
                                  '${seat.block} ${seat.row ?? ''}열 ${seat.number}번',
                                  style: GoogleFonts.notoSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${priceFormat.format(price)}원',
                                  style: GoogleFonts.notoSans(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary)),
                              GestureDetector(
                                onTap: () => setState(
                                    () => _selectedSeatIds.remove(seat.id)),
                                child: Text('삭제',
                                    style: GoogleFonts.notoSans(
                                        fontSize: 12, color: AppTheme.error)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('총 결제금액',
                      style:
                          GoogleFonts.notoSans(color: AppTheme.textSecondary)),
                  Text('${priceFormat.format(totalPrice)}원',
                      style: GoogleFonts.notoSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold)),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient:
                      selectedSeats.isNotEmpty ? AppTheme.goldGradient : null,
                  color: selectedSeats.isEmpty ? AppTheme.border : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: selectedSeats.isEmpty
                        ? null
                        : () => _goCheckoutWithSeats(
                              _selectedSeatIds.toList(),
                              selectedSeats.length,
                              isLoggedIn,
                            ),
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Text(
                        selectedSeats.isEmpty ? '좌석을 선택하세요' : '선택 완료',
                        style: GoogleFonts.notoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selectedSeats.isEmpty
                              ? AppTheme.textTertiary
                              : const Color(0xFFFDF3F6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 좌석 시점 뷰 바텀시트
// =============================================================================

class _SeatViewBottomSheet extends StatefulWidget {
  final VenueSeatView view;
  final String zone;
  final String? grade;
  final Color color;
  final String? row;

  const _SeatViewBottomSheet({
    required this.view,
    required this.zone,
    required this.grade,
    required this.color,
    this.row,
  });

  @override
  State<_SeatViewBottomSheet> createState() => _SeatViewBottomSheetState();
}

class _SeatViewBottomSheetState extends State<_SeatViewBottomSheet> {
  final TransformationController _controller = TransformationController();
  bool _isFullScreen = false;
  bool _imageLoaded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreen();
    }
    return _buildBottomSheet();
  }

  String get _locationText {
    final parts = <String>[
      '${widget.zone} 구역',
      if (widget.row != null) '${widget.row}열',
    ];
    return parts.join(' ');
  }

  String get _subtitle {
    final rowInfo = widget.row != null ? '${widget.row}열 · ' : '';
    return '${widget.view.floor} · $rowInfo실제 좌석에서 바라본 무대';
  }

  Widget _buildBottomSheet() {
    final screenHeight = MediaQuery.of(context).size.height;
    final is360 = widget.view.is360;

    return Container(
      height: screenHeight * 0.78,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    is360 ? Icons.threesixty_rounded : Icons.visibility_rounded,
                    size: 18,
                    color: const Color(0xFFFDF3F6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _locationText,
                            style: GoogleFonts.notoSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.grade != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: widget.color.withOpacity(0.4),
                                    width: 0.5),
                              ),
                              child: Text(
                                widget.grade!,
                                style: GoogleFonts.notoSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: widget.color,
                                ),
                              ),
                            ),
                          if (is360) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '360°',
                                style: GoogleFonts.notoSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _isFullScreen = true),
                  icon: const Icon(Icons.fullscreen_rounded,
                      color: AppTheme.textSecondary),
                  tooltip: '전체화면',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

          // Divider
          Container(
            height: 0.5,
            color: AppTheme.border,
          ),

          // Image / 360° Viewer
          Expanded(
            child: is360 ? _build360Viewer() : _buildFlatViewer(),
          ),

          // Description
          if (widget.view.description != null &&
              widget.view.description!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border:
                    Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTheme.gold.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.view.description!,
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Safety padding
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  /// 360° 파노라마 뷰어
  Widget _build360Viewer() {
    return Stack(
      children: [
        ClipRRect(
          child: PanoramaViewer(
            sensorControl: SensorControl.orientation,
            animSpeed: 1.0,
            child: Image.network(
              widget.view.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  if (!_imageLoaded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imageLoaded = true);
                    });
                  }
                  return child;
                }
                return const SizedBox.shrink();
              },
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.background,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_not_supported_rounded,
                          size: 48, color: AppTheme.textTertiary),
                      const SizedBox(height: 12),
                      Text(
                        '360° 이미지를 불러올 수 없습니다',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Loading overlay
        if (!_imageLoaded)
          Container(
            color: AppTheme.background,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      color: AppTheme.gold,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '360° 파노라마 로딩 중...',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 360° drag hint
        if (_imageLoaded)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.threesixty_rounded,
                        size: 14, color: AppTheme.gold),
                    const SizedBox(width: 6),
                    Text(
                      '드래그하여 360° 둘러보기',
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 일반 사진 뷰어 (줌/패닝)
  Widget _buildFlatViewer() {
    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _controller,
          minScale: 0.5,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(40),
          child: Center(
            child: Image.network(
              widget.view.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  if (!_imageLoaded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imageLoaded = true);
                    });
                  }
                  return child;
                }
                final progress = loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: progress,
                          color: AppTheme.gold,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '시야 이미지 로딩 중...',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.image_not_supported_rounded,
                        size: 48, color: AppTheme.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      '이미지를 불러올 수 없습니다',
                      style: GoogleFonts.notoSans(
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Zoom hint
        if (_imageLoaded)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pinch_rounded,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '두 손가락으로 확대/축소',
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFullScreen() {
    final is360 = widget.view.is360;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen viewer
          if (is360)
            PanoramaViewer(
              sensorControl: SensorControl.orientation,
              animSpeed: 1.0,
              child: Image.network(
                widget.view.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black,
                  child: const Center(
                    child: Icon(Icons.image_not_supported_rounded,
                        size: 48, color: AppTheme.textTertiary),
                  ),
                ),
              ),
            )
          else
            InteractiveViewer(
              transformationController: _controller,
              minScale: 0.5,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(80),
              child: Center(
                child: Image.network(
                  widget.view.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.image_not_supported_rounded,
                        size: 48, color: AppTheme.textTertiary),
                  ),
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  16, MediaQuery.of(context).padding.top + 8, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: widget.color.withOpacity(0.5), width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: widget.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_locationText · ${widget.view.floor}',
                          style: GoogleFonts.notoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (is360) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.gold.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '360°',
                              style: GoogleFonts.notoSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _isFullScreen = false),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fullscreen_exit_rounded,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom description
          if (widget.view.description != null &&
              widget.view.description!.isNotEmpty)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                        is360
                            ? Icons.threesixty_rounded
                            : Icons.visibility_rounded,
                        size: 16,
                        color: AppTheme.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.view.description!,
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
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
}

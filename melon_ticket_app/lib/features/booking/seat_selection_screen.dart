import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/data/repositories/venue_view_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'widgets/seat_dot_map.dart';

// =============================================================================
// 좌석 선택 화면 (모바일 최적화 - AI추천 / 도트맵 / 구역선택 / 빠른예매)
// =============================================================================

enum _SeatMode { ai, dotMap, zone, quick }

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
  final String? initialAIPosition;

  const SeatSelectionScreen({
    super.key,
    required this.eventId,
    this.openAIFirst = false,
    this.initialAIQuantity,
    this.initialAIMaxBudget,
    this.initialAIInstrument,
    this.initialAIPosition,
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
  final String _aiGrade = '상관없음';
  String _aiPosition = '가운데';
  int _aiMaxBudget = 0; // 0이면 제한 없음
  String _aiInstrument = '상관없음';
  List<_SeatRecommendation>? _aiResults;
  String? _lastAISignature;
  bool _isAIRefreshQueued = false;
  final PageController _aiPageController = PageController(viewportFraction: 0.88);
  int _aiCurrentPage = 0;

  // ── Dot Map Mode ──
  bool _hasDotMap = false;
  VenueSeatLayout? _dotMapLayout;

  // ── Zone Mode ──
  String? _selectedZone;

  // ── Quick Mode ──
  String _quickGrade = '자동';
  int _quickQuantity = 2;

  // ── Standing Mode ──
  int _standingQuantity = 1;

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

    // 팝업에서 명시적으로 선택한 position이 있으면 악기 자동추천보다 우선
    final pos = widget.initialAIPosition;
    if (pos != null && pos.isNotEmpty) {
      _aiPosition = pos;
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    _aiPageController.dispose();
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

  void _toggleSeat(Seat seat, Event event,
      [Map<String, VenueSeatView>? venueViews, List<Seat>? allSeats]) {
    final maxTickets = event.maxTicketsPerOrder > 0
        ? event.maxTicketsPerOrder
        : 10; // 0이면 기본 10석 제한
    setState(() {
      if (_selectedSeatIds.contains(seat.id)) {
        _selectedSeatIds.remove(seat.id);
      } else {
        if (_selectedSeatIds.length < maxTickets) {
          _selectedSeatIds.add(seat.id);
          // 사진 있는 좌석 선택 시 자동으로 시야 팝업 + 예매 정보 전달
          if (venueViews != null) {
            final view = _findBestView(venueViews, seat);
            if (view != null) {
              Future.microtask(() {
                final color = _getGradeColor(seat.grade);
                // 선택된 좌석 정보 계산
                final selected = allSeats
                        ?.where((s) => _selectedSeatIds.contains(s.id))
                        .toList() ??
                    [];
                final totalPrice = selected.fold<int>(
                    0, (sum, s) => sum + _getGradePrice(s.grade, event));
                final seatNums =
                    selected.map((s) => '${s.number}').join(', ');
                _showSeatView(
                  view,
                  seat.block,
                  seat.grade,
                  color,
                  seat.row,
                  '${selected.length}석 · $seatNums번',
                  totalPrice,
                  _selectedSeatIds.toList(),
                  true, // isZoneMode
                );
              });
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('최대 ${maxTickets}장까지 선택 가능합니다'),
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: eventAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.gold)),
        error: (e, _) => Center(
            child: Text('오류: $e',
                style: AppTheme.nanum(color: AppTheme.error))),
        data: (event) {
          if (event == null) {
            return Center(
                child: Text('공연을 찾을 수 없습니다',
                    style:
                        AppTheme.nanum(color: AppTheme.textSecondary)));
          }

          // 공연장 시점 이미지 로드
          final venueViewsAsync = ref.watch(venueViewsProvider(event.venueId));
          final venueViews = venueViewsAsync.valueOrNull ?? {};
          final venueAsync = ref.watch(venueStreamProvider(event.venueId));
          final venue = venueAsync.valueOrNull;
          final stagePosition =
              venue?.stagePosition.toLowerCase() ?? 'top';
          final isStageBottom = stagePosition == 'bottom';

          // 도트맵 레이아웃 확인
          if (venue?.seatLayout != null &&
              venue!.seatLayout!.seats.isNotEmpty) {
            _hasDotMap = true;
            _dotMapLayout = venue.seatLayout;
          }

          // 스탠딩 모드: 좌석 대신 수량 선택 UI
          if (event.isStanding) {
            return _buildStandingMode(event, isLoggedIn);
          }

          return seatsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.gold)),
            error: (e, _) => Center(
                child: Text('좌석 로딩 오류',
                    style: AppTheme.nanum(color: AppTheme.error))),
            data: (seats) {
              if (seats.isEmpty) {
                return _buildNoSeatsState(event);
              }
              final floors = seats.map((s) => s.floor).toSet().toList()..sort();
              if (_selectedFloor == null && floors.isNotEmpty) {
                _selectedFloor = floors.first;
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 800) {
                    return _buildDesktopLayout(event, seats, floors,
                        isLoggedIn, venueViews, isStageBottom);
                  }
                  return _buildMobileLayout(event, seats, floors,
                      isLoggedIn, venueViews, isStageBottom);
                },
              );
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NO SEATS STATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNoSeatsState(Event event) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          event.title,
          style: AppTheme.nanum(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_seat_outlined,
                  size: 64, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                '좌석 준비 중',
                style: AppTheme.nanum(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '좌석 배치가 아직 등록되지 않았습니다.\n잠시 후 다시 시도해주세요.',
                textAlign: TextAlign.center,
                style: AppTheme.nanum(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDING MODE (비지정석)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStandingMode(Event event, bool isLoggedIn) {
    final fmt = NumberFormat('#,###');
    final maxPerOrder = event.maxTicketsPerOrder > 0 ? event.maxTicketsPerOrder : 4;
    final price = event.priceByGrade?['일반'] ?? event.price;
    final totalPrice = price * _standingQuantity;

    return Column(
      children: [
        // ── 앱바 ──
        SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary, size: 22),
                  onPressed: () {
                    if (context.canPop()) context.pop(); else context.go('/');
                  },
                ),
                Expanded(
                  child: Text(
                    event.title,
                    style: AppTheme.nanum(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 콘텐츠 ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 40),

                // 스탠딩 아이콘
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.gold.withValues(alpha: 0.15),
                        AppTheme.gold.withValues(alpha: 0.05),
                      ],
                    ),
                    border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.people_rounded, color: AppTheme.gold, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  '스탠딩 입장권',
                  style: AppTheme.nanum(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '비지정석 · 선착순 입장',
                  style: AppTheme.nanum(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // 잔여 수량
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '잔여 수량',
                        style: AppTheme.nanum(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${fmt.format(event.availableSeats)} / ${fmt.format(event.totalSeats)}',
                        style: AppTheme.nanum(
                          color: event.availableSeats > 0 ? AppTheme.gold : AppTheme.error,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 수량 선택
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '수량 선택',
                        style: AppTheme.nanum(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _standingQtyButton(
                            icon: Icons.remove_rounded,
                            enabled: _standingQuantity > 1,
                            onTap: () => setState(() => _standingQuantity--),
                          ),
                          Container(
                            width: 72,
                            alignment: Alignment.center,
                            child: Text(
                              '$_standingQuantity',
                              style: AppTheme.nanum(
                                color: AppTheme.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _standingQtyButton(
                            icon: Icons.add_rounded,
                            enabled: _standingQuantity < maxPerOrder,
                            onTap: () => setState(() => _standingQuantity++),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '최대 $maxPerOrder매',
                        style: AppTheme.nanum(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 가격 정보
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('입장권 가격',
                              style: AppTheme.nanum(color: AppTheme.textSecondary, fontSize: 14)),
                          Text('${fmt.format(price)}원',
                              style: AppTheme.nanum(color: AppTheme.textPrimary, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: AppTheme.border),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('총 결제금액',
                              style: AppTheme.nanum(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              )),
                          Text('${fmt.format(totalPrice)}원',
                              style: AppTheme.nanum(
                                color: AppTheme.gold,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),

        // ── 하단 예매 버튼 ──
        Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: event.availableSeats >= _standingQuantity
                  ? () => _goCheckoutWithSeats([], _standingQuantity, isLoggedIn)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.background,
                disabledBackgroundColor: AppTheme.textTertiary.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                event.availableSeats >= _standingQuantity
                    ? '${fmt.format(totalPrice)}원 · $_standingQuantity매 예매하기'
                    : '매진',
                style: AppTheme.nanum(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _standingQtyButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? AppTheme.gold.withValues(alpha: 0.15) : AppTheme.surface,
          border: Border.all(
            color: enabled ? AppTheme.gold.withValues(alpha: 0.4) : AppTheme.border,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? AppTheme.gold : AppTheme.textTertiary,
          size: 22,
        ),
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
              : _mode == _SeatMode.dotMap && _dotMapLayout != null
                  ? _buildDotMapMode(seats, event)
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
                  style: AppTheme.nanum(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    shadows: AppTheme.textShadow,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  event.maxTicketsPerOrder > 0
                      ? '좌석을 선택해주세요 (최대 ${event.maxTicketsPerOrder}석)'
                      : '좌석을 선택해주세요',
                  style: AppTheme.nanum(
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
          const SizedBox(width: 6),
          if (_hasDotMap)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _modeTab(
                  _SeatMode.dotMap, Icons.grid_on_rounded, '좌석 선택'),
            ),
          _modeTab(_SeatMode.zone, Icons.grid_view_rounded, '구역 선택'),
          const SizedBox(width: 6),
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
                style: AppTheme.nanum(
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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        setState(() {
          _aiResults = _generateRecommendations(
              seats, event, isStageBottom, venueViews);
          _isAIRefreshQueued = false;
          _aiCurrentPage = 0;
        });
      });
    }

    // Phase 1: 로딩
    if (_aiResults == null) {
      return _buildAILoadingState();
    }

    // Phase 2: 결과 없음
    if (_aiResults!.isEmpty) {
      return _buildAINoResults(seats, event, isStageBottom);
    }

    // Phase 3: 스와이프 카드
    return _buildAISwipeCards(event, venueViews, isLoggedIn, seats, isStageBottom);
  }

  // ── AI Loading State ──
  Widget _buildAILoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingIcon(
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: AppTheme.goldGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 32, color: Color(0xFFFDF3F6)),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '좌석 선별중~',
            style: AppTheme.nanum(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              shadows: AppTheme.textShadowStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '최적의 좌석을 찾고 있습니다',
            style: AppTheme.nanum(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── AI No Results ──
  Widget _buildAINoResults(List<Seat> seats, Event event, bool isStageBottom) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('조건에 맞는 연석 좌석이 없습니다',
              style: AppTheme.nanum(
                  fontSize: 15, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text('등급이나 인원을 변경해보세요',
              style: AppTheme.nanum(
                  fontSize: 12, color: AppTheme.textTertiary)),
          const SizedBox(height: 20),
          _buildRetryButton(seats, event, isStageBottom),
        ],
      ),
    );
  }

  // ── AI Swipe Cards Layout ──
  Widget _buildAISwipeCards(Event event, Map<String, VenueZoneView> venueViews,
      bool isLoggedIn, List<Seat> seats, bool isStageBottom) {
    return Column(
      children: [
        // 조건 요약 바
        _buildCompactConditionBar(event),
        // 카드 영역
        Expanded(
          child: Stack(
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: PageView.builder(
                  controller: _aiPageController,
                  itemCount: _aiResults!.length,
                  onPageChanged: (i) => setState(() => _aiCurrentPage = i),
                  itemBuilder: (context, index) {
                    return _buildSwipeCard(
                        index, _aiResults![index], event, venueViews, isLoggedIn);
                  },
                ),
              ),
              // 페이지 닷
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: _buildPageDots(),
              ),
            ],
          ),
        ),
        // 다시 추천받기
        _buildRetryButton(seats, event, isStageBottom),
      ],
    );
  }

  // ── 개별 스와이프 카드 ──
  Widget _buildSwipeCard(int index, _SeatRecommendation rec, Event event,
      Map<String, VenueZoneView> venueViews, bool isLoggedIn) {
    final primarySeat = rec.seats.first;
    final previewView = _findBestView(venueViews, primarySeat);
    final seatColor = _getGradeColor(primarySeat.grade);
    final fmt = NumberFormat('#,###');
    final labels = ['1위 BEST', '2위 추천', '3위 추천'];
    final labelColors = [
      AppTheme.gold,
      AppTheme.success,
      const Color(0xFF0A84FF),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 좌석 사진 (풀 배경) — 탭하면 전체화면 뷰어
            GestureDetector(
              onTap: previewView != null
                  ? () {
                      _applyRecommendation(rec);
                      _showSeatView(
                        previewView,
                        rec.zone,
                        primarySeat.grade,
                        seatColor,
                        primarySeat.row,
                        rec.seatRange,
                        rec.totalPrice,
                        rec.seats.map((s) => s.id).toList(),
                      );
                    }
                  : null,
              child: previewView != null
                  ? CachedNetworkImage(
                      imageUrl: previewView.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppTheme.surface,
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.gold, strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) =>
                          _buildNoPhotoPlaceholder(rec),
                    )
                  : _buildNoPhotoPlaceholder(rec),
            ),

            // 랭킹 배지 (top-left)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: labelColors[index.clamp(0, 2)].withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  labels[index.clamp(0, 2)],
                  style: AppTheme.nanum(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFDF3F6),
                  ),
                ),
              ),
            ),

            // 360° / 탭 힌트 (top-right)
            if (previewView != null)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        previewView.isPanorama360
                            ? Icons.threesixty_rounded
                            : previewView.isPanorama180
                                ? Icons.panorama_horizontal_rounded
                                : Icons.zoom_in_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        previewView.isPanorama360
                            ? '360° 터치'
                            : previewView.isPanorama180
                                ? '180° 터치'
                                : '터치하여 확대',
                        style: AppTheme.nanum(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 하단 그라데이션 + 좌석 정보 오버레이
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.92),
                    ],
                    stops: const [0.0, 0.3, 1.0],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 등급 배지 + 구역
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: seatColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: seatColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            '${primarySeat.grade ?? "일반"}석',
                            style: AppTheme.nanum(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: seatColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${rec.zone}구역',
                          style: AppTheme.nanum(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 열 + 좌석번호
                    Text(
                      rec.seats.length >= 3
                          ? '${rec.row}열 ${rec.seatRange}번 좌석'
                          : '${rec.row}열 ${rec.seatRange}번',
                      style: AppTheme.nanum(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: AppTheme.textShadowStrong,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 가격 — 밝은 배경으로 강조
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.gold.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '총 ${fmt.format(rec.totalPrice)}원',
                        style: AppTheme.nanum(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: AppTheme.textShadowStrong,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 버튼 — 세련된 글래스 스타일
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppTheme.goldGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              _applyRecommendation(rec);
                              _goCheckoutWithSeats(
                                rec.seats.map((s) => s.id).toList(),
                                rec.seats.length,
                                isLoggedIn,
                                seatLabels: rec.seats.map((s) => s.displayName).toList(),
                                seatGrades: rec.seats.map((s) => s.grade ?? '').toList(),
                              );
                            },
                            child: Text(
                              isLoggedIn ? '이 좌석 선택' : '로그인 후 선택',
                              textAlign: TextAlign.center,
                              style: AppTheme.nanum(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFDF3F6),
                                letterSpacing: 0.5,
                                shadows: AppTheme.textShadowOnDark,
                              ),
                            ),
                          ),
                        ),
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

  // ── 사진 없을 때 플레이스홀더 ──
  Widget _buildNoPhotoPlaceholder(_SeatRecommendation rec) {
    return Container(
      color: AppTheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_seat_rounded,
                size: 64,
                color: AppTheme.textTertiary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              '${rec.zone}구역 · ${rec.row}열',
              style: AppTheme.nanum(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '시야 이미지 준비중',
              style: AppTheme.nanum(
                  fontSize: 12, color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  // ── 페이지 닷 인디케이터 ──
  Widget _buildPageDots() {
    if (_aiResults == null || _aiResults!.length <= 1) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_aiResults!.length, (i) {
        final isActive = i == _aiCurrentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.gold
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── 조건 요약 바 ──
  Widget _buildCompactConditionBar(Event event) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: AppTheme.gold),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _conditionChip('인원', '$_aiQuantity명'),
                  const SizedBox(width: 6),
                  _conditionChip('선호', _aiPosition),
                  if (_aiInstrument != '상관없음') ...[
                    const SizedBox(width: 6),
                    _conditionChip('악기', _aiInstrument),
                  ],
                  if (_aiMaxBudget > 0) ...[
                    const SizedBox(width: 6),
                    _conditionChip(
                        '스타일', _getBudgetStyleLabel(event)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getBudgetStyleLabel(Event event) {
    if (_aiMaxBudget <= 0) return 'AI 추천';
    final base = event.price * _aiQuantity;
    if (base <= 0) return 'AI 추천';
    final ratio = _aiMaxBudget / base;
    if (ratio <= 1.1) return '가볍게';
    if (ratio <= 1.6) return '완벽한 공연';
    return '눈맞춤';
  }

  Widget _conditionChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTheme.nanum(fontSize: 10),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // ── 다시 추천받기 ──
  Widget _buildRetryButton(
      List<Seat> seats, Event event, bool isStageBottom) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _aiResults = null;
              _lastAISignature = null;
              _selectedSeatIds.clear();
            });
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(
            '다시 추천받기',
            style:
                AppTheme.nanum(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.gold,
            side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  // ── AI Recommendation Logic ──

  List<_SeatRecommendation> _generateRecommendations(
      List<Seat> allSeats, Event event, bool isStageBottom,
      Map<String, VenueSeatView> venueViews) {
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
            _instrumentZoneBonus(seq.first.block, filtered, _aiInstrument) +
            _budgetGradeBonus(seq, event);
        final firstNum = seq.first.number;
        final lastNum = seq.last.number;

        candidates.add(_SeatRecommendation(
          seats: seq,
          score: score,
          totalPrice: totalPrice,
          zone: seq.first.block,
          row: seq.first.row ?? '1',
          seatRange: seq.length == 1
              ? '$firstNum'
              : seq.length == 2
                  ? '$firstNum-$lastNum'
                  : seq.map((s) => '${s.number}').join(', '),
        ));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    // 시야 사진 있는 좌석 우선, 없으면 전체 fallback
    final withView = venueViews.isNotEmpty
        ? candidates
            .where((c) => _findBestView(venueViews, c.seats.first) != null)
            .toList()
        : <_SeatRecommendation>[];

    final pool = withView.isNotEmpty ? withView : candidates;

    // Return top 3 with zone variety
    final result = <_SeatRecommendation>[];
    final seenZones = <String>{};
    for (final c in pool) {
      if (result.length >= 3) break;
      if (!seenZones.contains(c.zone) || result.length < 2) {
        result.add(c);
        seenZones.add(c.zone);
      }
    }
    if (result.length < 3) {
      for (final c in pool) {
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

  /// 예산 티어에 따른 등급 보너스
  /// 프리미엄 → VIP 강하게 선호, 가성비 → 저렴한 좌석 선호
  double _budgetGradeBonus(List<Seat> seats, Event event) {
    if (_aiMaxBudget <= 0) return 0; // 예산 상관없음 → 추가 보너스 없음

    final base = event.price * _aiQuantity;
    if (base <= 0) return 0;
    final ratio = _aiMaxBudget / base;

    double bonus = 0;
    for (final seat in seats) {
      final grade = seat.grade?.toUpperCase() ?? '';
      if (ratio >= 1.8) {
        // 프리미엄: VIP석 강하게 선호
        switch (grade) {
          case 'VIP':
            bonus += 40;
          case 'R':
            bonus += 20;
          case 'S':
            bonus += 5;
          default:
            bonus += 0;
        }
      } else if (ratio >= 1.2) {
        // 표준: R석 위주
        switch (grade) {
          case 'VIP':
            bonus += 20;
          case 'R':
            bonus += 25;
          case 'S':
            bonus += 10;
          default:
            bonus += 0;
        }
      } else {
        // 가성비: 저렴한 좌석 선호
        switch (grade) {
          case 'VIP':
            bonus += 0;
          case 'R':
            bonus += 5;
          case 'S':
            bonus += 15;
          case 'A':
            bonus += 25;
          default:
            bonus += 15;
        }
      }
    }
    return bonus / seats.length;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOT MAP MODE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDotMapMode(List<Seat> seats, Event event) {
    return SeatDotMap(
      layout: _dotMapLayout!,
      seats: seats,
      selectedSeatIds: _selectedSeatIds,
      maxSelectable: event.maxTicketsPerOrder > 0
          ? event.maxTicketsPerOrder
          : 4,
      onSeatTap: (seat) {
        setState(() {
          if (_selectedSeatIds.contains(seat.id)) {
            _selectedSeatIds.remove(seat.id);
          } else {
            final max = event.maxTicketsPerOrder > 0
                ? event.maxTicketsPerOrder
                : 4;
            if (_selectedSeatIds.length < max) {
              _selectedSeatIds.add(seat.id);
            }
          }
        });
      },
    );
  }

  // ZONE MODE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildZoneMode(
      List<Seat> seats, Event event, Map<String, VenueZoneView> venueViews) {
    final floorSeats = seats.where((s) => s.floor == _selectedFloor).toList();

    // 구역별 그룹핑
    final zones = <String, List<Seat>>{};
    for (final seat in floorSeats) {
      zones.putIfAbsent(seat.block, () => []).add(seat);
    }
    // VIP → R → S → A 등급순 정렬
    const gradeOrder = ['VIP', 'R', 'S', 'A'];
    final sortedZones = zones.keys.toList()
      ..sort((a, b) {
        final gradeA = zones[a]!
            .firstWhere((s) => s.grade != null, orElse: () => zones[a]!.first)
            .grade
            ?.toUpperCase();
        final gradeB = zones[b]!
            .firstWhere((s) => s.grade != null, orElse: () => zones[b]!.first)
            .grade
            ?.toUpperCase();
        final idxA = gradeOrder.indexOf(gradeA ?? '');
        final idxB = gradeOrder.indexOf(gradeB ?? '');
        final orderA = idxA >= 0 ? idxA : gradeOrder.length;
        final orderB = idxB >= 0 ? idxB : gradeOrder.length;
        if (orderA != orderB) return orderA.compareTo(orderB);
        return a.compareTo(b);
      });
    final fmt = NumberFormat('#,###');

    return Column(
      children: [
        // 전체 좌석 배치도
        Expanded(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(50),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // Stage
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

                  // 구역별 좌석
                  ...sortedZones.map((zone) {
                    final zoneSeats = zones[zone]!;
                    final grade = zoneSeats
                        .firstWhere((s) => s.grade != null,
                            orElse: () => zoneSeats.first)
                        .grade;
                    final color = _getGradeColor(grade);
                    final price = _getGradePrice(grade, event);
                    final available = zoneSeats
                        .where((s) => s.status == SeatStatus.available)
                        .length;
                    final gradeLabel = grade?.toUpperCase() ?? '';

                    // 행별 그룹핑
                    final rowMap = <String, List<Seat>>{};
                    for (final s in zoneSeats) {
                      rowMap.putIfAbsent(s.row ?? '1', () => []).add(s);
                    }
                    final sortedRows = rowMap.keys.toList()
                      ..sort((a, b) => (int.tryParse(a) ?? 0)
                          .compareTo(int.tryParse(b) ?? 0));

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // 구역 헤더: 이름 + 등급 + 가격
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$zone구역',
                                style: AppTheme.nanum(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (gradeLabel.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${gradeLabel}석',
                                    style: AppTheme.nanum(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                '${fmt.format(price)}원',
                                style: AppTheme.nanum(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '잔여$available',
                                style: AppTheme.nanum(
                                  fontSize: 10,
                                  color: available > 0
                                      ? color
                                      : AppTheme.textTertiary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 행별 좌석
                          ...sortedRows.map((row) {
                            final seats = rowMap[row]!
                              ..sort(
                                  (a, b) => a.number.compareTo(b.number));
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '$row열',
                                      style: AppTheme.nanum(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textTertiary,
                                      ),
                                    ),
                                  ),
                                  ...seats.map((s) =>
                                      _buildLargeSeat(s, event, venueViews, floorSeats)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
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
              _legendItem(
                  AppTheme.textTertiary.withValues(alpha: 0.15),
                  AppTheme.textTertiary,
                  '선택 가능'),
              const SizedBox(width: 12),
              _legendItem(AppTheme.gold, AppTheme.gold, '선택됨'),
              const SizedBox(width: 12),
              _legendItem(AppTheme.border, AppTheme.border, '선택 불가'),
              const SizedBox(width: 12),
              _legendDot('사진있음'),
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

    // 1. 같은 구역+층+행+좌석 (정확 매칭)
    for (final view in views.values) {
      if (!matchesZoneFloor(view)) continue;
      if (view.seat != seatNumber) continue;
      final viewRow = (view.row ?? '').trim();
      if (viewRow == row) return view;
    }

    // 2. 같은 구역+층+행 → 가장 가까운 좌석번호
    if (row.isNotEmpty) {
      VenueSeatView? closestSeat;
      int minSeatDist = 999;
      for (final view in views.values) {
        if (!matchesZoneFloor(view)) continue;
        final viewRow = (view.row ?? '').trim();
        if (viewRow != row) continue;
        if (view.seat == null) return view; // 행 대표 시야
        final dist = (view.seat! - seatNumber).abs();
        if (dist < minSeatDist) {
          minSeatDist = dist;
          closestSeat = view;
        }
      }
      if (closestSeat != null) return closestSeat;
    }

    // 3. 같은 구역+층 → 가장 가까운 행 (행/좌석 단위 모두 포함)
    if (row.isNotEmpty) {
      final rowNum = int.tryParse(row);
      if (rowNum != null) {
        VenueSeatView? closest;
        int minDist = 999;
        for (final view in views.values) {
          if (!matchesZoneFloor(view)) continue;
          final vRowStr = (view.row ?? '').trim();
          if (vRowStr.isEmpty) continue;
          final vRow = int.tryParse(vRowStr);
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

    // 6. 같은 구역 (층 무관) — fallback
    for (final view in views.values) {
      if (view.zone.trim().toUpperCase() != zone) continue;
      return view;
    }

    return null;
  }

  void _showSeatView(
    VenueSeatView view,
    String zone,
    String? grade,
    Color color, [
    String? row,
    String? seatRange,
    int? totalPrice,
    List<String>? seatIds,
    bool isZoneMode = false,
  ]) {
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
        seatRange: seatRange,
        totalPrice: totalPrice,
        seatIds: seatIds,
        eventId: seatRange != null ? widget.eventId : null,
        isZoneMode: isZoneMode,
      ),
    );
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
            style: AppTheme.nanum(
                fontSize: 11, color: AppTheme.textTertiary)),
      ],
    );
  }

  Widget _legendDot(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: const Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.all(1),
              child: CircleAvatar(
                radius: 3,
                backgroundColor: AppTheme.gold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: AppTheme.nanum(
                fontSize: 11, color: AppTheme.textTertiary)),
      ],
    );
  }

  Widget _buildLargeSeat(
      Seat seat, Event event, Map<String, VenueSeatView> venueViews,
      [List<Seat>? allSeats]) {
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
      bg = color.withValues(alpha: 0.15);
      borderColor = color.withValues(alpha: 0.5);
    }

    return GestureDetector(
      onTap: isAvailable
          ? () => _toggleSeat(seat, event, venueViews, allSeats)
          : null,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 0.5),
        ),
        child: Stack(
          children: [
            Center(
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Color(0xFFFDF3F6))
                  : Text(
                      '${seat.number}',
                      style: AppTheme.nanum(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: isAvailable
                            ? color
                            : AppTheme.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
            ),
            // 360° view indicator dot
            if (hasView && isAvailable && !isSelected)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
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
                    color: AppTheme.gold.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      size: 28, color: AppTheme.gold),
                ),
                const SizedBox(height: 12),
                Text(
                  '빠른 예매',
                  style: AppTheme.nanum(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    shadows: AppTheme.textShadow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '최적의 좌석을 자동으로 배정합니다',
                  style: AppTheme.nanum(
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
                    color: isActive ? color.withValues(alpha: 0.2) : AppTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? color : AppTheme.border,
                      width: isActive ? 1.5 : 0.5,
                    ),
                  ),
                  child: Text(
                    g == '자동' ? '자동 배정' : '$g석',
                    style: AppTheme.nanum(
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
                  style: AppTheme.nanum(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    shadows: AppTheme.textShadowStrong,
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
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
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
                        style: AppTheme.nanum(
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
                            style: AppTheme.nanum(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${fmt.format(_getGradePrice(s.grade, event))}원',
                            style: AppTheme.nanum(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 0.5, color: AppTheme.gold.withValues(alpha: 0.2)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '합계',
                        style: AppTheme.nanum(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        '${fmt.format(previewPrice)}원',
                        style: AppTheme.nanum(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold,
                          shadows: AppTheme.textShadow,
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
                        style: AppTheme.nanum(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: previewSeats.isEmpty
                              ? AppTheme.textTertiary
                              : const Color(0xFFFDF3F6),
                          shadows: previewSeats.isEmpty
                              ? null
                              : AppTheme.textShadowOnDark,
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
      List<String> seatIds, int quantity, bool isLoggedIn,
      {List<String>? seatLabels, List<String>? seatGrades}) {
    if (!isLoggedIn) {
      context.push('/login');
      return;
    }
    context.push(
      '/checkout/${widget.eventId}',
      extra: {
        'seatIds': seatIds,
        'quantity': quantity,
        'seatLabels': seatLabels,
        'seatGrades': seatGrades,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT (width > 800)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout(
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
          child: Row(
            children: [
              // 좌측: 도트맵/모드 콘텐츠
              Expanded(
                child: _mode == _SeatMode.ai
                    ? _buildAIMode(
                        seats, event, venueViews, isLoggedIn, isStageBottom)
                    : _mode == _SeatMode.dotMap && _dotMapLayout != null
                        ? _buildDotMapMode(seats, event)
                        : _mode == _SeatMode.zone
                            ? _buildZoneMode(seats, event, venueViews)
                            : _buildQuickMode(seats, event, isStageBottom),
              ),
              // 우측: 선택좌석 패널
              _buildSelectedSeatsPanel(
                  event, seats, selectedSeats, totalPrice, isLoggedIn),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedSeatsPanel(Event event, List<Seat> allSeats,
      List<Seat> selectedSeats, int totalPrice, bool isLoggedIn) {
    final fmt = NumberFormat('#,###');

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  '선택 좌석',
                  style: AppTheme.nanum(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                if (selectedSeats.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${selectedSeats.length}',
                      style: AppTheme.nanum(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gold,
                      ),
                    ),
                  ),
                const Spacer(),
                if (selectedSeats.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        setState(() => _selectedSeatIds.clear()),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '전체삭제',
                      style: AppTheme.nanum(
                          fontSize: 12, color: AppTheme.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          // 좌석 목록
          Expanded(
            child: selectedSeats.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_seat_outlined,
                            color: AppTheme.textTertiary, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          '선택한 좌석이 없습니다',
                          style: AppTheme.nanum(
                              fontSize: 13, color: AppTheme.textTertiary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: selectedSeats.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, color: AppTheme.border, indent: 20, endIndent: 20),
                    itemBuilder: (context, index) {
                      final seat = selectedSeats[index];
                      final grade = seat.grade ?? 'A';
                      final gradeColor = _gradeColors[grade] ?? _gradeColors['A']!;
                      final price = _getGradePrice(seat.grade, event);

                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            // 등급 뱃지
                            Container(
                              width: 36,
                              height: 22,
                              decoration: BoxDecoration(
                                color: gradeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Text(
                                  grade,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: gradeColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // 좌석 위치
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    seat.displayName,
                                    style: AppTheme.nanum(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${fmt.format(price)}원',
                                    style: AppTheme.nanum(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 삭제 버튼
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(
                                  () => _selectedSeatIds.remove(seat.id)),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded,
                                    size: 16, color: AppTheme.textTertiary),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // 푸터: 합계 + 선택완료 버튼
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
            ),
            child: Column(
              children: [
                if (selectedSeats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '합계',
                          style: AppTheme.nanum(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${fmt.format(totalPrice)}원',
                          style: AppTheme.nanum(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gold,
                            shadows: AppTheme.textShadowStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: selectedSeats.isNotEmpty
                          ? AppTheme.goldGradient
                          : null,
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
                                  seatLabels: selectedSeats
                                      .map((s) => s.displayName)
                                      .toList(),
                                  seatGrades: selectedSeats
                                      .map((s) => s.grade ?? '')
                                      .toList(),
                                ),
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Text(
                            selectedSeats.isEmpty
                                ? '좌석을 선택하세요'
                                : '선택 완료',
                            style: AppTheme.nanum(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: selectedSeats.isEmpty
                                  ? AppTheme.textTertiary
                                  : const Color(0xFFFDF3F6),
                              shadows: selectedSeats.isEmpty
                                  ? null
                                  : AppTheme.textShadowOnDark,
                            ),
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
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOBILE SELECTED SEATS LIST SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSelectedSeatsSheet(
      Event event, List<Seat> selectedSeats, int totalPrice, bool isLoggedIn) {
    final fmt = NumberFormat('#,###');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // Re-read from parent state in case it changed
          final seats = selectedSeats;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    Text(
                      '선택 좌석 ${seats.length}',
                      style: AppTheme.nanum(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (seats.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedSeatIds.clear());
                          Navigator.of(ctx).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '전체삭제',
                          style: AppTheme.nanum(
                              fontSize: 12, color: AppTheme.textTertiary),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              // Seat list
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.35),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: seats.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppTheme.border, indent: 20, endIndent: 20),
                  itemBuilder: (_, i) {
                    final seat = seats[i];
                    final grade = seat.grade ?? 'A';
                    final gradeColor =
                        _gradeColors[grade] ?? _gradeColors['A']!;
                    final price = _getGradePrice(seat.grade, event);

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 22,
                            decoration: BoxDecoration(
                              color: gradeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Text(grade,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: gradeColor)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              seat.displayName,
                              style: AppTheme.nanum(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${fmt.format(price)}원',
                            style: AppTheme.nanum(
                                fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() => _selectedSeatIds.remove(seat.id));
                              Navigator.of(ctx).pop();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close_rounded,
                                  size: 16, color: AppTheme.textTertiary),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Total
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: AppTheme.border, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('합계',
                        style: AppTheme.nanum(
                            fontSize: 13, color: AppTheme.textSecondary)),
                    Text(
                      '${fmt.format(totalPrice)}원',
                      style: AppTheme.nanum(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gold,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
            ],
          );
        },
      ),
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
            child: GestureDetector(
              onTap: selectedSeats.isNotEmpty
                  ? () => _showSelectedSeatsSheet(
                      event, selectedSeats, totalPrice, isLoggedIn)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedSeats.isEmpty
                            ? '좌석을 선택하세요'
                            : '${selectedSeats.length}석 선택',
                        style: AppTheme.nanum(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      if (selectedSeats.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(Icons.expand_less_rounded,
                              size: 16, color: AppTheme.textTertiary),
                        ),
                    ],
                  ),
                  if (selectedSeats.isNotEmpty)
                    Text(
                      '${fmt.format(totalPrice)}원',
                      style: AppTheme.nanum(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gold,
                        shadows: AppTheme.textShadowStrong,
                      ),
                    ),
                ],
              ),
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
                            seatLabels: selectedSeats.map((s) => s.displayName).toList(),
                            seatGrades: selectedSeats.map((s) => s.grade ?? '').toList(),
                          ),
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      selectedSeats.isEmpty ? '좌석을 선택하세요' : '선택 완료',
                      style: AppTheme.nanum(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selectedSeats.isEmpty
                            ? AppTheme.textTertiary
                            : const Color(0xFFFDF3F6),
                        shadows: selectedSeats.isEmpty
                            ? null
                            : AppTheme.textShadowOnDark,
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
                  style: AppTheme.nanum(
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
      style: AppTheme.nanum(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textTertiary,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DESKTOP ZONE LAYOUT (기존 PC 레이아웃 — 구역/블록 기반)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopZoneLayout(
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

    // ── 가로 2분할 (상: 좌석배치, 하: 선택/결제) ──
    return Column(
      children: [
        _buildHeader(event),
        if (floors.length > 1) _buildFloorTabs(floors),
        // ── 상단: 좌석 배치도 ──
        Expanded(
          flex: 3,
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
                        _buildDesktopSeatLayout(blocks, floorSeats, event),
                      ],
                    ),
                  ),
                ),
              ),
              // 등급별 가격 범례
              Positioned(
                left: 16,
                bottom: 16,
                child: _buildDesktopLegend(grades, event),
              ),
              // 줌 컨트롤
              Positioned(
                right: 16,
                bottom: 16,
                child: _buildZoomControls(),
              ),
            ],
          ),
        ),
        // ── 하단: 선택 좌석 + 결제 ──
        Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: _buildDesktopBottomPanel(
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
        style: AppTheme.nanum(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFDF3F6),
          letterSpacing: 4,
          shadows: AppTheme.textShadow,
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
            style: AppTheme.nanum(
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
      backgroundColor = gradeColor.withValues(alpha: 0.2);
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
              style: AppTheme.nanum(
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
                          color: _getGradeColor(grade).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: _getGradeColor(grade), width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$grade석',
                          style: AppTheme.nanum(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary)),
                      const SizedBox(width: 8),
                      Text(
                          '${NumberFormat('#,###').format(_getGradePrice(grade, event))}원',
                          style: AppTheme.nanum(
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
                  style: AppTheme.nanum(
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
                _transformController.value = Matrix4.diagonal3Values(_currentScale, _currentScale, 1.0);
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
                _transformController.value = Matrix4.diagonal3Values(_currentScale, _currentScale, 1.0);
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

  Widget _buildDesktopBottomPanel(Event event, List<Seat> selectedSeats,
      int totalPrice, bool isLoggedIn, NumberFormat priceFormat) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          // ── 선택 좌석 목록 (가로 스크롤) ──
          Expanded(
            child: selectedSeats.isEmpty
                ? Row(
                    children: [
                      Icon(Icons.touch_app_rounded,
                          size: 18, color: AppTheme.gold.withValues(alpha: 0.4)),
                      const SizedBox(width: 8),
                      Text('좌석을 선택해주세요',
                          style: AppTheme.nanum(
                              fontSize: 13, color: AppTheme.textTertiary)),
                    ],
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: selectedSeats.map((seat) {
                        final price = _getGradePrice(seat.grade, event);
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getGradeColor(seat.grade)
                                  .withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _getGradeColor(seat.grade),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${seat.block} ${seat.row ?? ''}열 ${seat.number}번',
                                style: AppTheme.nanum(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${priceFormat.format(price)}원',
                                style: AppTheme.nanum(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => setState(
                                    () => _selectedSeatIds.remove(seat.id)),
                                child: Icon(Icons.close_rounded,
                                    size: 14,
                                    color:
                                        AppTheme.textTertiary.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          // ── 총액 + 결제 버튼 ──
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (selectedSeats.isNotEmpty)
                Text(
                  '${selectedSeats.length}석 · ${priceFormat.format(totalPrice)}원',
                  style: AppTheme.nanum(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gold,
                    shadows: AppTheme.textShadow,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            height: 44,
            decoration: BoxDecoration(
              gradient: selectedSeats.isNotEmpty ? AppTheme.goldGradient : null,
              color: selectedSeats.isEmpty ? AppTheme.border : null,
              borderRadius: BorderRadius.circular(10),
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
                          seatLabels: selectedSeats.map((s) => s.displayName).toList(),
                        ),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Text(
                      selectedSeats.isEmpty ? '좌석을 선택하세요' : '선택 완료 →',
                      style: AppTheme.nanum(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selectedSeats.isEmpty
                            ? AppTheme.textTertiary
                            : const Color(0xFFFDF3F6),
                        shadows: selectedSeats.isEmpty
                            ? null
                            : AppTheme.textShadowOnDark,
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
  final String? seatRange;
  final int? totalPrice;
  final List<String>? seatIds;
  final String? eventId;
  final bool isZoneMode;

  const _SeatViewBottomSheet({
    required this.view,
    required this.zone,
    required this.grade,
    required this.color,
    this.row,
    this.seatRange,
    this.totalPrice,
    this.seatIds,
    this.eventId,
    this.isZoneMode = false,
  });

  @override
  State<_SeatViewBottomSheet> createState() => _SeatViewBottomSheetState();
}

class _SeatViewBottomSheetState extends State<_SeatViewBottomSheet> {
  final TransformationController _controller = TransformationController();
  bool _isFullScreen = true;
  bool _imageLoaded = false;
  bool _showDragHint = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showDragHint = false);
    });
  }

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

  bool get _hasBookingInfo =>
      widget.seatRange != null &&
      widget.totalPrice != null &&
      widget.seatIds != null &&
      widget.eventId != null;

  Widget _buildBookingBar() {
    final fmt = NumberFormat('#,###');
    final gradeText = widget.grade != null ? ' · ${widget.grade}석' : '';
    final locationInfo =
        '${widget.zone}구역 ${widget.row ?? ''}열 ${widget.seatRange}$gradeText';

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              border: const Border(
                top: BorderSide(
                    color: Color(0x33C9A84C), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        locationInfo,
                        style: AppTheme.nanum(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmt.format(widget.totalPrice)}원',
                        style: AppTheme.nanum(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gold,
                          shadows: AppTheme.textShadow,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      if (!widget.isZoneMode &&
                          widget.eventId != null &&
                          context.mounted) {
                        context.push(
                          '/checkout/${widget.eventId}',
                          extra: {
                            'seatIds': widget.seatIds,
                            'quantity': widget.seatIds!.length,
                          },
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.goldGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.isZoneMode ? '확인' : '예매하기',
                        style: AppTheme.nanum(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFDF3F6),
                          shadows: AppTheme.textShadowOnDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    final screenHeight = MediaQuery.of(context).size.height;
    final viewType = widget.view.viewType;
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
                    viewType == 'panorama360'
                        ? Icons.threesixty_rounded
                        : viewType == 'panorama180'
                            ? Icons.panorama_horizontal_rounded
                            : Icons.visibility_rounded,
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
                            style: AppTheme.nanum(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              shadows: AppTheme.textShadow,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.grade != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: widget.color.withValues(alpha: 0.4),
                                    width: 0.5),
                              ),
                              child: Text(
                                widget.grade!,
                                style: AppTheme.nanum(
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
                                color: AppTheme.gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                viewType == 'panorama180' ? '180°' : '360°',
                                style: AppTheme.nanum(
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
                        style: AppTheme.nanum(
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

          // Image / 360° Viewer + booking overlay
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: viewType == 'panorama360'
                      ? _buildPanoramaViewer(false)
                      : viewType == 'panorama180'
                          ? _buildPanoramaViewer(true)
                          : _buildFlatViewer(),
                ),
                // 예매 바 (AI 추천에서 진입 시에만 표시)
                if (_hasBookingInfo) _buildBookingBar(),
              ],
            ),
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
                      size: 16, color: AppTheme.gold.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.view.description!,
                      style: AppTheme.nanum(
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

  /// 파노라마 뷰어 (360° / 180°)
  Widget _buildPanoramaViewer(bool is180) {
    final label = is180 ? '180°' : '360°';
    return Stack(
      children: [
        ClipRRect(
          child: PanoramaViewer(
            sensorControl: SensorControl.orientation,
            animSpeed: 1.0,
            minLongitude: is180 ? -90.0 : -180.0,
            maxLongitude: is180 ? 90.0 : 180.0,
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
                        '$label 이미지를 불러올 수 없습니다',
                        style: AppTheme.nanum(
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
                    '$label 파노라마 로딩 중...',
                    style: AppTheme.nanum(
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Panorama drag hint
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
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(is180
                            ? Icons.panorama_horizontal_rounded
                            : Icons.threesixty_rounded,
                        size: 14, color: AppTheme.gold),
                    const SizedBox(width: 6),
                    Text(
                      '드래그하여 $label 둘러보기',
                      style: AppTheme.nanum(
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
                        style: AppTheme.nanum(
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
                      style: AppTheme.nanum(
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
                  color: Colors.black.withValues(alpha: 0.5),
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
                      style: AppTheme.nanum(
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
    final viewType = widget.view.viewType;
    final is360 = widget.view.is360;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen viewer
          if (is360)
            Listener(
              onPointerDown: (_) {
                if (_showDragHint) setState(() => _showDragHint = false);
              },
              child: PanoramaViewer(
                sensorControl: SensorControl.orientation,
                animSpeed: 1.0,
                zoom: 2.0,
                minZoom: 2.0,
                maxZoom: 5.0,
                minLatitude: -40.0,
                maxLatitude: 40.0,
                minLongitude: viewType == 'panorama180' ? -90.0 : -180.0,
                maxLongitude: viewType == 'panorama180' ? 90.0 : 180.0,
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
              ),
            )
          else
            ClipRect(
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1.0,
                maxScale: 5.0,
                boundaryMargin: EdgeInsets.zero,
                panEnabled: true,
                scaleEnabled: true,
                onInteractionStart: (_) {
                  if (_showDragHint) setState(() => _showDragHint = false);
                },
                child: SizedBox.expand(
                  child: Image.network(
                    widget.view.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.image_not_supported_rounded,
                          size: 48, color: AppTheme.textTertiary),
                    ),
                  ),
                ),
              ),
            ),

          // 360° drag hint overlay
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showDragHint ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulsingIcon(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.gold.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(Icons.threesixty,
                            size: 36, color: AppTheme.gold),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                          Text(
                            '드래그하여 둘러보기',
                            style: AppTheme.nanum(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    Colors.black.withValues(alpha: 0.7),
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
                      color: widget.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: widget.color.withValues(alpha: 0.5), width: 0.5),
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
                          style: AppTheme.nanum(
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
                              color: AppTheme.gold.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              viewType == 'panorama180' ? '180°' : '360°',
                              style: AppTheme.nanum(
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
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom: grade info + confirm button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    border: const Border(
                      top: BorderSide(
                          color: Color(0x33C9A84C), width: 0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grade + location info
                      Row(
                        children: [
                          if (widget.grade != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: widget.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: widget.color.withValues(alpha: 0.5),
                                    width: 0.5),
                              ),
                              child: Text(
                                '${widget.grade}석',
                                style: AppTheme.nanum(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: widget.color,
                                ),
                              ),
                            ),
                          if (widget.grade != null) const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$_locationText · ${widget.view.floor}',
                              style: AppTheme.nanum(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          if (is360)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                viewType == 'panorama180' ? '180°' : '360°',
                                style: AppTheme.nanum(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (widget.view.description != null &&
                          widget.view.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14,
                                color: AppTheme.gold.withValues(alpha: 0.6)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.view.description!,
                                style: AppTheme.nanum(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Confirm button
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: AppTheme.goldGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '확인완료',
                                  style: AppTheme.nanum(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFFDF3F6),
                                    shadows: AppTheme.textShadowOnDark,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
}

// ── Pulsing animation widget ──
class _PulsingIcon extends StatefulWidget {
  final Widget child;
  const _PulsingIcon({required this.child});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

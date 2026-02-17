import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../app/theme.dart';
import '../../data/models/event.dart';
import '../../data/models/venue.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/seat_repository.dart';
import '../../data/repositories/venue_repository.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import 'widgets/seat_map_picker.dart';

// =============================================================================
// 공연 등록 화면 (간편 등록 → 즉시 승인 → 링크 공유)
// =============================================================================

class EventCreateScreen extends ConsumerStatefulWidget {
  const EventCreateScreen({super.key});

  @override
  ConsumerState<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends ConsumerState<EventCreateScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ──
  final _titleCtrl = TextEditingController();
  final _venueNameCtrl = TextEditingController();
  final _venueAddressCtrl = TextEditingController();
  final _runningTimeCtrl = TextEditingController(text: '120');
  final _maxTicketsCtrl = TextEditingController(text: '4');
  final _descriptionCtrl = TextEditingController();
  final _castCtrl = TextEditingController();
  final _organizerCtrl = TextEditingController();
  final _noticeCtrl = TextEditingController();

  // ── State ──
  String _category = '콘서트';
  String _ageLimit = '전체관람가';
  DateTime _startAt = DateTime.now().add(const Duration(days: 14));

  // ── 날짜/시간 직접 입력 컨트롤러 ──
  late final TextEditingController _yearCtrl;
  late final TextEditingController _monthCtrl;
  late final TextEditingController _dayCtrl;
  late final TextEditingController _hourCtrl;
  late final TextEditingController _minuteCtrl;

  // ── 공연장 선택 ──
  Venue? _selectedVenue;

  ParsedSeatData? _seatMapData;
  bool _isLoadingSeatMap = false;
  String? _seatMapError;

  // ── 등급 설정 ──
  static const _allGrades = ['VIP', 'R', 'S', 'A'];
  static const _gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFF30D158),
    'S': Color(0xFF0A84FF),
    'A': Color(0xFFFF9F0A),
  };
  final Set<String> _enabledGrades = {'VIP', 'R', 'S', 'A'};
  final Map<String, TextEditingController> _gradePriceControllers = {};

  Uint8List? _posterBytes;
  String? _posterFileName;

  bool _isSubmitting = false;

  static const _categories = [
    '콘서트',
    '뮤지컬',
    '연극',
    '클래식',
    '오페라',
    '스포츠',
    '전시/행사',
    '팬미팅',
    '기타',
  ];
  static const _ageLimits = [
    '전체관람가',
    '만 7세 이상',
    '만 12세 이상',
    '만 15세 이상',
    '만 19세 이상',
  ];

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController(text: _startAt.year.toString());
    _monthCtrl = TextEditingController(text: _startAt.month.toString());
    _dayCtrl = TextEditingController(text: _startAt.day.toString());
    _hourCtrl = TextEditingController(text: _startAt.hour.toString().padLeft(2, '0'));
    _minuteCtrl = TextEditingController(text: _startAt.minute.toString().padLeft(2, '0'));
    final priceFmt = NumberFormat('#,###');
    for (final grade in _allGrades) {
      _gradePriceControllers[grade] = TextEditingController(
        text: priceFmt.format(SeatMapParser.getDefaultPrice(grade)),
      );
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _venueNameCtrl.dispose();
    _venueAddressCtrl.dispose();
    _runningTimeCtrl.dispose();
    _maxTicketsCtrl.dispose();
    _descriptionCtrl.dispose();
    _castCtrl.dispose();
    _organizerCtrl.dispose();
    _noticeCtrl.dispose();
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    for (final c in _gradePriceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
      );
    }

    if (currentUser.value?.isAdmin != true) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          foregroundColor: AppTheme.textPrimary,
          title: Text(
            '공연 등록',
            style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 44,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  '관리자 권한이 필요합니다',
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '관리자 계정으로 로그인 후 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: const Color(0xFFFDF3F6),
                  ),
                  child: Text(
                    '홈으로 이동',
                    style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      MediaQuery.of(context).size.width >= 900 ? 40 : 16,
                  vertical: 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: _buildForm(),
                  ),
                ),
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Step 1: 기본 정보 ──
        _stepHeader('1', '기본 정보'),
        _card(
          child: Column(
            children: [
              _field('공연명',
                  child: TextFormField(
                    controller: _titleCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration('공연 제목을 입력하세요'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '공연명을 입력해주세요' : null,
                  )),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 460;
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(
                          child:
                              _field('카테고리', child: _buildCategoryDropdown()),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field('공연일시', child: _buildDateTimePicker()),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _field('카테고리', child: _buildCategoryDropdown()),
                      const SizedBox(height: 14),
                      _field('공연일시', child: _buildDateTimePicker()),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Step 2: 좌석 배치 (핵심 기능) ──
        _stepHeader('2', '좌석 배치', badge: '핵심'),
        _card(child: _buildSeatMapSection()),

        // ── Step 3: 가격 설정 (좌석 데이터 로드 후 자동 표시) ──
        if (_seatMapData != null) ...[
          const SizedBox(height: 28),
          _stepHeader('3', '등급별 가격'),
          _card(child: _buildGradeSelector()),
        ],

        const SizedBox(height: 28),

        // ── Step 4: 상세 정보 ──
        _stepHeader(_seatMapData != null ? '4' : '3', '상세 정보'),
        _card(child: _buildOptionalFields()),

        const SizedBox(height: 80),
      ],
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
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/admin');
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textPrimary, size: 20),
          ),
          Expanded(
            child: Text(
              '공연 등록',
              style: GoogleFonts.notoSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: _isSubmitting ? null : AppTheme.goldGradient,
                color: _isSubmitting ? AppTheme.border : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSubmitting ? null : _submitEvent,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.textPrimary,
                            ),
                          )
                        : Text(
                            '등록하기',
                            style: GoogleFonts.notoSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFDF3F6),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP HEADER & CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _stepHeader(String number, String title, {String? badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFDF3F6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
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
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: BASIC INFO WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _category,
      items: _categories
          .map((c) => DropdownMenuItem(
                value: c,
                child: Text(c, style: _inputStyle()),
              ))
          .toList(),
      onChanged: (v) => setState(() => _category = v!),
      decoration: _inputDecoration(null),
      dropdownColor: AppTheme.cardElevated,
    );
  }

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  void _syncDateTimeFromControllers() {
    final y = int.tryParse(_yearCtrl.text) ?? _startAt.year;
    final m = (int.tryParse(_monthCtrl.text) ?? _startAt.month).clamp(1, 12);
    final d = (int.tryParse(_dayCtrl.text) ?? _startAt.day).clamp(1, 31);
    final h = (int.tryParse(_hourCtrl.text) ?? _startAt.hour).clamp(0, 23);
    final min = (int.tryParse(_minuteCtrl.text) ?? _startAt.minute).clamp(0, 59);
    final dt = DateTime(y, m, d, h, min);
    if (dt != _startAt) {
      setState(() => _startAt = dt);
    }
  }

  void _syncControllersFromDateTime() {
    _yearCtrl.text = _startAt.year.toString();
    _monthCtrl.text = _startAt.month.toString();
    _dayCtrl.text = _startAt.day.toString();
    _hourCtrl.text = _startAt.hour.toString().padLeft(2, '0');
    _minuteCtrl.text = _startAt.minute.toString().padLeft(2, '0');
  }

  Widget _buildDateTimePicker() {
    final wd = _weekdays[_startAt.weekday - 1];
    final amPm = _startAt.hour < 12 ? '오전' : '오후';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 한글 요약 표시 + 달력 버튼 ──
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 15, color: AppTheme.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_startAt.year}년 ${_startAt.month}월 ${_startAt.day}일 ($wd) $amPm ${_startAt.hour}시 ${_startAt.minute.toString().padLeft(2, '0')}분',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gold,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _pickDateTime(
                    _startAt,
                    (dt) => setState(() {
                          _startAt = dt;
                          _syncControllersFromDateTime();
                        })),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_calendar_rounded,
                          size: 13, color: AppTheme.gold),
                      const SizedBox(width: 4),
                      Text('달력',
                          style: GoogleFonts.notoSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.gold,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 숫자 직접 입력 필드 ──
          Row(
            children: [
              _dateTimeField(_yearCtrl, 52, '년'),
              _dtLabel('년'),
              const SizedBox(width: 6),
              _dateTimeField(_monthCtrl, 32, '월'),
              _dtLabel('월'),
              const SizedBox(width: 6),
              _dateTimeField(_dayCtrl, 32, '일'),
              _dtLabel('일'),
              const SizedBox(width: 14),
              _dateTimeField(_hourCtrl, 32, '시'),
              _dtLabel('시'),
              const SizedBox(width: 4),
              Text(':', style: GoogleFonts.notoSans(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
              )),
              const SizedBox(width: 4),
              _dateTimeField(_minuteCtrl, 32, '분'),
              _dtLabel('분'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateTimeField(TextEditingController ctrl, double width, String label) {
    return SizedBox(
      width: width,
      height: 36,
      child: TextFormField(
        controller: ctrl,
        style: GoogleFonts.notoSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.gold, width: 1),
          ),
        ),
        onChanged: (_) => _syncDateTimeFromControllers(),
      ),
    );
  }

  Widget _dtLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: GoogleFonts.notoSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: SEAT MAP (핵심 기능)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSeatMapSection() {
    final venuesAsync = ref.watch(venuesStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '공연장을 선택하면 좌석 배치가 자동으로 설정됩니다.',
          style: GoogleFonts.notoSans(
            fontSize: 13,
            color: AppTheme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),

        // ── 공연장 DB에서 선택 ──
        venuesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.gold))),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (venues) {
            if (venues.isEmpty) {
              return _buildNoVenueCard();
            }
            return Column(
              children: [
                ...venues.map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildVenueSelectCard(v),
                    )),
              ],
            );
          },
        ),

        const SizedBox(height: 10),

        // ── 엑셀 업로드 (추가 옵션) ──
        _buildExcelUploadArea(),

        // ── 에러 ──
        if (_seatMapError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AppTheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_seatMapError!,
                        style: GoogleFonts.notoSans(
                            fontSize: 13, color: AppTheme.error)),
                  ),
                ],
              ),
            ),
          ),

        // ── 미리보기 ──
        if (_seatMapData != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _buildSeatMapPreview(),
          ),
      ],
    );
  }

  Widget _buildNoVenueCard() {
    return InkWell(
      onTap: () => context.push('/admin/venues'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.gold.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_location_alt_rounded,
                  size: 20, color: AppTheme.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('공연장을 먼저 등록하세요',
                      style: GoogleFonts.notoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.gold,
                      )),
                  Text('공연장 관리에서 좌석 배치가 포함된 공연장을 등록할 수 있습니다',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      )),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppTheme.gold),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueSelectCard(Venue venue) {
    final isSelected = _selectedVenue?.id == venue.id;
    final fmt = NumberFormat('#,###');

    return InkWell(
      onTap: () => _selectVenue(venue),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.goldSubtle : AppTheme.cardElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.gold : AppTheme.border,
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
                    ? AppTheme.gold.withOpacity(0.2)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.location_city_rounded,
                  size: 20,
                  color: isSelected ? AppTheme.gold : AppTheme.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(venue.name,
                          style: GoogleFonts.notoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          )),
                      if (venue.hasSeatView) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('시야',
                              style: GoogleFonts.notoSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.gold,
                              )),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층'
                    '${venue.address != null ? ' · ${venue.address}' : ''}',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.gold, size: 20),
          ],
        ),
      ),
    );
  }

  void _selectVenue(Venue venue) {
    // 공연장 선택 → 해당 공연장의 좌석 데이터로 프리셋 생성
    List<SeatGrade> grades;
    if (venue.name == '스카이아트홀') {
      grades = SkyArtHallPreset.grades;
    } else if (venue.name == '부산시민회관 대극장') {
      grades = BusanCivicHallPreset.grades;
    } else {
      // 기본 등급
      grades = [
        SeatGrade(name: 'VIP', price: 110000, colorHex: '#C9A84C'),
        SeatGrade(name: 'R', price: 88000, colorHex: '#30D158'),
        SeatGrade(name: 'S', price: 66000, colorHex: '#0A84FF'),
        SeatGrade(name: 'A', price: 44000, colorHex: '#FF9F0A'),
      ];
    }

    final data = SeatMapParser.createPresetData(venue, grades);

    setState(() {
      _selectedVenue = venue;
      _venueNameCtrl.text = venue.name;
      _venueAddressCtrl.text = venue.address ?? '';
    });

    _onSeatMapLoaded(data);
  }

  Widget _buildExcelUploadArea() {
    return InkWell(
      onTap: _isLoadingSeatMap ? null : _pickExcelFile,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppTheme.cardElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Column(
          children: [
            if (_isLoadingSeatMap)
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.gold))
            else
              Icon(Icons.cloud_upload_outlined,
                  size: 32, color: AppTheme.textTertiary.withOpacity(0.6)),
            const SizedBox(height: 10),
            Text(
              _isLoadingSeatMap ? '엑셀 분석 중...' : '엑셀 파일 업로드',
              style: GoogleFonts.notoSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '시트명=층, 행: 구역 | 열 수 | 좌석 수 | 등급',
              style: GoogleFonts.notoSans(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatMapPreview() {
    final data = _seatMapData!;
    final fmt = NumberFormat('#,###');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.venueName,
                  style: GoogleFonts.notoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: _clearSeatMap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('초기화',
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error,
                      )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '총 ${fmt.format(data.totalSeats)}석 · ${data.floors.length}층',
            style: GoogleFonts.notoSans(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: data.floors
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${f.name}: ${f.blocks.length}구역 (${fmt.format(f.totalSeats)}석)',
                        style: GoogleFonts.notoSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ))
                .toList(),
          ),
          if (data.grades.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: data.grades.map((g) {
                final color = _hexToColor(g.colorHex);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        )),
                    const SizedBox(width: 4),
                    Text(g.name,
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        )),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3: GRADE SELECTOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGradeSelector() {
    final fmt = NumberFormat('#,###');

    return Column(
      children: _allGrades.map((grade) {
        final isEnabled = _enabledGrades.contains(grade);
        final ctrl = _gradePriceControllers[grade]!;
        final color = _gradeColors[grade]!;

        var gradeSeats = 0;
        if (_seatMapData != null) {
          for (final floor in _seatMapData!.floors) {
            for (final block in floor.blocks) {
              if (block.grade == grade) gradeSeats += block.totalSeats;
            }
          }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isEnabled ? AppTheme.cardElevated : AppTheme.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isEnabled ? color.withOpacity(0.4) : AppTheme.border,
                width: isEnabled ? 1 : 0.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isEnabled,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _enabledGrades.add(grade);
                        } else {
                          _enabledGrades.remove(grade);
                        }
                      });
                    },
                    activeColor: color,
                    checkColor:
                        grade == 'VIP' ? const Color(0xFFFDF3F6) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    side: BorderSide(
                      color: isEnabled ? color : AppTheme.textTertiary,
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isEnabled ? color : color.withOpacity(0.3),
                    shape: BoxShape.circle,
                    boxShadow: isEnabled
                        ? [
                            BoxShadow(
                                color: color.withOpacity(0.3), blurRadius: 4)
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$grade석',
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isEnabled
                          ? AppTheme.textPrimary
                          : AppTheme.textTertiary,
                    ),
                  ),
                ),
                if (_seatMapData != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${fmt.format(gradeSeats)}석',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: isEnabled
                            ? AppTheme.textTertiary
                            : AppTheme.textTertiary.withOpacity(0.5),
                      ),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: ctrl,
                    enabled: isEnabled,
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isEnabled
                          ? AppTheme.textPrimary
                          : AppTheme.textTertiary,
                    ),
                    decoration: InputDecoration(
                      suffixText: '원',
                      suffixStyle: GoogleFonts.notoSans(
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                      filled: true,
                      fillColor: isEnabled ? AppTheme.surface : AppTheme.card,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppTheme.border, width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppTheme.border, width: 0.5),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: AppTheme.border.withOpacity(0.3),
                            width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppTheme.gold, width: 1),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandsSeparatorFormatter()],
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPTIONAL FIELDS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOptionalFields() {
    return Column(
      children: [
        // 포스터
        _field('포스터 이미지', child: _buildPosterPicker()),
        const SizedBox(height: 14),

        // 공연 소개
        _field('공연 소개',
            child: TextFormField(
              controller: _descriptionCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('공연 소개를 입력하세요 (선택)'),
              maxLines: 4,
            )),
        const SizedBox(height: 14),

        // 관람등급 + 공연시간
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 460;
            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    child: _field('관람등급',
                        child: DropdownButtonFormField<String>(
                          value: _ageLimit,
                          items: _ageLimits
                              .map((a) => DropdownMenuItem(
                                    value: a,
                                    child: Text(a, style: _inputStyle()),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _ageLimit = v!),
                          decoration: _inputDecoration(null),
                          dropdownColor: AppTheme.cardElevated,
                        )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field('공연시간 (분)',
                        child: TextFormField(
                          controller: _runningTimeCtrl,
                          style: _inputStyle(),
                          decoration: _inputDecoration('120'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                        )),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _field('관람등급',
                    child: DropdownButtonFormField<String>(
                      value: _ageLimit,
                      items: _ageLimits
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(a, style: _inputStyle()),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _ageLimit = v!),
                      decoration: _inputDecoration(null),
                      dropdownColor: AppTheme.cardElevated,
                    )),
                const SizedBox(height: 14),
                _field('공연시간 (분)',
                    child: TextFormField(
                      controller: _runningTimeCtrl,
                      style: _inputStyle(),
                      decoration: _inputDecoration('120'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    )),
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // 공연장명 + 주소
        _field('공연장명',
            child: TextFormField(
              controller: _venueNameCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('공연장 이름 (선택)'),
            )),
        const SizedBox(height: 14),
        _field('공연장 주소',
            child: TextFormField(
              controller: _venueAddressCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('주소 입력 (선택)'),
            )),
        const SizedBox(height: 14),

        // 출연진 + 주최
        _field('출연진',
            child: TextFormField(
              controller: _castCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('홍길동, 김철수 (선택)'),
            )),
        const SizedBox(height: 14),
        _field('주최/기획',
            child: TextFormField(
              controller: _organizerCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('(주)멜론엔터테인먼트 (선택)'),
            )),
        const SizedBox(height: 14),

        // 예매 유의사항
        _field('예매 유의사항',
            child: TextFormField(
              controller: _noticeCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('유의사항 입력 (선택)'),
              maxLines: 3,
            )),
        const SizedBox(height: 14),

        // 최대 구매 수량
        _field('1인 최대 구매 수량',
            child: TextFormField(
              controller: _maxTicketsCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('4'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            )),
      ],
    );
  }

  Widget _buildPosterPicker() {
    if (_posterBytes != null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.gold, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.memory(
                _posterBytes!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  _posterActionBtn(Icons.edit_rounded, '변경', _pickPosterImage),
                  const SizedBox(width: 6),
                  _posterActionBtn(Icons.close_rounded, '삭제', () {
                    setState(() {
                      _posterBytes = null;
                      _posterFileName = null;
                    });
                  }),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickPosterImage,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          color: AppTheme.cardElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 28, color: AppTheme.textTertiary.withOpacity(0.6)),
            const SizedBox(height: 6),
            Text(
              '포스터 이미지 선택 (JPG, PNG)',
              style: GoogleFonts.notoSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterActionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.notoSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _field(String label, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.notoSans(
        fontSize: 14,
        color: AppTheme.textTertiary,
      ),
      filled: true,
      fillColor: AppTheme.cardElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.gold, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
      ),
    );
  }

  TextStyle _inputStyle() {
    return GoogleFonts.notoSans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppTheme.textPrimary,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pickDateTime(
      DateTime current, ValueChanged<DateTime> onChanged) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.gold,
            onPrimary: Color(0xFFFDF3F6),
            surface: AppTheme.card,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.gold,
              onPrimary: Color(0xFFFDF3F6),
              surface: AppTheme.card,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        ),
      );
      if (time != null) {
        onChanged(DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ));
      }
    }
  }

  Future<void> _pickExcelFile() async {
    setState(() {
      _isLoadingSeatMap = true;
      _seatMapError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final fileName = result.files.single.name;
        final parsed = SeatMapParser.parseExcel(bytes, fileName);
        if (parsed != null) {
          _onSeatMapLoaded(parsed);
        } else {
          setState(() => _seatMapError = '좌석 데이터를 찾을 수 없습니다. 엑셀 형식을 확인해주세요.');
        }
      }
    } catch (e) {
      setState(() => _seatMapError = '파일 오류: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSeatMap = false);
    }
  }

  void _onSeatMapLoaded(ParsedSeatData data) {
    final dataGrades = data.grades.map((g) => g.name.toUpperCase()).toSet();

    setState(() {
      _seatMapData = data;
      _seatMapError = null;

      if (dataGrades.isNotEmpty) {
        _enabledGrades.clear();
        for (final g in dataGrades) {
          if (_allGrades.contains(g)) {
            _enabledGrades.add(g);
          }
        }
      }

      for (final grade in data.grades) {
        final key = grade.name.toUpperCase();
        if (_gradePriceControllers.containsKey(key)) {
          _gradePriceControllers[key]!.text = NumberFormat('#,###').format(grade.price);
        }
      }

      if (_venueNameCtrl.text.isEmpty) {
        _venueNameCtrl.text = data.venueName;
      }
    });
  }

  void _clearSeatMap() {
    setState(() {
      _seatMapData = null;
      _seatMapError = null;
      _enabledGrades.addAll(_allGrades);
    });
  }

  Future<void> _pickPosterImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        if (bytes.length > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('이미지 크기가 5MB를 초과합니다'),
                backgroundColor: AppTheme.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return;
        }
        setState(() {
          _posterBytes = bytes;
          _posterFileName = result.files.single.name;
        });
      }
    } catch (_) {
      // 취소됨
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBMIT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _submitEvent() async {
    if (!_formKey.currentState!.validate()) {
      _showError('공연명을 입력해주세요');
      return;
    }
    if (_seatMapData == null) {
      _showError('좌석 배치를 선택해주세요');
      return;
    }
    if (_enabledGrades.isEmpty) {
      _showError('사용할 좌석 등급을 1개 이상 선택해주세요');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 활성화된 등급만 좌석 수 계산
      var totalSeats = 0;
      for (final floor in _seatMapData!.floors) {
        for (final block in floor.blocks) {
          if (block.grade == null || _enabledGrades.contains(block.grade)) {
            totalSeats += block.totalSeats;
          }
        }
      }

      // 활성화된 등급별 가격 맵
      final priceByGrade = <String, int>{};
      for (final grade in _enabledGrades) {
        final ctrl = _gradePriceControllers[grade];
        if (ctrl != null) {
          priceByGrade[grade] =
              int.tryParse(ctrl.text.replaceAll(',', '')) ?? SeatMapParser.getDefaultPrice(grade);
        }
      }

      // 기본가격 = 최저 등급 가격
      final basePrice = priceByGrade.values.isNotEmpty
          ? priceByGrade.values.reduce((a, b) => a < b ? a : b)
          : 55000;

      // 판매 설정 자동 계산
      final now = DateTime.now();
      final saleStartAt = now;
      final saleEndAt = _startAt.subtract(const Duration(hours: 1));
      final revealAt = _startAt.subtract(const Duration(hours: 1));

      final event = Event(
        id: '',
        venueId: _selectedVenue?.id ?? '',
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        imageUrl: null,
        startAt: _startAt,
        revealAt: revealAt,
        saleStartAt: saleStartAt,
        saleEndAt: saleEndAt,
        price: basePrice,
        maxTicketsPerOrder: int.tryParse(_maxTicketsCtrl.text) ?? 4,
        totalSeats: totalSeats,
        availableSeats: totalSeats,
        status: EventStatus.active,
        createdAt: now,
        category: _category,
        venueName: _venueNameCtrl.text.trim().isEmpty
            ? _seatMapData?.venueName
            : _venueNameCtrl.text.trim(),
        venueAddress: _venueAddressCtrl.text.trim().isEmpty
            ? null
            : _venueAddressCtrl.text.trim(),
        runningTime: int.tryParse(_runningTimeCtrl.text) ?? 120,
        ageLimit: _ageLimit,
        cast: _castCtrl.text.trim().isEmpty ? null : _castCtrl.text.trim(),
        organizer: _organizerCtrl.text.trim().isEmpty
            ? null
            : _organizerCtrl.text.trim(),
        notice:
            _noticeCtrl.text.trim().isEmpty ? null : _noticeCtrl.text.trim(),
        priceByGrade: priceByGrade.isNotEmpty ? priceByGrade : null,
      );

      // 이벤트 생성
      final eventId =
          await ref.read(eventRepositoryProvider).createEvent(event);

      // 포스터 업로드
      if (_posterBytes != null && _posterFileName != null) {
        final imageUrl =
            await ref.read(storageServiceProvider).uploadPosterImage(
                  bytes: _posterBytes!,
                  eventId: eventId,
                  fileName: _posterFileName!,
                );
        await ref.read(eventRepositoryProvider).updateEvent(
          eventId,
          {'imageUrl': imageUrl},
        );
      }

      // 좌석 생성
      await _createSeatsFromSeatMap(eventId);

      if (mounted) {
        _showSuccessDialog(eventId, _titleCtrl.text.trim(), totalSeats);
      }
    } catch (e) {
      if (mounted) _showError('오류: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _createSeatsFromSeatMap(String eventId) async {
    if (_seatMapData == null) return;

    final seatData = <Map<String, dynamic>>[];

    for (final floor in _seatMapData!.floors) {
      for (final block in floor.blocks) {
        if (block.grade != null && !_enabledGrades.contains(block.grade)) {
          continue;
        }
        if (block.customRows.isNotEmpty) {
          for (final customRow in block.customRows) {
            final seatCount = customRow.seatCount;
            if (seatCount <= 0) continue;
            final rowLabel = customRow.name.trim().isEmpty
                ? '1'
                : customRow.name.trim();
            for (var number = 1; number <= seatCount; number++) {
              seatData.add({
                'block': block.name,
                'floor': floor.name,
                'row': rowLabel,
                'number': number,
                'grade': block.grade,
              });
            }
          }
          continue;
        }
        for (var row = 1; row <= block.rows; row++) {
          for (var number = 1; number <= block.seatsPerRow; number++) {
            seatData.add({
              'block': block.name,
              'floor': floor.name,
              'row': row.toString(),
              'number': number,
              'grade': block.grade,
            });
          }
        }
      }
    }

    await ref
        .read(seatRepositoryProvider)
        .createSeatsFromCsv(eventId, seatData);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUCCESS DIALOG
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSuccessDialog(String eventId, String title, int totalSeats) {
    final eventPath = '/event/$eventId';
    final fullUrl = kIsWeb ? '${Uri.base.origin}$eventPath' : eventPath;
    final fmt = NumberFormat('#,###');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 체크 아이콘 ──
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.goldGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.gold.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFFFDF3F6), size: 36),
                ),
                const SizedBox(height: 20),

                // ── 제목 ──
                Text(
                  '공연이 등록되었습니다!',
                  style: GoogleFonts.notoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: GoogleFonts.notoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '총 ${fmt.format(totalSeats)}석 · 즉시 판매 시작',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
                ),

                const SizedBox(height: 20),

                // ── 링크 복사 영역 ──
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded,
                          size: 16, color: AppTheme.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fullUrl,
                          style: GoogleFonts.notoSans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: fullUrl));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: const Text('링크가 복사되었습니다'),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '복사',
                            style: GoogleFonts.notoSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── 공연 상세 보기 버튼 ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppTheme.goldGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          context.go(eventPath);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Text(
                            '공연 상세 보기',
                            style: GoogleFonts.notoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFDF3F6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── 대시보드 이동 버튼 ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.go('/admin');
                    },
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: AppTheme.border, width: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      '대시보드로 이동',
                      style: GoogleFonts.notoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

/// 천 단위 콤마 자동 포맷터 (110000 → 110,000)
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  static final _fmt = NumberFormat('#,###');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(',', '');
    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }
    final number = int.tryParse(digitsOnly);
    if (number == null) return oldValue;

    final formatted = _fmt.format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

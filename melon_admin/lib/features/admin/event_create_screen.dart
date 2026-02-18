import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/services/kakao_postcode_service.dart'
    if (dart.library.io) 'package:melon_core/services/kakao_postcode_stub.dart';
import 'package:melon_core/data/models/discount_policy.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/storage_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';
import 'widgets/seat_map_picker.dart';

// =============================================================================
// 공연 등록 화면 (Editorial / Luxury Magazine Admin Design)
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
  final _maxTicketsCtrl = TextEditingController(text: '0');
  final _descriptionCtrl = TextEditingController();
  final _castCtrl = TextEditingController();
  final _organizerCtrl = TextEditingController(); // 주최
  final _plannerCtrl = TextEditingController(); // 기획
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

  // ── 할인 정책 ──
  final List<DiscountPolicy> _discountPolicies = [];

  bool _showRemainingSeats = true;
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
    '만 3세 이상',
    '만 5세 이상',
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
    _plannerCtrl.dispose();
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
      return const Scaffold(
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
            'Editorial Admin',
            style: AppTheme.serif(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 44,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  '관리자 권한이 필요합니다',
                  style: AppTheme.serif(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '관리자 계정으로 로그인 후 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.onAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: Text(
                    '홈으로 이동',
                    style: AppTheme.sans(fontWeight: FontWeight.w700),
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
                      MediaQuery.of(context).size.width >= 900 ? 40 : 20,
                  vertical: 32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
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
        // ── Form Title ──
        Text(
          '공연 등록',
          style: AppTheme.serif(
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 12,
          height: 1,
          color: AppTheme.gold,
        ),
        const SizedBox(height: 40),

        // ── Section 1: 기본 정보 ──
        _sectionHeader('기본 정보'),
        const SizedBox(height: 24),
        _field('공연명', isRequired: true,
            child: TextFormField(
              controller: _titleCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('공연 제목을 입력하세요'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '공연명을 입력해주세요' : null,
            )),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 460;
            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    child:
                        _field('카테고리', isRequired: true, child: _buildCategoryDropdown()),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _field('공연일시', isRequired: true, child: _buildDateTimePicker()),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _field('카테고리', isRequired: true, child: _buildCategoryDropdown()),
                const SizedBox(height: 20),
                _field('공연일시', isRequired: true, child: _buildDateTimePicker()),
              ],
            );
          },
        ),

        const SizedBox(height: 48),

        // ── Section 2: 공연장 ──
        _sectionHeader('공연장'),
        const SizedBox(height: 24),
        _buildSeatMapSection(),

        // ── Section 3: 등급별 가격 (좌석 데이터 로드 후 자동 표시) ──
        if (_seatMapData != null) ...[
          const SizedBox(height: 48),
          _sectionHeader('등급별 가격'),
          const SizedBox(height: 24),
          _buildGradeSelector(),
        ],

        const SizedBox(height: 48),

        // ── Section 4: 포스터 ──
        _sectionHeader('포스터'),
        const SizedBox(height: 24),
        _buildPosterPicker(),

        const SizedBox(height: 48),

        // ── Section 5: 상세 정보 ──
        _sectionHeader('상세 정보'),
        const SizedBox(height: 24),
        _buildOptionalFields(),

        const SizedBox(height: 48),

        // ── Section 6: 제작/기획 ──
        _sectionHeader('제작 / 기획'),
        const SizedBox(height: 24),
        _buildProducerFields(),

        const SizedBox(height: 48),

        // ── Section 7: 할인 정책 ──
        _sectionHeader('할인 정책'),
        const SizedBox(height: 24),
        _buildDiscountSection(),

        const SizedBox(height: 48),

        // ── Section 8: 추가 설정 ──
        _sectionHeader('추가 설정'),
        const SizedBox(height: 24),
        _buildAdditionalSettings(),

        const SizedBox(height: 100),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP BAR — Sticky editorial header
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
        color: AppTheme.background.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(
            color: AppTheme.border,
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
                color: AppTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Editorial Admin',
            style: AppTheme.serif(
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
  // BOTTOM BAR — Fixed burgundy submit
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitEvent,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: AppTheme.onAccent,
            disabledBackgroundColor: AppTheme.sage.withValues(alpha: 0.3),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.onAccent,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'REGISTER EVENT',
                      style: AppTheme.serif(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onAccent,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION HEADER — Serif italic + thin line
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: AppTheme.serif(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 0.5,
            color: AppTheme.sage.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: BASIC INFO WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _category,
      items: _categories
          .map((c) => DropdownMenuItem(
                value: c,
                child: Text(c, style: _inputStyle()),
              ))
          .toList(),
      onChanged: (v) => setState(() => _category = v!),
      decoration: _inputDecoration(null).copyWith(
        suffixIcon: const Icon(Icons.expand_more, size: 20, color: AppTheme.sage),
      ),
      dropdownColor: AppTheme.surface,
      icon: const SizedBox.shrink(),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 한글 요약 + 달력 버튼 ──
        Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 14, color: AppTheme.sage.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_startAt.year}년 ${_startAt.month}월 ${_startAt.day}일 ($wd) $amPm ${_startAt.hour}시 ${_startAt.minute.toString().padLeft(2, '0')}분',
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.gold,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _pickDateTime(
                  _startAt,
                  (dt) => setState(() {
                        _startAt = dt;
                        _syncControllersFromDateTime();
                      })),
              child: Text(
                'CALENDAR',
                style: AppTheme.label(
                  fontSize: 9,
                  color: AppTheme.gold,
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
            Text(':', style: AppTheme.sans(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            )),
            const SizedBox(width: 4),
            _dateTimeField(_minuteCtrl, 32, '분'),
            _dtLabel('분'),
          ],
        ),
      ],
    );
  }

  Widget _dateTimeField(TextEditingController ctrl, double width, String label) {
    return SizedBox(
      width: width,
      height: 36,
      child: TextFormField(
        controller: ctrl,
        style: AppTheme.sans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: false,
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.border, width: 0.5),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.sage.withValues(alpha: 0.4), width: 0.5),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.gold, width: 1),
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
        style: AppTheme.sans(
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
          style: AppTheme.sans(
            fontSize: 13,
            color: AppTheme.sage.withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),

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

        const SizedBox(height: 12),

        // ── 엑셀 업로드 (추가 옵션) ──
        _buildExcelUploadArea(),

        // ── 에러 ──
        if (_seatMapError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.06),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AppTheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_seatMapError!,
                        style: AppTheme.sans(
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
      onTap: () => context.push('/venues'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.08),
                shape: BoxShape.circle,
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
                      style: AppTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.gold,
                      )),
                  Text('공연장 관리에서 좌석 배치가 포함된 공연장을 등록할 수 있습니다',
                      style: AppTheme.sans(
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.gold.withValues(alpha: 0.04) : AppTheme.surface,
          border: Border.all(
            color: isSelected ? AppTheme.gold : AppTheme.sage.withValues(alpha: 0.2),
            width: isSelected ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.gold.withValues(alpha: 0.1)
                    : AppTheme.background,
                shape: BoxShape.circle,
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
                          style: AppTheme.sans(
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
                            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4), width: 0.5),
                          ),
                          child: Text('VIEW',
                              style: AppTheme.label(
                                fontSize: 8,
                                color: AppTheme.gold,
                              )),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층'
                    '${venue.address != null ? ' · ${venue.address}' : ''}',
                    style: AppTheme.sans(
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(
            color: AppTheme.sage.withValues(alpha: 0.25),
            width: 0.5,
            // Dashed border simulated via pattern
          ),
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
                  size: 28, color: AppTheme.sage.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(
              _isLoadingSeatMap ? '엑셀 분석 중...' : 'Drag or tap to upload seat data',
              style: AppTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.sage,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '시트명=층, 행: 구역 | 열 수 | 좌석 수 | 등급',
              style: AppTheme.sans(
                fontSize: 11,
                color: AppTheme.sage.withValues(alpha: 0.5),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3), width: 0.5),
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
                  style: AppTheme.serif(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _clearSeatMap,
                child: Text(
                  'RESET',
                  style: AppTheme.label(
                    fontSize: 9,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '총 ${fmt.format(data.totalSeats)}석 · ${data.floors.length}층',
            style: AppTheme.sans(
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
                        color: AppTheme.background,
                        border: Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Text(
                        '${f.name}: ${f.blocks.length}구역 (${fmt.format(f.totalSeats)}석)',
                        style: AppTheme.sans(
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
                        style: AppTheme.sans(
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
  // STEP 3: GRADE SELECTOR — 2-column grid editorial
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGradeSelector() {
    final fmt = NumberFormat('#,###');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 460;

        if (isWide) {
          // 2-column grid
          final gradeWidgets = _allGrades.map((grade) {
            return _buildGradeItem(grade, fmt);
          }).toList();

          final rows = <Widget>[];
          for (var i = 0; i < gradeWidgets.length; i += 2) {
            rows.add(
              Padding(
                padding: EdgeInsets.only(bottom: i + 2 < gradeWidgets.length ? 16 : 0),
                child: Row(
                  children: [
                    Expanded(child: gradeWidgets[i]),
                    const SizedBox(width: 20),
                    if (i + 1 < gradeWidgets.length)
                      Expanded(child: gradeWidgets[i + 1])
                    else
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            );
          }
          return Column(children: rows);
        }

        // Single column
        return Column(
          children: _allGrades.map((grade) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildGradeItem(grade, fmt),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildGradeItem(String grade, NumberFormat fmt) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Grade badge + checkbox
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
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
                  borderRadius: BorderRadius.circular(2),
                ),
                side: BorderSide(
                  color: isEnabled ? color : AppTheme.textTertiary,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isEnabled ? AppTheme.gold : AppTheme.sage.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                grade,
                style: AppTheme.label(
                  fontSize: 10,
                  color: isEnabled ? AppTheme.gold : AppTheme.textTertiary,
                ),
              ),
            ),
            if (_seatMapData != null) ...[
              const SizedBox(width: 8),
              Text(
                '${fmt.format(gradeSeats)}석',
                style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Price input — underline style
        TextFormField(
          controller: ctrl,
          enabled: isEnabled,
          style: AppTheme.sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isEnabled
                ? AppTheme.textPrimary
                : AppTheme.textTertiary,
          ),
          decoration: InputDecoration(
            suffixText: '원',
            suffixStyle: AppTheme.sans(
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 0, vertical: 10),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AppTheme.sage.withValues(alpha: 0.4), width: 0.5),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AppTheme.sage.withValues(alpha: 0.4), width: 0.5),
            ),
            disabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AppTheme.sage.withValues(alpha: 0.15), width: 0.5),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.gold, width: 1),
            ),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [_ThousandsSeparatorFormatter()],
          textAlign: TextAlign.end,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPTIONAL FIELDS — 상세 정보 section
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOptionalFields() {
    return Column(
      children: [
        // 공연 소개
        _field('공연 소개',
            child: TextFormField(
              controller: _descriptionCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('공연에 대한 설명을 입력하세요'),
              maxLines: 4,
            )),
        const SizedBox(height: 20),

        // 관람등급 + 공연시간
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 460;
            final ageLimitField = _field('관람등급', isRequired: true,
                child: DropdownButtonFormField<String>(
                  initialValue: _ageLimit,
                  items: _ageLimits
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Text(a, style: _inputStyle()),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _ageLimit = v!),
                  decoration: _inputDecoration(null).copyWith(
                    suffixIcon: const Icon(Icons.expand_more, size: 20, color: AppTheme.sage),
                  ),
                  dropdownColor: AppTheme.surface,
                  icon: const SizedBox.shrink(),
                ));
            final runningTimeField = _field('공연시간 (분)', isRequired: true,
                child: TextFormField(
                  controller: _runningTimeCtrl,
                  style: _inputStyle(),
                  decoration: _inputDecoration(null),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ));
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: ageLimitField),
                  const SizedBox(width: 24),
                  Expanded(child: runningTimeField),
                ],
              );
            }
            return Column(
              children: [
                ageLimitField,
                const SizedBox(height: 20),
                runningTimeField,
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // 공연장명
        _field('공연장명', isRequired: true,
            child: TextFormField(
              controller: _venueNameCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration(null),
            )),
        const SizedBox(height: 20),

        // 공연장 주소 (카카오 주소 검색)
        _field('공연장 주소', isRequired: true, child: _buildAddressField()),
        const SizedBox(height: 20),

        // 출연진
        _field('출연진',
            child: TextFormField(
              controller: _castCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('출연진 정보를 입력하세요'),
            )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRODUCER FIELDS — 제작/기획 section
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProducerFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 460;
        final hostField = _field('주최',
            child: TextFormField(
              controller: _organizerCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration(null),
            ));
        final plannerField = _field('기획',
            child: TextFormField(
              controller: _plannerCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration(null),
            ));
        if (isWide) {
          return Row(
            children: [
              Expanded(child: hostField),
              const SizedBox(width: 24),
              Expanded(child: plannerField),
            ],
          );
        }
        return Column(
          children: [
            hostField,
            const SizedBox(height: 20),
            plannerField,
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISCOUNT SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDiscountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 추가된 정책 카드 리스트
        ..._discountPolicies.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final priceFormat = NumberFormat('#,###');
          final basePrice = int.tryParse(
                  _gradePriceControllers.values.firstOrNull?.text
                          .replaceAll(',', '') ??
                      '55000') ??
              55000;
          final discounted = p.discountedPrice(basePrice);

          return Container(
            margin: EdgeInsets.only(bottom: i < _discountPolicies.length - 1 ? 8 : 0),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.sage.withValues(alpha: 0.2), width: 0.5),
            ),
            child: Row(
              children: [
                // 할인 아이콘
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: p.type == 'bulk'
                        ? AppTheme.gold.withValues(alpha: 0.08)
                        : AppTheme.success.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      p.type == 'bulk'
                          ? Icons.groups_rounded
                          : Icons.verified_user_rounded,
                      size: 16,
                      color: p.type == 'bulk'
                          ? AppTheme.gold
                          : AppTheme.success,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: AppTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${(p.discountRate * 100).toInt()}%',
                            style: AppTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.error,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${priceFormat.format(discounted)}원',
                            style: AppTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          if (p.description != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.description!,
                                style: AppTheme.sans(
                                  fontSize: 10,
                                  color: AppTheme.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 삭제
                IconButton(
                  onPressed: () => setState(() => _discountPolicies.removeAt(i)),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          );
        }),
        if (_discountPolicies.isNotEmpty) const SizedBox(height: 12),
        // 추가 버튼
        GestureDetector(
          onTap: () => _showAddDiscountDialog(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(
                color: AppTheme.gold.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded,
                    size: 16, color: AppTheme.gold),
                const SizedBox(width: 6),
                Text(
                  'ADD DISCOUNT POLICY',
                  style: AppTheme.label(
                    fontSize: 10,
                    color: AppTheme.gold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADDITIONAL SETTINGS — 예매 유의사항 + 최대 구매 + 잔여석 토글
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAdditionalSettings() {
    return Column(
      children: [
        // 예매 유의사항
        _field('예매 유의사항',
            child: TextFormField(
              controller: _noticeCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('예매 시 유의사항을 입력하세요'),
              maxLines: 3,
            )),
        const SizedBox(height: 20),

        // 최대 구매 수량
        _field('1인 최대 구매 수량',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _maxTicketsCtrl,
                  style: _inputStyle(),
                  decoration: _inputDecoration(null),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 6),
                Text(
                  '0 입력 시 무제한',
                  style: AppTheme.sans(
                    fontSize: 11,
                    color: AppTheme.sage.withValues(alpha: 0.6),
                  ),
                ),
              ],
            )),

        // 잔여석 표시 토글 — editorial bordered container
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25), width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '잔여석 표시',
                      style: AppTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '예매 화면에 남은 좌석 수를 표시합니다',
                      style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.sage.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _showRemainingSeats,
                onChanged: (v) => setState(() => _showRemainingSeats = v),
                activeTrackColor: AppTheme.gold,
                activeThumbColor: AppTheme.onAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _venueAddressCtrl,
                style: _inputStyle(),
                decoration: _inputDecoration(null),
                readOnly: true,
                onTap: _searchAddress,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _searchAddress,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 15, color: AppTheme.gold),
                    const SizedBox(width: 6),
                    Text('SEARCH',
                        style: AppTheme.label(
                          fontSize: 9,
                          color: AppTheme.gold,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _searchAddress() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('주소 검색은 웹에서만 지원됩니다'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      );
      return;
    }

    final result = await openKakaoPostcode();
    if (result != null && mounted) {
      setState(() {
        _venueAddressCtrl.text = result.fullAddress;
        // 공연장명이 비어있으면 건물명으로 자동 입력
        if (_venueNameCtrl.text.trim().isEmpty &&
            result.buildingName.isNotEmpty) {
          _venueNameCtrl.text = result.buildingName;
        }
      });
    }
  }

  void _showAddDiscountDialog() {
    String type = 'bulk';
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '2');
    final descCtrl = TextEditingController();

    showAnimatedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
            title: Text(
              '할인 정책 추가',
              style: AppTheme.serif(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 유형 선택
                  Text('DISCOUNT TYPE',
                      style: AppTheme.label(
                          fontSize: 9, color: AppTheme.sage)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _dialogChip(
                        label: '수량 할인',
                        icon: Icons.groups_rounded,
                        selected: type == 'bulk',
                        onTap: () => setDialogState(() => type = 'bulk'),
                      ),
                      const SizedBox(width: 8),
                      _dialogChip(
                        label: '대상 할인',
                        icon: Icons.verified_user_rounded,
                        selected: type == 'special',
                        onTap: () => setDialogState(() => type = 'special'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 이름
                  Text(type == 'bulk' ? 'CONDITION NAME' : 'TARGET NAME',
                      style: AppTheme.label(
                          fontSize: 9, color: AppTheme.sage)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: nameCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration(null),
                  ),

                  if (type == 'bulk') ...[
                    const SizedBox(height: 12),
                    Text('MIN QUANTITY',
                        style: AppTheme.label(
                            fontSize: 9, color: AppTheme.sage)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: qtyCtrl,
                      style: _inputStyle(),
                      decoration: _inputDecoration(null),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],

                  const SizedBox(height: 12),
                  Text('DISCOUNT RATE (%)',
                      style: AppTheme.label(
                          fontSize: 9, color: AppTheme.sage)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: rateCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration(null),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),

                  const SizedBox(height: 12),
                  Text('DESCRIPTION (OPTIONAL)',
                      style: AppTheme.label(
                          fontSize: 9, color: AppTheme.sage)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: descCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration(null),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('취소',
                    style: AppTheme.sans(color: AppTheme.textTertiary)),
              ),
              FilledButton(
                onPressed: () {
                  final rate = int.tryParse(rateCtrl.text) ?? 0;
                  if (nameCtrl.text.trim().isEmpty || rate <= 0 || rate > 100) {
                    return;
                  }
                  final name = nameCtrl.text.trim();
                  final qty = type == 'bulk'
                      ? (int.tryParse(qtyCtrl.text) ?? 2)
                      : 1;
                  final desc = descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim();

                  // 자동 이름 생성
                  final fullName = type == 'bulk'
                      ? '$name $rate%'
                      : '$name $rate%';

                  setState(() {
                    _discountPolicies.add(DiscountPolicy(
                      name: fullName,
                      type: type,
                      minQuantity: qty,
                      discountRate: rate / 100.0,
                      description: desc,
                    ));
                  });
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: AppTheme.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text('추가',
                    style: AppTheme.sans(fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.gold.withValues(alpha: 0.06)
                : AppTheme.background,
            border: Border.all(
              color: selected
                  ? AppTheme.gold.withValues(alpha: 0.4)
                  : AppTheme.sage.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? AppTheme.gold : AppTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppTheme.gold : AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPicker() {
    if (_posterBytes != null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.gold, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.memory(
              _posterBytes!,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  _posterActionBtn(Icons.edit_rounded, 'CHANGE', _pickPosterImage),
                  const SizedBox(width: 6),
                  _posterActionBtn(Icons.close_rounded, 'REMOVE', () {
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
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(
            color: AppTheme.sage.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: AppTheme.sage.withValues(alpha: 0.3),
            strokeWidth: 0.5,
            dashWidth: 6,
            dashSpace: 4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 28, color: AppTheme.sage.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(
                'Drag or tap to upload artwork',
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.sage,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Recommended: 1000x1440px (JPG, PNG)',
                style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.sage.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
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
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: AppTheme.label(
                  fontSize: 8,
                  color: Colors.white,
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS — Editorial field + underline input
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _field(String label, {required Widget child, bool isRequired = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.sage,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: AppTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.error,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.sans(
        fontSize: 14,
        color: AppTheme.sage.withValues(alpha: 0.5),
      ),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.sage.withValues(alpha: 0.4), width: 0.5),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.sage.withValues(alpha: 0.4), width: 0.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.gold, width: 1),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.error, width: 1),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.error, width: 1.5),
      ),
    );
  }

  TextStyle _inputStyle() {
    return AppTheme.sans(
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
          colorScheme: const ColorScheme.light(
            primary: AppTheme.gold,
            onPrimary: AppTheme.onAccent,
            surface: AppTheme.surface,
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
            colorScheme: const ColorScheme.light(
              primary: AppTheme.gold,
              onPrimary: AppTheme.onAccent,
              surface: AppTheme.surface,
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
                    borderRadius: BorderRadius.circular(4)),
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
        maxTicketsPerOrder: int.tryParse(_maxTicketsCtrl.text) ?? 0,
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
        planner: _plannerCtrl.text.trim().isEmpty
            ? null
            : _plannerCtrl.text.trim(),
        notice:
            _noticeCtrl.text.trim().isEmpty ? null : _noticeCtrl.text.trim(),
        discount: _discountPolicies.isNotEmpty
            ? _discountPolicies.map((p) => p.name).join(', ')
            : null,
        priceByGrade: priceByGrade.isNotEmpty ? priceByGrade : null,
        discountPolicies:
            _discountPolicies.isNotEmpty ? _discountPolicies : null,
        showRemainingSeats: _showRemainingSeats,
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

    showAnimatedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnimatedDialogContent(
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
                        color: AppTheme.gold.withValues(alpha: 0.3),
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
                  style: AppTheme.serif(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '총 ${fmt.format(totalSeats)}석 · 즉시 판매 시작',
                  style: AppTheme.sans(
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
                    color: AppTheme.background,
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
                          style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: fullUrl));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: const Text('링크가 복사되었습니다'),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text(
                          'COPY',
                          style: AppTheme.label(
                            fontSize: 9,
                            color: AppTheme.gold,
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
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.go(eventPath);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: AppTheme.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      'VIEW EVENT',
                      style: AppTheme.serif(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onAccent,
                        letterSpacing: 2.0,
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
                      context.go('/');
                    },
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: AppTheme.border, width: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      'DASHBOARD',
                      style: AppTheme.label(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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

/// Dashed border painter for editorial poster upload area
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashWidth = 6.0,
    this.dashSpace = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw dashed border
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, end),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashWidth != oldDelegate.dashWidth ||
      dashSpace != oldDelegate.dashSpace;
}

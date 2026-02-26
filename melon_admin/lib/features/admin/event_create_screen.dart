import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/admin_theme.dart';
import '../../widgets/premium_datetime_picker.dart';
import 'package:melon_core/services/kakao_postcode_service.dart'
    if (dart.library.io) 'package:melon_core/services/kakao_postcode_stub.dart';
import 'package:melon_core/data/models/discount_policy.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/data/repositories/hall_repository.dart';
import 'package:melon_core/data/models/hall.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/storage_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';
import 'widgets/seat_map_picker.dart';

// =============================================================================
// 공연 등록 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

class EventCreateScreen extends ConsumerStatefulWidget {
  final String? editEventId;
  final String? cloneEventId;
  const EventCreateScreen({super.key, this.editEventId, this.cloneEventId});

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
  final _inquiryInfoCtrl = TextEditingController(); // 예매 관련 문의

  // ── State ──
  String _category = '콘서트';
  final Set<String> _selectedTags = {};
  String _ageLimit = '전체관람가';
  DateTime _startAt = DateTime.now().add(const Duration(days: 14));

  // ── 날짜/시간 직접 입력 컨트롤러 ──
  late final TextEditingController _yearCtrl;
  late final TextEditingController _monthCtrl;
  late final TextEditingController _dayCtrl;
  late final TextEditingController _hourCtrl;
  late final TextEditingController _minuteCtrl;

  // ── 비지정석(스탠딩) ──
  bool _isStanding = false;
  final _standingCapacityCtrl = TextEditingController(text: '100');

  // ── 다회 공연 (연속 회차) ──
  bool _isMultiSession = false;
  final List<DateTime> _sessionDates = []; // 추가 회차 날짜

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

  Uint8List? _posterBytes; // 업로드 중 임시 미리보기용
  String? _posterUrl; // 서버에 업로드된 포스터 URL
  bool _isUploadingPoster = false;

  // ── 팜플렛 (최대 8장, 장당 3MB) ──
  final ScrollController _pamphletScrollCtrl = ScrollController();
  List<String> _pamphletUrls = []; // 서버에 업로드된 팜플렛 URLs
  bool _isUploadingPamphlet = false;
  static const _maxPamphlets = 8;
  static const _maxPamphletBytes = 3 * 1024 * 1024; // 3MB per image

  // ── 할인 정책 ──
  final List<DiscountPolicy> _discountPolicies = [];

  bool _showRemainingSeats = true;
  String? _hallId; // Hall 커뮤니티 채널 ID
  String? _hallDisplayName; // Hall 이름 (UI 표시용)
  final _hallNameCtrl = TextEditingController();
  bool _isSubmitting = false;
  double _submitProgress = 0.0;
  String _submitStage = '';

  // ── 수정 모드 ──
  bool get _isEditMode => widget.editEventId != null;
  bool _isLoadingEvent = false;

  // ── 임시저장 (Draft) ──
  static const _draftKey = 'event_create_draft';
  Timer? _autoSaveTimer;
  bool _hasDraft = false;
  DateTime? _draftSavedAt;

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

  static const _availableTags = [
    '내한',
    '단독',
    '앵콜',
    '월드투어',
    '페스티벌',
    '첫 내한',
    '한정',
    '프리미엄',
    '가족',
    '시즌',
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
    if (_isEditMode) {
      _loadEventForEdit();
    } else if (widget.cloneEventId != null) {
      _loadEventForClone();
    } else {
      _checkDraft();
    }
    // 30초마다 자동 저장 (신규 등록 시에만)
    if (!_isEditMode) {
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) => _saveDraft());
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
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
    _inquiryInfoCtrl.dispose();
    _pamphletScrollCtrl.dispose();
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
  // DRAFT (임시저장)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _checkDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_draftKey);
    if (json != null && json.isNotEmpty) {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final savedAt = data['savedAt'] != null
          ? DateTime.tryParse(data['savedAt'] as String)
          : null;
      if (mounted) {
        setState(() {
          _hasDraft = true;
          _draftSavedAt = savedAt;
        });
      }
    }
  }

  Future<void> _saveDraft({bool silent = true}) async {
    // 폼이 비어있으면 저장하지 않음
    if (_titleCtrl.text.trim().isEmpty &&
        _venueNameCtrl.text.trim().isEmpty &&
        _descriptionCtrl.text.trim().isEmpty) {
      return;
    }

    final data = <String, dynamic>{
      'savedAt': DateTime.now().toIso8601String(),
      'title': _titleCtrl.text,
      'category': _category,
      'tags': _selectedTags.toList(),
      'ageLimit': _ageLimit,
      'startAt': _startAt.toIso8601String(),
      'venueName': _venueNameCtrl.text,
      'venueAddress': _venueAddressCtrl.text,
      'runningTime': _runningTimeCtrl.text,
      'maxTickets': _maxTicketsCtrl.text,
      'description': _descriptionCtrl.text,
      'cast': _castCtrl.text,
      'organizer': _organizerCtrl.text,
      'planner': _plannerCtrl.text,
      'notice': _noticeCtrl.text,
      'inquiryInfo': _inquiryInfoCtrl.text,
      'enabledGrades': _enabledGrades.toList(),
      'gradePrices': {
        for (final e in _gradePriceControllers.entries) e.key: e.value.text,
      },
      'showRemainingSeats': _showRemainingSeats,
      'isStanding': _isStanding,
      'standingCapacity': _standingCapacityCtrl.text,
      if (_hallId != null) 'hallId': _hallId,
      'discountPolicies':
          _discountPolicies.map((p) => p.toMap()).toList(),
      if (_selectedVenue != null) 'venueId': _selectedVenue!.id,
      if (_posterUrl != null) 'posterUrl': _posterUrl,
      'pamphletUrls': _pamphletUrls,
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(data));

    if (mounted) {
      setState(() {
        _draftSavedAt = DateTime.now();
        _hasDraft = true;
      });
    }

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '임시저장 완료 (${DateFormat('HH:mm').format(DateTime.now())})',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AdminTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_draftKey);
    if (json == null || json.isEmpty) return;

    final data = jsonDecode(json) as Map<String, dynamic>;

    setState(() {
      _hasDraft = false;
      _titleCtrl.text = data['title'] as String? ?? '';
      _category = data['category'] as String? ?? '콘서트';
      if (data['tags'] != null) {
        _selectedTags
          ..clear()
          ..addAll(List<String>.from(data['tags'] as List));
      }
      _ageLimit = data['ageLimit'] as String? ?? '전체관람가';

      if (data['startAt'] != null) {
        _startAt = DateTime.tryParse(data['startAt'] as String) ?? _startAt;
        _yearCtrl.text = _startAt.year.toString();
        _monthCtrl.text = _startAt.month.toString();
        _dayCtrl.text = _startAt.day.toString();
        _hourCtrl.text = _startAt.hour.toString().padLeft(2, '0');
        _minuteCtrl.text = _startAt.minute.toString().padLeft(2, '0');
      }

      _venueNameCtrl.text = data['venueName'] as String? ?? '';
      _venueAddressCtrl.text = data['venueAddress'] as String? ?? '';
      _runningTimeCtrl.text = data['runningTime'] as String? ?? '120';
      _maxTicketsCtrl.text = data['maxTickets'] as String? ?? '0';
      _descriptionCtrl.text = data['description'] as String? ?? '';
      _castCtrl.text = data['cast'] as String? ?? '';
      _organizerCtrl.text = data['organizer'] as String? ?? '';
      _plannerCtrl.text = data['planner'] as String? ?? '';
      _noticeCtrl.text = data['notice'] as String? ?? '';
      _inquiryInfoCtrl.text = data['inquiryInfo'] as String? ?? '';
      _showRemainingSeats = data['showRemainingSeats'] as bool? ?? true;
      _isStanding = data['isStanding'] as bool? ?? false;
      _standingCapacityCtrl.text = data['standingCapacity'] as String? ?? '100';
      _hallId = data['hallId'] as String?;

      if (data['enabledGrades'] != null) {
        _enabledGrades
          ..clear()
          ..addAll(List<String>.from(data['enabledGrades'] as List));
      }

      if (data['gradePrices'] != null) {
        final prices = data['gradePrices'] as Map<String, dynamic>;
        for (final entry in prices.entries) {
          _gradePriceControllers[entry.key]?.text = entry.value as String;
        }
      }

      if (data['discountPolicies'] != null) {
        _discountPolicies
          ..clear()
          ..addAll(
            (data['discountPolicies'] as List)
                .map((m) => DiscountPolicy.fromMap(m as Map<String, dynamic>)),
          );
      }

      // 포스터/팜플렛 URL 복원
      _posterUrl = data['posterUrl'] as String?;
      if (data['pamphletUrls'] != null) {
        _pamphletUrls = List<String>.from(data['pamphletUrls'] as List);
      }
    });
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    if (mounted) {
      setState(() {
        _hasDraft = false;
        _draftSavedAt = null;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD EVENT FOR EDIT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadEventForEdit() async {
    setState(() => _isLoadingEvent = true);
    try {
      final event = await ref
          .read(eventRepositoryProvider)
          .getEvent(widget.editEventId!);
      if (event == null || !mounted) return;

      final priceFmt = NumberFormat('#,###');
      setState(() {
        _titleCtrl.text = event.title;
        _category = event.category ?? '콘서트';
        _selectedTags
          ..clear()
          ..addAll(event.tags);
        _ageLimit = event.ageLimit ?? '전체관람가';
        _startAt = event.startAt;
        _yearCtrl.text = _startAt.year.toString();
        _monthCtrl.text = _startAt.month.toString();
        _dayCtrl.text = _startAt.day.toString();
        _hourCtrl.text = _startAt.hour.toString().padLeft(2, '0');
        _minuteCtrl.text = _startAt.minute.toString().padLeft(2, '0');
        _venueNameCtrl.text = event.venueName ?? '';
        _venueAddressCtrl.text = event.venueAddress ?? '';
        _runningTimeCtrl.text = (event.runningTime ?? 120).toString();
        _maxTicketsCtrl.text = (event.maxTicketsPerOrder).toString();
        _descriptionCtrl.text = event.description;
        _castCtrl.text = event.cast ?? '';
        _organizerCtrl.text = event.organizer ?? '';
        _plannerCtrl.text = event.planner ?? '';
        _noticeCtrl.text = event.notice ?? '';
        _inquiryInfoCtrl.text = event.inquiryInfo ?? '';
        _showRemainingSeats = event.showRemainingSeats;
        _isStanding = event.isStanding;
        _hallId = event.hallId;

        if (event.priceByGrade != null) {
          _enabledGrades
            ..clear()
            ..addAll(event.priceByGrade!.keys);
          for (final entry in event.priceByGrade!.entries) {
            _gradePriceControllers[entry.key]?.text =
                priceFmt.format(entry.value);
          }
        }

        if (event.discountPolicies != null) {
          _discountPolicies
            ..clear()
            ..addAll(event.discountPolicies!);
        }

        // 기존 포스터/팜플렛 URL 로드
        _posterUrl = event.imageUrl;
        _pamphletUrls = List<String>.from(event.pamphletUrls ?? []);
      });

      // 공연장의 좌석 맵 데이터 자동 로드
      if (event.venueId.isNotEmpty) {
        final venue = await ref.read(venueRepositoryProvider).getVenue(event.venueId);
        if (venue != null && mounted) {
          _selectVenue(venue);
        }
      }
    } catch (e) {
      if (mounted) _showError('공연 데이터 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoadingEvent = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD EVENT FOR CLONE (복제)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadEventForClone() async {
    setState(() => _isLoadingEvent = true);
    try {
      final event = await ref
          .read(eventRepositoryProvider)
          .getEvent(widget.cloneEventId!);
      if (event == null || !mounted) return;

      final priceFmt = NumberFormat('#,###');
      setState(() {
        _titleCtrl.text = '${event.title} (복제)';
        _category = event.category ?? '콘서트';
        _selectedTags
          ..clear()
          ..addAll(event.tags);
        _ageLimit = event.ageLimit ?? '전체관람가';
        // 날짜/시간은 현재 기준으로 리셋 (복제이므로 새 일정 입력 필요)
        _venueNameCtrl.text = event.venueName ?? '';
        _venueAddressCtrl.text = event.venueAddress ?? '';
        _runningTimeCtrl.text = (event.runningTime ?? 120).toString();
        _maxTicketsCtrl.text = (event.maxTicketsPerOrder).toString();
        _descriptionCtrl.text = event.description;
        _castCtrl.text = event.cast ?? '';
        _organizerCtrl.text = event.organizer ?? '';
        _plannerCtrl.text = event.planner ?? '';
        _noticeCtrl.text = event.notice ?? '';
        _inquiryInfoCtrl.text = event.inquiryInfo ?? '';
        _showRemainingSeats = event.showRemainingSeats;
        _isStanding = event.isStanding;
        _hallId = event.hallId;

        if (event.priceByGrade != null) {
          _enabledGrades
            ..clear()
            ..addAll(event.priceByGrade!.keys);
          for (final entry in event.priceByGrade!.entries) {
            _gradePriceControllers[entry.key]?.text =
                priceFmt.format(entry.value);
          }
        }

        if (event.discountPolicies != null) {
          _discountPolicies
            ..clear()
            ..addAll(event.discountPolicies!);
        }

        // 포스터/팜플렛 URL 복사
        _posterUrl = event.imageUrl;
        _pamphletUrls = List<String>.from(event.pamphletUrls ?? []);
      });

      // 공연장 자동 선택
      if (event.venueId.isNotEmpty) {
        final venue = await ref.read(venueRepositoryProvider).getVenue(event.venueId);
        if (venue != null && mounted) {
          _selectVenue(venue);
        }
      }
    } catch (e) {
      if (mounted) _showError('공연 데이터 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoadingEvent = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser.isLoading || _isLoadingEvent) {
      return const Scaffold(
        backgroundColor: AdminTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AdminTheme.gold),
        ),
      );
    }

    if (currentUser.value?.isAdmin != true) {
      return Scaffold(
        backgroundColor: AdminTheme.background,
        appBar: AppBar(
          backgroundColor: AdminTheme.surface,
          foregroundColor: AdminTheme.textPrimary,
          title: Text(
            'Editorial Admin',
            style: AdminTheme.serif(
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
                  color: AdminTheme.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  '관리자 권한이 필요합니다',
                  style: AdminTheme.serif(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '관리자 계정으로 로그인 후 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.gold,
                    foregroundColor: AdminTheme.onAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: Text(
                    '홈으로 이동',
                    style: AdminTheme.sans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          // ── 임시저장 복원 배너 ──
          if (_hasDraft) _buildDraftBanner(),
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
          _isEditMode ? '공연 수정' : '공연 등록',
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

        const SizedBox(height: 20),

        // ── 비지정석(스탠딩) 토글 ──
        _buildStandingToggle(),

        const SizedBox(height: 20),

        // ── 태그 ──
        _field('태그', child: _buildTagsSelector()),

        const SizedBox(height: 20),

        // ── 커뮤니티 연결 ──
        _buildHallSelector(),

        const SizedBox(height: 20),

        // ── 다회 공연 토글 ──
        _buildMultiSessionSection(),

        const SizedBox(height: 48),

        // ── Section 2: 공연장 (스탠딩이 아닌 경우에만) ──
        if (!_isStanding) ...[
          _sectionHeader('공연장'),
          const SizedBox(height: 24),
          if (_isEditMode) ...[
            // 수정 모드: 좌석 배치 변경 불가 안내
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminTheme.sage.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AdminTheme.border, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: AdminTheme.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '좌석 배치는 수정할 수 없습니다. 좌석 변경이 필요하면 좌석 관리에서 수정하세요.',
                      style: AdminTheme.sans(
                        fontSize: 13,
                        color: AdminTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 수정 모드에서도 등급별 가격은 수정 가능
            if (_enabledGrades.isNotEmpty) ...[
              const SizedBox(height: 48),
              _sectionHeader('등급별 가격'),
              const SizedBox(height: 24),
              _buildGradeSelector(),
            ],
          ] else ...[
            _buildSeatMapSection(),
            // ── Section 3: 등급별 가격 (좌석 데이터 로드 후 자동 표시) ──
            if (_seatMapData != null) ...[
              const SizedBox(height: 48),
              _sectionHeader('등급별 가격'),
              const SizedBox(height: 24),
              _buildGradeSelector(),
            ],
          ],
        ],

        const SizedBox(height: 48),

        // ── Section 4: 포스터 ──
        _sectionHeader('포스터'),
        const SizedBox(height: 24),
        _buildPosterPicker(),

        const SizedBox(height: 48),

        // ── Section 4.5: 팜플렛 ──
        _sectionHeader('팜플렛'),
        const SizedBox(height: 8),
        Text('공연 상세 팜플렛 이미지를 등록하세요 (최대 $_maxPamphlets장, 장당 3MB)',
            style: AdminTheme.sans(
              fontSize: 12,
              color: AdminTheme.textTertiary,
            )),
        const SizedBox(height: 16),
        _buildPamphletPicker(),

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
          const Spacer(),
          // ── 자동저장 시각 표시 ──
          if (_draftSavedAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${DateFormat('HH:mm').format(_draftSavedAt!)} 저장됨',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ),
          // ── 임시저장 버튼 ──
          GestureDetector(
            onTap: () => _saveDraft(silent: false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AdminTheme.gold.withValues(alpha: 0.4),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_outlined,
                      size: 14,
                      color: AdminTheme.gold.withValues(alpha: 0.8)),
                  const SizedBox(width: 5),
                  Text(
                    '임시저장',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.gold,
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

  Widget _buildDraftBanner() {
    final timeStr = _draftSavedAt != null
        ? DateFormat('M/d HH:mm').format(_draftSavedAt!)
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AdminTheme.gold.withValues(alpha: 0.08),
        border: const Border(
          bottom: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.restore_rounded,
              size: 18, color: AdminTheme.gold.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '작성 중이던 임시저장본이 있습니다${timeStr.isNotEmpty ? ' ($timeStr)' : ''}',
              style: AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              await _loadDraft();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('임시저장본을 불러왔습니다'),
                    backgroundColor: AdminTheme.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AdminTheme.gold,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '불러오기',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              await _clearDraft();
            },
            child: Text(
              '삭제',
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.textTertiary,
              ),
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
        color: AdminTheme.background.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: _isSubmitting
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 단계 텍스트 + 퍼센트
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AdminTheme.gold.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _submitStage,
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${(_submitProgress * 100).toInt()}%',
                      style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 프로그레스 바
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _submitProgress),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: AdminTheme.sage.withValues(alpha: 0.15),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AdminTheme.gold),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitEvent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.gold,
                  foregroundColor: AdminTheme.onAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isEditMode ? 'UPDATE EVENT' : 'REGISTER EVENT',
                      style: AdminTheme.serif(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.onAccent,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(_isEditMode ? Icons.save_rounded : Icons.arrow_forward, size: 18),
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
        suffixIcon: const Icon(Icons.expand_more, size: 20, color: AdminTheme.sage),
      ),
      dropdownColor: AdminTheme.surface,
      icon: const SizedBox.shrink(),
    );
  }

  Widget _buildTagsSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableTags.map((tag) {
        final selected = _selectedTags.contains(tag);
        return FilterChip(
          label: Text(
            tag,
            style: TextStyle(
              color: selected ? AdminTheme.background : AdminTheme.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) {
              _selectedTags.add(tag);
            } else {
              _selectedTags.remove(tag);
            }
          }),
          selectedColor: AdminTheme.gold,
          backgroundColor: AdminTheme.surface,
          checkmarkColor: AdminTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected
                  ? AdminTheme.gold
                  : AdminTheme.sage.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

  Widget _buildStandingToggle() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isStanding
                ? AdminTheme.gold.withValues(alpha: 0.08)
                : AdminTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isStanding
                  ? AdminTheme.gold.withValues(alpha: 0.4)
                  : AdminTheme.border,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isStanding ? Icons.people_rounded : Icons.event_seat_rounded,
                color: _isStanding ? AdminTheme.gold : AdminTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '비지정석 (스탠딩)',
                      style: TextStyle(
                        color: AdminTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '좌석 배치 없이 수량 기반 입장권 발매',
                      style: TextStyle(
                        color: AdminTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isStanding,
                onChanged: (v) => setState(() => _isStanding = v),
                activeColor: AdminTheme.gold,
                activeTrackColor: AdminTheme.gold.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
        if (_isStanding) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field('수용 인원', isRequired: true, child: TextFormField(
                  controller: _standingCapacityCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '100',
                    hintStyle: TextStyle(color: AdminTheme.textSecondary.withValues(alpha: 0.5)),
                    suffixText: '명',
                    suffixStyle: TextStyle(color: AdminTheme.textSecondary, fontSize: 13),
                    filled: true,
                    fillColor: AdminTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AdminTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AdminTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AdminTheme.gold, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                )),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _field('입장권 가격', isRequired: true, child: TextFormField(
                  controller: _gradePriceControllers['일반'] ?? (_gradePriceControllers['일반'] = TextEditingController()),
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '50,000',
                    hintStyle: TextStyle(color: AdminTheme.textSecondary.withValues(alpha: 0.5)),
                    suffixText: '원',
                    suffixStyle: TextStyle(color: AdminTheme.textSecondary, fontSize: 13),
                    filled: true,
                    fillColor: AdminTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AdminTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AdminTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AdminTheme.gold, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                )),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHallSelector() {
    final isConnected = _hallId != null && _hallId!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isConnected
            ? AdminTheme.gold.withValues(alpha: 0.08)
            : AdminTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected
              ? AdminTheme.gold.withValues(alpha: 0.4)
              : AdminTheme.border,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: isConnected,
              onChanged: (v) {
                if (v == true) {
                  _showHallPicker();
                } else {
                  setState(() {
                    _hallId = null;
                    _hallNameCtrl.clear();
                  });
                }
              },
              activeColor: AdminTheme.gold,
              checkColor: AdminTheme.onAccent,
              side: BorderSide(
                color: AdminTheme.sage.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.forum_rounded,
            color: isConnected ? AdminTheme.gold : AdminTheme.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '커뮤니티 연결',
            style: TextStyle(
              color: isConnected ? AdminTheme.textPrimary : AdminTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isConnected) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _hallDisplayName ?? _hallId!,
                style: TextStyle(
                  color: AdminTheme.gold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: _showHallPicker,
              icon: Icon(Icons.edit_rounded,
                  size: 16, color: AdminTheme.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '변경',
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  void _showHallPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        final hallNameCtrl = TextEditingController();
        final allHalls = ref.read(allHallsProvider);
        return AlertDialog(
          backgroundColor: AdminTheme.surface,
          title: Text('커뮤니티 연결', style: AdminTheme.serif(fontSize: 18)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 기존 Hall 목록
                Text('기존 Hall 선택',
                    style: AdminTheme.sans(
                        fontSize: 13, color: AdminTheme.textSecondary)),
                const SizedBox(height: 8),
                allHalls.when(
                  data: (halls) {
                    if (halls.isEmpty) {
                      return Text('등록된 Hall이 없습니다.',
                          style: AdminTheme.sans(
                              fontSize: 12, color: AdminTheme.textTertiary));
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: halls.length,
                        itemBuilder: (_, i) {
                          final hall = halls[i];
                          final isSelected = _hallId == hall.id;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor:
                                AdminTheme.gold.withValues(alpha: 0.08),
                            leading: Icon(Icons.forum_rounded,
                                size: 18,
                                color: isSelected
                                    ? AdminTheme.gold
                                    : AdminTheme.textTertiary),
                            title: Text(hall.name,
                                style: AdminTheme.sans(
                                    fontSize: 13,
                                    color: isSelected
                                        ? AdminTheme.gold
                                        : AdminTheme.textPrimary)),
                            onTap: () {
                              setState(() {
                                _hallId = hall.id;
                                _hallDisplayName = hall.name;
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const SizedBox(
                      height: 40,
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AdminTheme.gold))),
                  error: (_, __) => Text('Hall 목록 로드 실패',
                      style: AdminTheme.sans(
                          fontSize: 12, color: AdminTheme.error)),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 0.5,
                  color: AdminTheme.border,
                ),
                const SizedBox(height: 16),
                // 새 Hall 생성
                Text('또는 새 Hall 생성',
                    style: AdminTheme.sans(
                        fontSize: 13, color: AdminTheme.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: hallNameCtrl,
                  style: AdminTheme.sans(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '공연명 (예: 레미제라블)',
                    hintStyle: AdminTheme.sans(
                        fontSize: 13, color: AdminTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소',
                  style: AdminTheme.sans(color: AdminTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (hallNameCtrl.text.trim().isNotEmpty) {
                  final hallRepo = ref.read(hallRepositoryProvider);
                  final hallId = await hallRepo.createHall(Hall(
                    id: '',
                    name: hallNameCtrl.text.trim(),
                    createdBy: 'admin',
                    createdAt: DateTime.now(),
                  ));
                  setState(() {
                    _hallId = hallId;
                    _hallDisplayName = hallNameCtrl.text.trim();
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
              ),
              child: Text('생성',
                  style: AdminTheme.sans(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
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
        GestureDetector(
          onTap: () => _pickDateTime(
              _startAt,
              (dt) => setState(() {
                    _startAt = dt;
                    _syncControllersFromDateTime();
                  })),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              border: Border.all(
                  color: AdminTheme.gold.withValues(alpha: 0.3), width: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_startAt.year}년 ${_startAt.month}월 ${_startAt.day}일 ($wd)',
                        style: AdminTheme.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$amPm ${_startAt.hour}시 ${_startAt.minute.toString().padLeft(2, '0')}분',
                        style: AdminTheme.sans(
                          fontSize: 13,
                          color: AdminTheme.gold,
                        ),
                      ),
                    ],
                  ),
                ),
                Text('변경',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AdminTheme.gold,
                    )),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AdminTheme.gold.withValues(alpha: 0.6)),
              ],
            ),
          ),
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
            Text(':', style: AdminTheme.sans(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: AdminTheme.textTertiary,
            )),
            const SizedBox(width: 4),
            _dateTimeField(_minuteCtrl, 32, '분'),
            _dtLabel('분'),
          ],
        ),
      ],
    );
  }

  Widget _buildMultiSessionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 토글
        Row(
          children: [
            Text(
              '다회 공연 (연속 회차)',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textSecondary,
              ),
            ),
            const Spacer(),
            Switch(
              value: _isMultiSession,
              onChanged: (v) => setState(() {
                _isMultiSession = v;
                if (!v) _sessionDates.clear();
              }),
              activeColor: AdminTheme.gold,
            ),
          ],
        ),
        if (_isMultiSession) ...[
          const SizedBox(height: 8),
          // 추가 회차 리스트
          ..._sessionDates.asMap().entries.map((entry) {
            final idx = entry.key;
            final date = entry.value;
            final wd = _weekdays[date.weekday - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '${idx + 2}회차',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.gold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickDateTime(
                        date,
                        (dt) => setState(() => _sessionDates[idx] = dt),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AdminTheme.surface,
                          border: Border.all(
                              color: AdminTheme.border, width: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${date.year}.${date.month}.${date.day} ($wd) ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            color: AdminTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _sessionDates.removeAt(idx)),
                    child: const Icon(Icons.close_rounded,
                        size: 18, color: AdminTheme.error),
                  ),
                ],
              ),
            );
          }),
          // 회차 추가 버튼
          GestureDetector(
            onTap: () {
              final lastDate = _sessionDates.isNotEmpty
                  ? _sessionDates.last
                  : _startAt;
              setState(() {
                _sessionDates
                    .add(lastDate.add(const Duration(days: 1)));
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                    color: AdminTheme.gold.withValues(alpha: 0.3),
                    width: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded,
                      size: 16,
                      color: AdminTheme.gold.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    '회차 추가',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.gold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '1회차: 위의 공연일시 기준. 각 회차별 좌석이 독립적으로 관리됩니다.',
            style: AdminTheme.sans(
              fontSize: 11,
              color: AdminTheme.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateTimeField(TextEditingController ctrl, double width, String label) {
    return SizedBox(
      width: width,
      height: 36,
      child: TextFormField(
        controller: ctrl,
        style: AdminTheme.sans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AdminTheme.textPrimary,
        ),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: false,
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: AdminTheme.border, width: 0.5),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AdminTheme.sage.withValues(alpha: 0.4), width: 0.5),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AdminTheme.gold, width: 1),
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
        style: AdminTheme.sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AdminTheme.textTertiary,
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
          style: AdminTheme.sans(
            fontSize: 13,
            color: AdminTheme.sage.withValues(alpha: 0.7),
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
                        strokeWidth: 2, color: AdminTheme.gold))),
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
                color: AdminTheme.error.withValues(alpha: 0.06),
                border: Border.all(color: AdminTheme.error.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AdminTheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_seatMapError!,
                        style: AdminTheme.sans(
                            fontSize: 13, color: AdminTheme.error)),
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
      onTap: () => context.go('/venues'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AdminTheme.gold.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_location_alt_rounded,
                  size: 20, color: AdminTheme.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('공연장을 먼저 등록하세요',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.gold,
                      )),
                  Text('공연장 관리에서 좌석 배치가 포함된 공연장을 등록할 수 있습니다',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        color: AdminTheme.textTertiary,
                      )),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AdminTheme.gold),
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
          color: isSelected ? AdminTheme.gold.withValues(alpha: 0.04) : AdminTheme.surface,
          border: Border.all(
            color: isSelected ? AdminTheme.gold : AdminTheme.sage.withValues(alpha: 0.2),
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
                    ? AdminTheme.gold.withValues(alpha: 0.1)
                    : AdminTheme.background,
                shape: BoxShape.circle,
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
                  Row(
                    children: [
                      Text(venue.name,
                          style: AdminTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AdminTheme.textPrimary,
                          )),
                      if (venue.seatMapImageUrl != null &&
                          venue.seatMapImageUrl!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AdminTheme.sage.withValues(alpha: 0.4),
                                width: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text('2D VIEW',
                              style: AdminTheme.label(
                                fontSize: 8,
                                color: AdminTheme.textSecondary,
                              )),
                        ),
                      ],
                      if (venue.hasSeatView) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: AdminTheme.goldGradient,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text('3D VIEW',
                              style: AdminTheme.label(
                                fontSize: 8,
                                color: AdminTheme.onAccent,
                              )),
                        ),
                      ],
                    ],
                  ),
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
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: AdminTheme.gold, size: 20),
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
          color: AdminTheme.surface,
          border: Border.all(
            color: AdminTheme.sage.withValues(alpha: 0.25),
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
                      strokeWidth: 2, color: AdminTheme.gold))
            else
              Icon(Icons.cloud_upload_outlined,
                  size: 28, color: AdminTheme.sage.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(
              _isLoadingSeatMap ? '엑셀 분석 중...' : 'Drag or tap to upload seat data',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AdminTheme.sage,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '시트명=층, 행: 구역 | 열 수 | 좌석 수 | 등급',
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.sage.withValues(alpha: 0.5),
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
        color: AdminTheme.surface,
        border: Border.all(color: AdminTheme.success.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AdminTheme.success, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.venueName,
                  style: AdminTheme.serif(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _clearSeatMap,
                child: Text(
                  'RESET',
                  style: AdminTheme.label(
                    fontSize: 9,
                    color: AdminTheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '총 ${fmt.format(data.totalSeats)}석 · ${data.floors.length}층',
            style: AdminTheme.sans(
              fontSize: 13,
              color: AdminTheme.textSecondary,
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
                        color: AdminTheme.background,
                        border: Border.all(color: AdminTheme.border, width: 0.5),
                      ),
                      child: Text(
                        '${f.name}: ${f.blocks.length}구역 (${fmt.format(f.totalSeats)}석)',
                        style: AdminTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AdminTheme.textSecondary,
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
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AdminTheme.textSecondary,
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
                  color: isEnabled ? color : AdminTheme.textTertiary,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isEnabled ? AdminTheme.gold : AdminTheme.sage.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                grade,
                style: AdminTheme.label(
                  fontSize: 10,
                  color: isEnabled ? AdminTheme.gold : AdminTheme.textTertiary,
                ),
              ),
            ),
            if (_seatMapData != null) ...[
              const SizedBox(width: 8),
              Text(
                '${fmt.format(gradeSeats)}석',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
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
          style: AdminTheme.sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isEnabled
                ? AdminTheme.textPrimary
                : AdminTheme.textTertiary,
          ),
          decoration: InputDecoration(
            suffixText: '원',
            suffixStyle: AdminTheme.sans(
              fontSize: 13,
              color: AdminTheme.textTertiary,
            ),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 0, vertical: 10),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AdminTheme.sage.withValues(alpha: 0.4), width: 0.5),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AdminTheme.sage.withValues(alpha: 0.4), width: 0.5),
            ),
            disabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AdminTheme.gold, width: 1),
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
                    suffixIcon: const Icon(Icons.expand_more, size: 20, color: AdminTheme.sage),
                  ),
                  dropdownColor: AdminTheme.surface,
                  icon: const SizedBox.shrink(),
                ));
            final runningTimeField = _field('공연시간 (분)', isRequired: true,
                child: TextFormField(
                  controller: _runningTimeCtrl,
                  style: _inputStyle(),
                  decoration: _inputDecoration('예) 120'),
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
              decoration: _inputDecoration('예) 세종문화회관 대극장'),
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
              decoration: _inputDecoration(''),
            ));
        final plannerField = _field('기획',
            child: TextFormField(
              controller: _plannerCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration(''),
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

          // 적용 등급별 할인가 계산
          final grades = p.applicableGrades ?? _enabledGrades.toList();
          final gradePriceInfo = <String>[];
          for (final g in grades) {
            final ctrl = _gradePriceControllers[g];
            if (ctrl != null) {
              final base = int.tryParse(ctrl.text.replaceAll(',', '')) ?? 0;
              final disc = p.discountedPrice(base);
              gradePriceInfo.add('$g ${priceFormat.format(disc)}원');
            }
          }

          return Container(
            margin: EdgeInsets.only(bottom: i < _discountPolicies.length - 1 ? 8 : 0),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.2), width: 0.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 할인율 배지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AdminTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AdminTheme.error.withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '${(p.discountRate * 100).toInt()}%',
                    style: AdminTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AdminTheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 할인명
                      Text(
                        p.name,
                        style: AdminTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 적용 등급 + 할인가
                      Row(
                        children: [
                          ...grades.map((g) {
                            final color = _gradeColors[g] ?? AdminTheme.sage;
                            final ctrl = _gradePriceControllers[g];
                            final base = ctrl != null
                                ? (int.tryParse(ctrl.text.replaceAll(',', '')) ?? 0)
                                : 0;
                            final disc = p.discountedPrice(base);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Row(
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
                                  const SizedBox(width: 3),
                                  Text(
                                    '$g ${priceFormat.format(disc)}원',
                                    style: AdminTheme.sans(
                                      fontSize: 11,
                                      color: AdminTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (p.applicableGrades == null)
                            Text(
                              '(전체)',
                              style: AdminTheme.sans(
                                fontSize: 10,
                                color: AdminTheme.textTertiary,
                              ),
                            ),
                        ],
                      ),
                      // 설명
                      if (p.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          p.description!,
                          style: AdminTheme.sans(
                            fontSize: 10,
                            color: AdminTheme.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // 삭제
                IconButton(
                  onPressed: () => setState(() => _discountPolicies.removeAt(i)),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AdminTheme.textTertiary),
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
              color: AdminTheme.surface,
              border: Border.all(
                color: AdminTheme.gold.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded,
                    size: 16, color: AdminTheme.gold),
                const SizedBox(width: 6),
                Text(
                  'ADD DISCOUNT POLICY',
                  style: AdminTheme.label(
                    fontSize: 10,
                    color: AdminTheme.gold,
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
              decoration: _inputDecoration(
                  '예) 공연 시작 후 입장 불가\n     취소/환불은 공연 3일 전까지 가능'),
              maxLines: 3,
              minLines: 2,
            )),
        const SizedBox(height: 20),

        // 예매 관련 문의
        _field('예매 관련 문의',
            child: TextFormField(
              controller: _inquiryInfoCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration(
                  '예) 예매 관련 문의: 010-1234-5678 (티켓 예매 담당)'),
              maxLines: 2,
              minLines: 1,
            )),
        const SizedBox(height: 20),

        // 최대 구매 수량
        _field('1인 최대 구매 수량',
            child: TextFormField(
              controller: _maxTicketsCtrl,
              style: _inputStyle(),
              decoration: _inputDecoration('0 = 무제한'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            )),

        // 잔여석 표시 토글 — editorial bordered container
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.25), width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '잔여석 표시',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '예매 화면에 남은 좌석 수를 표시합니다',
                      style: AdminTheme.sans(
                        fontSize: 11,
                        color: AdminTheme.sage.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _showRemainingSeats,
                onChanged: (v) => setState(() => _showRemainingSeats = v),
                activeTrackColor: AdminTheme.gold,
                activeThumbColor: AdminTheme.onAccent,
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
                  border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.4), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 15, color: AdminTheme.gold),
                    const SizedBox(width: 6),
                    Text('SEARCH',
                        style: AdminTheme.label(
                          fontSize: 9,
                          color: AdminTheme.gold,
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
          backgroundColor: AdminTheme.error,
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
    // 적용 좌석 등급 (기본: 전체 선택)
    final selectedGrades = Set<String>.from(_enabledGrades);
    bool allGrades = true;

    showAnimatedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AdminTheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
            title: Text(
              '할인 정책 추가',
              style: AdminTheme.serif(
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
                  Text('할인 유형',
                      style: AdminTheme.sans(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Discount Type',
                      style: AdminTheme.label(
                          fontSize: 8, color: AdminTheme.sage)),
                  const SizedBox(height: 8),
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

                  // 적용 좌석 등급
                  Text('적용 좌석',
                      style: AdminTheme.sans(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Applicable Grades',
                      style: AdminTheme.label(
                          fontSize: 8, color: AdminTheme.sage)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 전체 등급 칩
                      GestureDetector(
                        onTap: () => setDialogState(() {
                          allGrades = !allGrades;
                          if (allGrades) {
                            selectedGrades.addAll(_enabledGrades);
                          } else {
                            selectedGrades.clear();
                          }
                        }),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: allGrades
                                  ? AdminTheme.gold.withValues(alpha: 0.12)
                                  : AdminTheme.background,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: allGrades
                                    ? AdminTheme.gold.withValues(alpha: 0.6)
                                    : AdminTheme.sage.withValues(alpha: 0.2),
                                width: allGrades ? 1 : 0.5,
                              ),
                            ),
                            child: Text(
                              '전체',
                              style: AdminTheme.label(
                                fontSize: 10,
                                color: allGrades
                                    ? AdminTheme.gold
                                    : AdminTheme.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 개별 등급 칩
                      ..._allGrades
                          .where((g) => _enabledGrades.contains(g))
                          .map((grade) {
                        final isOn =
                            allGrades || selectedGrades.contains(grade);
                        final color = _gradeColors[grade]!;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: GestureDetector(
                            onTap: () => setDialogState(() {
                              if (allGrades) {
                                allGrades = false;
                                selectedGrades
                                  ..clear()
                                  ..addAll(_enabledGrades)
                                  ..remove(grade);
                              } else if (isOn) {
                                selectedGrades.remove(grade);
                              } else {
                                selectedGrades.add(grade);
                                if (selectedGrades
                                    .containsAll(_enabledGrades)) {
                                  allGrades = true;
                                }
                              }
                            }),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isOn
                                      ? color.withValues(alpha: 0.12)
                                      : AdminTheme.background,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isOn
                                        ? color.withValues(alpha: 0.6)
                                        : AdminTheme.sage
                                            .withValues(alpha: 0.2),
                                    width: isOn ? 1 : 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isOn
                                            ? color
                                            : color.withValues(alpha: 0.3),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      grade,
                                      style: AdminTheme.label(
                                        fontSize: 10,
                                        color: isOn
                                            ? color
                                            : AdminTheme.textTertiary,
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
                  const SizedBox(height: 16),

                  // 할인명 (공개용)
                  Text('할인명',
                      style: AdminTheme.sans(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('이 이름이 예매 화면에 그대로 표시됩니다',
                      style: AdminTheme.sans(
                          fontSize: 10, color: AdminTheme.textTertiary)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: nameCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration(
                      type == 'bulk'
                          ? '예) 2매 이상 구매시 20% 할인'
                          : '예) 국가유공자(동반1인) 50%',
                    ),
                  ),

                  if (type == 'bulk') ...[
                    const SizedBox(height: 12),
                    Text('최소 수량',
                        style: AdminTheme.sans(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Min Quantity',
                        style: AdminTheme.label(
                            fontSize: 8, color: AdminTheme.sage)),
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
                  Text('할인율',
                      style: AdminTheme.sans(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Discount Rate',
                      style: AdminTheme.label(
                          fontSize: 8, color: AdminTheme.sage)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: rateCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration(null).copyWith(
                      suffixText: '%',
                      suffixStyle: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.gold,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),

                  const SizedBox(height: 12),
                  Text('설명 (선택)',
                      style: AdminTheme.sans(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('예매 화면 하단에 부가 설명으로 표시됩니다',
                      style: AdminTheme.sans(
                          fontSize: 10, color: AdminTheme.textTertiary)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: descCtrl,
                    style: _inputStyle(),
                    decoration: _inputDecoration(
                      '예) 2매 이상만 예매 가능. 전체취소만 가능.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('취소',
                    style: AdminTheme.sans(color: AdminTheme.textTertiary)),
              ),
              FilledButton(
                onPressed: () {
                  final rate = int.tryParse(rateCtrl.text) ?? 0;
                  if (nameCtrl.text.trim().isEmpty || rate <= 0 || rate > 100) {
                    return;
                  }
                  if (!allGrades && selectedGrades.isEmpty) return;

                  final name = nameCtrl.text.trim();
                  final qty = type == 'bulk'
                      ? (int.tryParse(qtyCtrl.text) ?? 2)
                      : 1;
                  final desc = descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim();

                  setState(() {
                    _discountPolicies.add(DiscountPolicy(
                      name: name,
                      type: type,
                      minQuantity: qty,
                      discountRate: rate / 100.0,
                      description: desc,
                      applicableGrades: allGrades
                          ? null
                          : selectedGrades.toList(),
                    ));
                  });
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AdminTheme.gold,
                  foregroundColor: AdminTheme.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text('추가',
                    style: AdminTheme.sans(fontWeight: FontWeight.w700, color: AdminTheme.onAccent)),
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
                ? AdminTheme.gold.withValues(alpha: 0.06)
                : AdminTheme.background,
            border: Border.all(
              color: selected
                  ? AdminTheme.gold.withValues(alpha: 0.4)
                  : AdminTheme.sage.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? AdminTheme.gold : AdminTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AdminTheme.gold : AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPicker() {
    // 업로드 중 (bytes 미리보기 + 프로그레스)
    if (_posterBytes != null && _isUploadingPoster) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.5), width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Opacity(
              opacity: 0.5,
              child: Image.memory(
                _posterBytes!,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AdminTheme.gold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '업로드 중...',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.gold,
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

    // 서버에 업로드 완료된 포스터 URL
    if (_posterUrl != null && _posterUrl!.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AdminTheme.gold, width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.network(
              _posterUrl!,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                color: AdminTheme.surface,
                child: Center(
                  child: Text('이미지 로드 실패',
                      style: AdminTheme.sans(color: AdminTheme.textTertiary, fontSize: 13)),
                ),
              ),
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
                      _posterUrl = null;
                      _posterBytes = null;
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
          color: AdminTheme.surface,
          border: Border.all(
            color: AdminTheme.sage.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: AdminTheme.sage.withValues(alpha: 0.3),
            strokeWidth: 0.5,
            dashWidth: 6,
            dashSpace: 4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 28, color: AdminTheme.sage.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(
                'Drag or tap to upload artwork',
                style: AdminTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AdminTheme.sage,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Recommended: 1000x1440px (JPG, PNG)',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.sage.withValues(alpha: 0.5),
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
                style: AdminTheme.label(
                  fontSize: 8,
                  color: Colors.white,
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAMPHLET PICKER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPamphletPicker() {
    final totalCount = _pamphletUrls.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 업로드된 팜플렛 이미지 (URL)
        if (_pamphletUrls.isNotEmpty) ...[
          SizedBox(
            height: 140,
            child: ReorderableListView.builder(
              scrollController: _pamphletScrollCtrl,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: _pamphletUrls.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final url = _pamphletUrls.removeAt(oldIndex);
                  _pamphletUrls.insert(newIndex, url);
                });
              },
              itemBuilder: (context, index) {
                final url = _pamphletUrls[index];
                return ReorderableDragStartListener(
                  key: ValueKey(url),
                  index: index,
                  child: Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AdminTheme.sage.withValues(alpha: 0.2),
                          width: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(url, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                  color: AdminTheme.surface,
                                  child: const Icon(Icons.broken_image_rounded,
                                      size: 24, color: AdminTheme.textTertiary),
                                )),
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AdminTheme.background.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text('${index + 1}',
                                style: AdminTheme.label(
                                  fontSize: 9,
                                  color: AdminTheme.textPrimary,
                                )),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(
                                () => _pamphletUrls.removeAt(index)),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color:
                                    AdminTheme.error.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '드래그하여 순서 변경',
                  style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                  ),
                ),
                Text(
                  '$totalCount/$_maxPamphlets장',
                  style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 업로드 중 표시
        if (_isUploadingPamphlet) ...[
          Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.2), width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AdminTheme.gold),
                ),
                const SizedBox(width: 10),
                Text(
                  '업로드 중...',
                  style: AdminTheme.sans(fontSize: 12, color: AdminTheme.gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 추가 버튼
        if (totalCount < _maxPamphlets && !_isUploadingPamphlet)
          InkWell(
            onTap: _pickPamphletImages,
            child: Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                border: Border.all(
                  color: AdminTheme.sage.withValues(alpha: 0.25),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: AdminTheme.sage.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                  dashWidth: 6,
                  dashSpace: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 20,
                        color: AdminTheme.sage.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Text(
                      totalCount == 0
                          ? '팜플렛 이미지 추가'
                          : '추가 ($totalCount/$_maxPamphlets)',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        color: AdminTheme.sage,
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

  Future<void> _pickPamphletImages() async {
    try {
      final remaining = _maxPamphlets - _pamphletUrls.length;
      if (remaining <= 0) return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isUploadingPamphlet = true);

      final userId = ref.read(authServiceProvider).currentUser?.uid ?? 'unknown';

      // 이름순 정렬 후 업로드
      final sortedFiles = result.files.take(remaining).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      for (final file in sortedFiles) {
        if (file.bytes == null) continue;

        var bytes = file.bytes!;
        final name = file.name;

        // 3MB 초과 시 거부
        if (bytes.length > _maxPamphletBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$name: 3MB 초과 (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB). 이미지를 줄여주세요.'),
                backgroundColor: AdminTheme.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            );
          }
          continue;
        }

        // 서버에 즉시 업로드
        final url = await ref.read(storageServiceProvider).uploadDraftImage(
              bytes: bytes,
              userId: userId,
              fileName: name,
              type: 'pamphlet',
            );
        if (mounted) {
          setState(() => _pamphletUrls.add(url));
        }
      }

      if (mounted) setState(() => _isUploadingPamphlet = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPamphlet = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('팜플렛 업로드 실패: $e'),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
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
              style: AdminTheme.label(
                fontSize: 10,
                color: AdminTheme.sage,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.error,
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
      hintStyle: AdminTheme.sans(
        fontSize: 13,
        color: AdminTheme.sage.withValues(alpha: 0.4),
      ),
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: AdminTheme.sage.withValues(alpha: 0.4), width: 0.5),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AdminTheme.sage.withValues(alpha: 0.4), width: 0.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AdminTheme.gold, width: 1),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AdminTheme.error, width: 1),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AdminTheme.error, width: 1.5),
      ),
    );
  }

  TextStyle _inputStyle() {
    return AdminTheme.sans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AdminTheme.textPrimary,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pickDateTime(
      DateTime current, ValueChanged<DateTime> onChanged) async {
    final result = await showPremiumDateTimePicker(
      context: context,
      initialDateTime: current,
    );
    if (result != null && mounted) {
      onChanged(result);
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
                backgroundColor: AdminTheme.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            );
          }
          return;
        }
        // 미리보기 즉시 표시
        setState(() {
          _posterBytes = bytes;
          _isUploadingPoster = true;
        });

        // 서버에 즉시 업로드
        final userId = ref.read(authServiceProvider).currentUser?.uid ?? 'unknown';
        final url = await ref.read(storageServiceProvider).uploadDraftImage(
              bytes: bytes,
              userId: userId,
              fileName: result.files.single.name,
              type: 'poster',
            );

        if (mounted) {
          setState(() {
            _posterUrl = url;
            _posterBytes = null; // bytes 해제, URL로 표시 전환
            _isUploadingPoster = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPoster = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('포스터 업로드 실패: $e'),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBMIT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _submitEvent() async {
    if (_isSubmitting) return; // 중복 등록 방지
    if (!_formKey.currentState!.validate()) {
      _showError('공연명을 입력해주세요');
      return;
    }
    if (!_isStanding && !_isEditMode && _seatMapData == null) {
      _showError('좌석 배치를 선택해주세요');
      return;
    }
    if (!_isStanding && _enabledGrades.isEmpty) {
      _showError('사용할 좌석 등급을 1개 이상 선택해주세요');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitProgress = 0.0;
      _submitStage = '준비 중...';
    });

    try {
      // 활성화된 등급별 가격 맵
      final priceByGrade = <String, int>{};
      if (_isStanding) {
        // 스탠딩 모드: 일반 등급 1개
        final standingPrice = int.tryParse(
            (_gradePriceControllers['일반']?.text ?? '').replaceAll(',', '')) ?? 50000;
        priceByGrade['일반'] = standingPrice;
      } else {
        for (final grade in _enabledGrades) {
          final ctrl = _gradePriceControllers[grade];
          if (ctrl != null) {
            priceByGrade[grade] =
                int.tryParse(ctrl.text.replaceAll(',', '')) ?? SeatMapParser.getDefaultPrice(grade);
          }
        }
      }

      // 기본가격 = 최저 등급 가격
      final basePrice = priceByGrade.values.isNotEmpty
          ? priceByGrade.values.reduce((a, b) => a < b ? a : b)
          : 55000;

      final saleEndAt = _startAt.subtract(const Duration(hours: 1));
      final revealAt = _startAt.subtract(const Duration(hours: 1));

      // ════════════════════════════════════════════════════════════════════
      // 수정 모드
      // ════════════════════════════════════════════════════════════════════
      if (_isEditMode) {
        final eventId = widget.editEventId!;
        if (mounted) setState(() { _submitProgress = 0.10; _submitStage = '공연 정보 수정 중...'; });

        final updateData = <String, dynamic>{
          'title': _titleCtrl.text.trim(),
          'description': _descriptionCtrl.text.trim(),
          'startAt': Timestamp.fromDate(_startAt),
          'saleEndAt': Timestamp.fromDate(saleEndAt),
          'revealAt': Timestamp.fromDate(revealAt),
          'price': basePrice,
          'maxTicketsPerOrder': int.tryParse(_maxTicketsCtrl.text) ?? 0,
          'category': _category,
          'venueName': _venueNameCtrl.text.trim().isEmpty
              ? null
              : _venueNameCtrl.text.trim(),
          'venueAddress': _venueAddressCtrl.text.trim().isEmpty
              ? null
              : _venueAddressCtrl.text.trim(),
          'runningTime': int.tryParse(_runningTimeCtrl.text) ?? 120,
          'ageLimit': _ageLimit,
          'cast': _castCtrl.text.trim().isEmpty ? null : _castCtrl.text.trim(),
          'organizer': _organizerCtrl.text.trim().isEmpty
              ? null
              : _organizerCtrl.text.trim(),
          'planner': _plannerCtrl.text.trim().isEmpty
              ? null
              : _plannerCtrl.text.trim(),
          'notice':
              _noticeCtrl.text.trim().isEmpty ? null : _noticeCtrl.text.trim(),
          'inquiryInfo':
              _inquiryInfoCtrl.text.trim().isEmpty ? null : _inquiryInfoCtrl.text.trim(),
          'discount': _discountPolicies.isNotEmpty
              ? _discountPolicies.map((p) => p.name).join(', ')
              : null,
          'priceByGrade': priceByGrade.isNotEmpty ? priceByGrade : null,
          'discountPolicies':
              _discountPolicies.isNotEmpty
                  ? _discountPolicies.map((p) => p.toMap()).toList()
                  : null,
          'showRemainingSeats': _showRemainingSeats,
          'isStanding': _isStanding,
          'tags': _selectedTags.isNotEmpty ? _selectedTags.toList() : [],
          if (_hallId != null) 'hallId': _hallId,
        };

        // 포스터/팜플렛은 이미 서버에 업로드되어 URL 보유
        updateData['imageUrl'] = _posterUrl;
        updateData['pamphletUrls'] = _pamphletUrls.isNotEmpty ? _pamphletUrls : null;

        // 스탠딩 모드: 수용 인원 업데이트
        if (_isStanding) {
          final capacity = int.tryParse(_standingCapacityCtrl.text) ?? 100;
          updateData['totalSeats'] = capacity;
          updateData['availableSeats'] = capacity;
        }

        await ref.read(eventRepositoryProvider).updateEvent(eventId, updateData);
        if (mounted) setState(() { _submitProgress = 0.50; _submitStage = '좌석 확인 중...'; });

        // 좌석이 없으면 자동 생성 (스탠딩이 아닌 경우)
        final existingSeats = await ref.read(seatRepositoryProvider).getSeatsByEvent(eventId);
        if (!_isStanding && existingSeats.isEmpty && _seatMapData != null) {
          if (mounted) setState(() { _submitProgress = 0.60; _submitStage = '좌석 생성 중...'; });
          await _createSeatsFromSeatMap(eventId);
          // totalSeats 업데이트
          var totalSeats = 0;
          for (final floor in _seatMapData!.floors) {
            for (final block in floor.blocks) {
              if (block.grade == null || _enabledGrades.contains(block.grade)) {
                totalSeats += block.totalSeats;
              }
            }
          }
          await ref.read(eventRepositoryProvider).updateEvent(eventId, {
            'totalSeats': totalSeats,
            'availableSeats': totalSeats,
          });
        }
        if (mounted) setState(() => _submitProgress = 0.90);

        if (mounted) setState(() { _submitProgress = 1.0; _submitStage = '수정 완료!'; });

        if (mounted) {
          _showEditSuccessDialog(eventId, _titleCtrl.text.trim());
        }
        return;
      }

      // ════════════════════════════════════════════════════════════════════
      // 신규 등록 모드
      // ════════════════════════════════════════════════════════════════════

      // 좌석 수 계산
      var totalSeats = 0;
      if (_isStanding) {
        totalSeats = int.tryParse(_standingCapacityCtrl.text) ?? 100;
      } else {
        for (final floor in _seatMapData!.floors) {
          for (final block in floor.blocks) {
            if (block.grade == null || _enabledGrades.contains(block.grade)) {
              totalSeats += block.totalSeats;
            }
          }
        }
      }

      // 판매 설정 자동 계산
      final now = DateTime.now();
      final saleStartAt = now;

      // ── 다회 공연 설정
      final isMulti = _isMultiSession && _sessionDates.isNotEmpty;
      final sessionCount = isMulti ? 1 + _sessionDates.length : 1;
      final seriesId = isMulti
          ? 'S${now.millisecondsSinceEpoch.toRadixString(36)}'
          : null;
      final allStartDates = [_startAt, ..._sessionDates];
      final createdEventIds = <String>[];

      for (var si = 0; si < sessionCount; si++) {
        final sessionStartAt = allStartDates[si];
        final sessionRevealAt =
            sessionStartAt.subtract(const Duration(hours: 1));
        final sessionSaleEndAt =
            sessionStartAt.subtract(const Duration(hours: 1));
        final progressBase = si / sessionCount;
        final progressStep = 1.0 / sessionCount;

        final sessionTitle = isMulti
            ? '${_titleCtrl.text.trim()} [${si + 1}회]'
            : _titleCtrl.text.trim();

        final event = Event(
          id: '',
          venueId: _selectedVenue?.id ?? '',
          title: sessionTitle,
          description: _descriptionCtrl.text.trim(),
          imageUrl: null,
          startAt: sessionStartAt,
          revealAt: sessionRevealAt,
          saleStartAt: saleStartAt,
          saleEndAt: sessionSaleEndAt,
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
          inquiryInfo: _inquiryInfoCtrl.text.trim().isEmpty
              ? null
              : _inquiryInfoCtrl.text.trim(),
          discount: _discountPolicies.isNotEmpty
              ? _discountPolicies.map((p) => p.name).join(', ')
              : null,
          priceByGrade: priceByGrade.isNotEmpty ? priceByGrade : null,
          discountPolicies:
              _discountPolicies.isNotEmpty ? _discountPolicies : null,
          showRemainingSeats: _showRemainingSeats,
          has360View: _selectedVenue?.hasSeatView ?? false,
          tags: _selectedTags.toList(),
          seriesId: seriesId,
          sessionNumber: si + 1,
          totalSessions: sessionCount,
          isStanding: _isStanding,
          hallId: _hallId,
        );

        // ── Step 1: 이벤트 생성
        if (mounted) setState(() {
          _submitProgress = progressBase + progressStep * 0.1;
          _submitStage = isMulti
              ? '${si + 1}회차 공연 등록 중...'
              : '공연 정보 등록 중...';
        });
        final eventId =
            await ref.read(eventRepositoryProvider).createEvent(event);
        createdEventIds.add(eventId);

        // ── Step 2: 포스터/팜플렛 URL 저장
        if (_posterUrl != null || _pamphletUrls.isNotEmpty) {
          if (mounted) setState(() {
            _submitProgress = progressBase + progressStep * 0.3;
            _submitStage = isMulti
                ? '${si + 1}회차 이미지 저장 중...'
                : '이미지 정보 저장 중...';
          });
          final imageData = <String, dynamic>{};
          if (_posterUrl != null) imageData['imageUrl'] = _posterUrl;
          if (_pamphletUrls.isNotEmpty) {
            imageData['pamphletUrls'] = _pamphletUrls;
          }
          await ref
              .read(eventRepositoryProvider)
              .updateEvent(eventId, imageData);
        }

        // ── Step 3: 좌석 생성 (스탠딩이 아닌 경우)
        if (!_isStanding) {
          if (mounted) setState(() {
            _submitProgress = progressBase + progressStep * 0.5;
            _submitStage = isMulti
                ? '${si + 1}회차 좌석 생성 중...'
                : '좌석 생성 중...';
          });
          await _createSeatsFromSeatMap(eventId);
        }
      }

      if (mounted) setState(() { _submitProgress = 1.0; _submitStage = '완료!'; });

      // 등록 성공 → 임시저장 삭제
      await _clearDraft();

      if (mounted) {
        if (isMulti) {
          _showSuccessDialog(
            createdEventIds.first,
            _titleCtrl.text.trim(),
            totalSeats * sessionCount,
            sessionCount: sessionCount,
          );
        } else {
          _showSuccessDialog(
              createdEventIds.first, _titleCtrl.text.trim(), totalSeats);
        }
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

  void _showSuccessDialog(String eventId, String title, int totalSeats,
      {int sessionCount = 1}) {
    final eventPath = '/event/$eventId';
    final fullUrl = kIsWeb ? '${Uri.base.origin}$eventPath' : eventPath;
    final fmt = NumberFormat('#,###');

    showAnimatedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnimatedDialogContent(
        padding: const EdgeInsets.all(28),
        backgroundColor: AdminTheme.surface,
        borderColor: AdminTheme.border,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                // ── 체크 아이콘 ──
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AdminTheme.goldGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AdminTheme.gold.withValues(alpha: 0.3),
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
                  style: AdminTheme.serif(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AdminTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.gold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  sessionCount > 1
                    ? '${sessionCount}회차 · 총 ${fmt.format(totalSeats)}석 · 즉시 판매 시작'
                    : '총 ${fmt.format(totalSeats)}석 · 즉시 판매 시작',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textTertiary,
                  ),
                ),

                const SizedBox(height: 20),

                // ── 링크 복사 영역 ──
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AdminTheme.background,
                    border: Border.all(color: AdminTheme.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded,
                          size: 16, color: AdminTheme.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fullUrl,
                          style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textSecondary,
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
                              backgroundColor: AdminTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text(
                          'COPY',
                          style: AdminTheme.label(
                            fontSize: 9,
                            color: AdminTheme.gold,
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
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      'VIEW EVENT',
                      style: AdminTheme.serif(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.onAccent,
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
                          const BorderSide(color: AdminTheme.border, width: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      'DASHBOARD',
                      style: AdminTheme.label(
                        fontSize: 10,
                        color: AdminTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showEditSuccessDialog(String eventId, String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AdminTheme.gold.withValues(alpha: 0.15),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminTheme.success.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AdminTheme.success.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(Icons.check_rounded,
                      color: AdminTheme.success, size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  '수정 완료',
                  style: AdminTheme.serif(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AdminTheme.gold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '공연 정보가 성공적으로 업데이트되었습니다.',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.go('/');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.textPrimary,
                      side: BorderSide(
                        color: AdminTheme.border,
                        width: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      'DASHBOARD',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.textSecondary,
                        letterSpacing: 1.5,
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
        backgroundColor: AdminTheme.error,
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

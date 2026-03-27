import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:http/http.dart' as http;
import '../../app/admin_theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/infrastructure/firebase/functions_service.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/data/models/venue.dart';
import 'excel_seat_upload_helper.dart';

// =============================================================================
// 네이버 티켓 전용 위자드 — 스텝 바이 스텝 흐름
// =============================================================================

const _gradeOrder = ['VIP', 'R', 'S', 'A'];

// 카카오 우편번호 서비스 JS interop
@JS('openKakaoPostcode')
external JSPromise<JSString> _openKakaoPostcode();

class NaverTicketWizardScreen extends ConsumerStatefulWidget {
  final String? editEventId;
  const NaverTicketWizardScreen({super.key, this.editEventId});

  @override
  ConsumerState<NaverTicketWizardScreen> createState() =>
      _NaverTicketWizardScreenState();
}

class _NaverTicketWizardScreenState
    extends ConsumerState<NaverTicketWizardScreen> {
  int _currentStep = 0;
  String? _createdEventId;

  // Step 1: 공연 등록
  final _titleCtrl = TextEditingController();
  final _venueNameCtrl = TextEditingController();
  DateTime _startAt = DateTime.now().add(const Duration(days: 7));
  final _enabledGrades = <String>{'VIP', 'R', 'S', 'A'};
  final _gradePriceControllers = <String, TextEditingController>{
    'VIP': TextEditingController(text: '110000'),
    'R': TextEditingController(text: '88000'),
    'S': TextEditingController(text: '66000'),
    'A': TextEditingController(text: '44000'),
  };
  Uint8List? _posterBytes;
  String? _existingImageUrl; // 이미 업로드된 포스터 URL
  final _naverUrlCtrl = TextEditingController(); // 네이버 판매 URL
  String? _venueAddress; // 공연장 주소
  bool _naverOnly = true; // 네이버 전용 (새 봇) vs 놀티켓 연계 (기존 봇)
  bool _showExistingEvents = false;
  bool _isCreatingEvent = false;

  // Step 2: 좌석 등록
  ParsedSeatData? _seatData;
  ExcelParseResult? _parseResult;
  bool _isParsingSeat = false;
  bool _isUploadingSeats = false;
  bool _seatsUploaded = false;
  String? _seatError;
  bool _isDragging = false;

  // Step 3: 주문 입력
  final _orderIdCtrl = TextEditingController();
  final _buyerNameCtrl = TextEditingController();
  final _buyerPhoneCtrl = TextEditingController();
  String _selectedGrade = 'S';
  int _quantity = 1;
  bool _isCreatingOrder = false;

  @override
  void initState() {
    super.initState();
    if (widget.editEventId != null) {
      _createdEventId = widget.editEventId;
      _loadExistingEvent(widget.editEventId!);
    }
  }

  Future<void> _loadExistingEvent(String eventId) async {
    final doc = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .get();
    if (!doc.exists || !mounted) return;
    final d = doc.data()!;
    setState(() {
      _titleCtrl.text = d['title'] ?? '';
      _venueNameCtrl.text = d['venueName'] ?? '';
      _venueAddress = d['venueAddress'];
      _startAt = (d['startAt'] as Timestamp).toDate();
      if (d['naverProductUrl'] != null) {
        _naverUrlCtrl.text = d['naverProductUrl'];
      }
      _naverOnly = d['naverOnly'] ?? false;
      _existingImageUrl = d['imageUrl'];
      if (d['priceByGrade'] != null) {
        final prices = Map<String, dynamic>.from(d['priceByGrade']);
        _enabledGrades.clear();
        for (final e in prices.entries) {
          _enabledGrades.add(e.key);
          _gradePriceControllers[e.key]?.text = e.value.toString();
        }
      }
      // 편집 모드: Step 0 (공연 정보)부터 시작
      _currentStep = 0;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _venueNameCtrl.dispose();
    _naverUrlCtrl.dispose();
    for (final c in _gradePriceControllers.values) {
      c.dispose();
    }
    _orderIdCtrl.dispose();
    _buyerNameCtrl.dispose();
    _buyerPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          // ── Top bar ──
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              bottom: 12,
            ),
            decoration: const BoxDecoration(
              color: AdminTheme.surface,
              border: Border(
                bottom: BorderSide(color: AdminTheme.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/'),
                  icon: const Icon(
                    Icons.west,
                    color: AdminTheme.textPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Naver Ticket',
                  style: AdminTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                // Step indicator
                _StepIndicator(
                  currentStep: _currentStep,
                  labels: const ['공연', '좌석', '주문', '현황'],
                  onStepTap: widget.editEventId != null
                      ? (step) => setState(() => _currentStep = step)
                      : null,
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(child: _buildStep()),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1EventRegistration();
      case 1:
        return _buildStep2SeatUpload();
      case 2:
        return _buildStep3OrderInput();
      case 3:
        return _buildStep4Status();
      default:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Step 1: 공연 등록
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStep1EventRegistration() {
    return SingleChildScrollView(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step 1',
                style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.editEventId != null ? '공연 수정' : '공연 등록',
                style: AdminTheme.serif(fontSize: 22),
              ),
              const SizedBox(height: 4),
              Text(
                widget.editEventId != null
                    ? '공연 정보를 수정하세요'
                    : '공연 기본 정보를 입력하세요',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 32),

              // 기존 공연 선택 (새로 만들 때만)
              if (widget.editEventId == null) ...[
                _buildExistingEventSelector(),
                const SizedBox(height: 16),
              ],

              // 공연 정보 폼
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.editEventId == null)
                      Text(
                        '새 공연 등록',
                        style: AdminTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 20),

                    // 공연명
                    TextField(
                      controller: _titleCtrl,
                      style: AdminTheme.sans(fontSize: 14),
                      decoration: const InputDecoration(labelText: '공연명 *'),
                    ),
                    const SizedBox(height: 16),

                    // 네이버 판매 URL
                    TextField(
                      controller: _naverUrlCtrl,
                      style: AdminTheme.sans(fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: '네이버 판매 URL',
                        hintText: 'https://smartstore.naver.com/...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                        ),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),

                    // 장소 (카카오 주소 검색)
                    TextField(
                      controller: _venueNameCtrl,
                      style: AdminTheme.sans(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '공연장',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, size: 20),
                          tooltip: '주소 검색',
                          onPressed: () => _showVenueSearchDialog(),
                        ),
                      ),
                    ),
                    if (_venueAddress != null && _venueAddress!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: AdminTheme.gold,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _venueAddress!,
                                style: AdminTheme.sans(
                                  fontSize: 12,
                                  color: AdminTheme.textSecondary,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _venueAddress = null),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: AdminTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // 날짜/시간
                    Row(
                      children: [
                        Text(
                          '공연 일시:',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startAt,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date == null) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(_startAt),
                              builder: (context, child) {
                                return MediaQuery(
                                  data: MediaQuery.of(context).copyWith(
                                    alwaysUse24HourFormat: true,
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (time == null) return;
                            setState(() {
                              _startAt = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AdminTheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AdminTheme.border,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              DateFormat(
                                'yyyy.MM.dd (E) HH:mm',
                                'ko_KR',
                              ).format(_startAt),
                              style: AdminTheme.sans(
                                fontSize: 13,
                                color: AdminTheme.gold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AdminTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AdminTheme.gold.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '운영 정책: 좌석과 QR은 공연 시작 2시간 전에 자동 공개됩니다. 긴급 공개가 필요하면 주문 화면 상단의 좌석 공개 버튼으로 즉시 앞당길 수 있습니다.',
                        style: AdminTheme.sans(
                          fontSize: 11,
                          color: AdminTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 포스터
                    Row(
                      children: [
                        Text(
                          '포스터:',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_posterBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              _posterBytes!,
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          )
                        else if (_existingImageUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              _existingImageUrl!,
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed: _pickPoster,
                            icon: const Icon(Icons.image_outlined, size: 16),
                            label: const Text('업로드'),
                            style: TextButton.styleFrom(
                              foregroundColor: AdminTheme.gold,
                            ),
                          ),
                        if (_posterBytes != null || _existingImageUrl != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _pickPoster,
                            icon: const Icon(
                              Icons.edit,
                              size: 16,
                              color: AdminTheme.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 공연 유형 (네이버 전용 vs 놀티켓 연계)
                    Text(
                      '공연 유형',
                      style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _naverOnly = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _naverOnly
                                    ? AdminTheme.gold.withValues(alpha: 0.12)
                                    : AdminTheme.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _naverOnly
                                      ? AdminTheme.gold
                                      : AdminTheme.border,
                                  width: _naverOnly ? 1.5 : 0.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.storefront_rounded,
                                    size: 20,
                                    color: _naverOnly
                                        ? AdminTheme.gold
                                        : AdminTheme.textTertiary,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '네이버 전용',
                                    style: AdminTheme.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _naverOnly
                                          ? AdminTheme.gold
                                          : AdminTheme.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '좌석봇 자동배정',
                                    style: AdminTheme.sans(
                                      fontSize: 9,
                                      color: _naverOnly
                                          ? AdminTheme.gold.withValues(
                                              alpha: 0.7,
                                            )
                                          : AdminTheme.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _naverOnly = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: !_naverOnly
                                    ? AdminTheme.gold.withValues(alpha: 0.12)
                                    : AdminTheme.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: !_naverOnly
                                      ? AdminTheme.gold
                                      : AdminTheme.border,
                                  width: !_naverOnly ? 1.5 : 0.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.link_rounded,
                                    size: 20,
                                    color: !_naverOnly
                                        ? AdminTheme.gold
                                        : AdminTheme.textTertiary,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '놀티켓 연계',
                                    style: AdminTheme.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: !_naverOnly
                                          ? AdminTheme.gold
                                          : AdminTheme.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '기존 봇 처리',
                                    style: AdminTheme.sans(
                                      fontSize: 9,
                                      color: !_naverOnly
                                          ? AdminTheme.gold.withValues(
                                              alpha: 0.7,
                                            )
                                          : AdminTheme.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 등급별 가격
                    Text(
                      '등급별 가격',
                      style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _gradeOrder.map((grade) {
                        final enabled = _enabledGrades.contains(grade);
                        return SizedBox(
                          width: 130,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: enabled,
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _enabledGrades.add(grade);
                                    } else {
                                      _enabledGrades.remove(grade);
                                    }
                                  }),
                                  activeColor: AdminTheme.gold,
                                  side: const BorderSide(
                                    color: AdminTheme.textTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                grade,
                                style: AdminTheme.sans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: enabled
                                      ? AdminTheme.textPrimary
                                      : AdminTheme.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _gradePriceControllers[grade],
                                  enabled: enabled,
                                  style: AdminTheme.sans(fontSize: 12),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    prefixText: '₩',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // 등록/수정 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isCreatingEvent
                            ? null
                            : (widget.editEventId != null
                                ? _updateEvent
                                : _createEvent),
                        child: _isCreatingEvent
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AdminTheme.onAccent,
                                ),
                              )
                            : Text(widget.editEventId != null
                                ? '공연 수정'
                                : '공연 등록'),
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

  Widget _buildExistingEventSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .orderBy('startAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final events = snapshot.data!.docs;
        if (events.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showExistingEvents = !_showExistingEvents),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Text(
                      '기존 공연 선택',
                      style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${events.length})',
                      style: AdminTheme.sans(fontSize: 12, color: AdminTheme.textTertiary),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _showExistingEvents ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AdminTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  children: events.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final title = d['title'] as String? ?? '';
                    final venue = d['venueName'] as String? ?? '';
                    final startAt = (d['startAt'] as Timestamp?)?.toDate();
                    final dateStr = startAt != null
                        ? DateFormat('MM.dd HH:mm').format(startAt)
                        : '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _createdEventId = doc.id;
                            _currentStep = 2;
                          });
                          _checkSeatsAndNavigate(doc.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AdminTheme.card,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AdminTheme.border, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: AdminTheme.sans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '$venue  ·  $dateStr',
                                      style: AdminTheme.sans(
                                        fontSize: 11,
                                        color: AdminTheme.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AdminTheme.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              crossFadeState: _showExistingEvents
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider(color: AdminTheme.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '또는',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AdminTheme.border)),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkSeatsAndNavigate(String eventId) async {
    final seatSnap = await FirebaseFirestore.instance
        .collection('seats')
        .where('eventId', isEqualTo: eventId)
        .limit(1)
        .get();
    if (!mounted) return;
    setState(() {
      _createdEventId = eventId;
      _currentStep = seatSnap.docs.isEmpty ? 1 : 2;
    });
  }

  Future<void> _pickPoster() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _posterBytes = result.files.single.bytes);
    }
  }

  // ── 카카오 우편번호 서비스로 주소 검색 (API 키 불필요) ──
  Future<void> _showVenueSearchDialog() async {
    try {
      final resultJs = await _openKakaoPostcode().toDart;
      final resultStr = resultJs.toDart;
      if (resultStr.isEmpty) return; // 사용자가 닫음

      final data = jsonDecode(resultStr) as Map<String, dynamic>;
      final roadAddress = data['roadAddress'] as String? ?? '';
      final address = data['address'] as String? ?? '';
      final buildingName = data['buildingName'] as String? ?? '';

      setState(() {
        // 건물명이 있으면 공연장명으로, 없으면 주소를 공연장명으로
        if (buildingName.isNotEmpty) {
          _venueNameCtrl.text = buildingName;
        }
        _venueAddress = roadAddress.isNotEmpty ? roadAddress : address;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('주소 검색 오류: $e')));
      }
    }
  }

  Future<void> _createEvent() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공연명을 입력하세요')));
      return;
    }

    setState(() => _isCreatingEvent = true);

    try {
      // 가격 맵
      final priceByGrade = <String, int>{};
      for (final grade in _enabledGrades) {
        final price =
            int.tryParse(_gradePriceControllers[grade]?.text ?? '0') ?? 0;
        priceByGrade[grade] = price;
      }
      final basePrice = priceByGrade.values.isEmpty
          ? 0
          : priceByGrade.values.reduce((a, b) => a < b ? a : b);

      // 포스터 업로드
      String? imageUrl;
      if (_posterBytes != null) {
        final storageRef = FirebaseStorage.instance.ref().child(
          'events/posters/${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await storageRef.putData(
          _posterBytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        imageUrl = await storageRef.getDownloadURL();
      }

      final event = Event(
        id: '',
        venueId: '',
        title: _titleCtrl.text.trim(),
        description: '',
        startAt: _startAt,
        revealAt: _startAt.subtract(const Duration(hours: 2)),
        saleStartAt: DateTime.now(),
        saleEndAt: _startAt.subtract(const Duration(hours: 1)),
        price: basePrice,
        maxTicketsPerOrder: 0,
        totalSeats: 0,
        availableSeats: 0,
        status: EventStatus.active,
        createdAt: DateTime.now(),
        imageUrl: imageUrl,
        venueName: _venueNameCtrl.text.trim(),
        venueAddress: _venueAddress,
        priceByGrade: priceByGrade,
      );

      final eventRepo = ref.read(eventRepositoryProvider);
      final eventId = await eventRepo.createEvent(event);

      // 네이버 전용 플래그 + 상품 URL 저장
      final extraFields = <String, dynamic>{'naverOnly': _naverOnly};
      if (_naverUrlCtrl.text.trim().isNotEmpty) {
        extraFields['naverProductUrl'] = _naverUrlCtrl.text.trim();
      }
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update(extraFields);

      if (!mounted) return;
      setState(() {
        _createdEventId = eventId;
        _isCreatingEvent = false;
        _currentStep = 1;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공연이 등록되었습니다')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingEvent = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _updateEvent() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('공연명을 입력하세요')));
      return;
    }

    setState(() => _isCreatingEvent = true);

    try {
      final eventId = _createdEventId!;

      // 가격 맵
      final priceByGrade = <String, int>{};
      for (final grade in _enabledGrades) {
        final price =
            int.tryParse(_gradePriceControllers[grade]?.text ?? '0') ?? 0;
        priceByGrade[grade] = price;
      }
      final basePrice = priceByGrade.values.isEmpty
          ? 0
          : priceByGrade.values.reduce((a, b) => a < b ? a : b);

      // 포스터 업로드 (새로 선택한 경우만)
      String? imageUrl = _existingImageUrl;
      if (_posterBytes != null) {
        final storageRef = FirebaseStorage.instance.ref().child(
          'events/posters/${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await storageRef.putData(
          _posterBytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        imageUrl = await storageRef.getDownloadURL();
      }

      // 이벤트 업데이트
      final updates = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'venueName': _venueNameCtrl.text.trim(),
        'startAt': Timestamp.fromDate(_startAt),
        'price': basePrice,
        'priceByGrade': priceByGrade,
        'naverOnly': _naverOnly,
      };
      if (_venueAddress != null) updates['venueAddress'] = _venueAddress;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (_naverUrlCtrl.text.trim().isNotEmpty) {
        updates['naverProductUrl'] = _naverUrlCtrl.text.trim();
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update(updates);

      if (!mounted) return;
      setState(() {
        _isCreatingEvent = false;
        _currentStep = 1;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('공연이 수정되었습니다')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingEvent = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Step 2: 좌석 등록
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStep2SeatUpload() {
    return SingleChildScrollView(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step 2',
                style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold),
              ),
              const SizedBox(height: 4),
              Text('좌석 등록', style: AdminTheme.serif(fontSize: 22)),
              const SizedBox(height: 4),
              Text(
                '네이버 스마트스토어의 좌석현황 엑셀을 업로드하세요',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 32),

              // 공연장에서 좌석 가져오기
              _buildVenueImportButton(),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '또는 엑셀 파일 직접 업로드',
                  style: AdminTheme.sans(
                    fontSize: 11,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 엑셀 업로드 영역 (드래그앤드롭 지원)
              DropTarget(
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
                onDragDone: (details) {
                  setState(() => _isDragging = false);
                  if (_isParsingSeat || details.files.isEmpty) return;
                  final file = details.files.first;
                  final ext = file.name.split('.').last.toLowerCase();
                  if (!['xlsx', 'xls'].contains(ext)) {
                    setState(() => _seatError = '.xlsx 또는 .xls 파일만 지원합니다.');
                    return;
                  }
                  file.readAsBytes().then((bytes) => _processExcelBytes(bytes, file.name));
                },
                child: GestureDetector(
                onTap: _isParsingSeat ? null : _pickSeatExcel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: _isDragging ? AdminTheme.gold.withValues(alpha: 0.08) : AdminTheme.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _isDragging
                          ? AdminTheme.gold
                          : _seatData != null
                          ? AdminTheme.success
                          : _seatError != null
                          ? AdminTheme.error
                          : AdminTheme.border,
                      width: _isDragging || _seatData != null || _seatError != null ? 1 : 0.5,
                    ),
                  ),
                  child: _isParsingSeat
                      ? Column(
                          children: [
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AdminTheme.gold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '좌석 배치도 분석 중...',
                              style: AdminTheme.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AdminTheme.gold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '엑셀 파싱 및 좌석 데이터 추출 중입니다',
                              style: AdminTheme.sans(
                                fontSize: 12,
                                color: AdminTheme.textTertiary,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Icon(
                              _seatData != null
                                  ? Icons.check_circle_rounded
                                  : _seatError != null
                                  ? Icons.error_outline_rounded
                                  : Icons.upload_file_rounded,
                              size: 36,
                              color: _seatData != null
                                  ? AdminTheme.success
                                  : _seatError != null
                                  ? AdminTheme.error
                                  : AdminTheme.textTertiary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _seatData != null
                                  ? '좌석 ${_seatData!.totalSeats}석 로드 완료'
                                  : _seatError != null
                                  ? '파싱 실패'
                                  : '엑셀 파일을 선택하거나 끌어서 놓으세요',
                              style: AdminTheme.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _seatData != null
                                    ? AdminTheme.success
                                    : _seatError != null
                                    ? AdminTheme.error
                                    : AdminTheme.textSecondary,
                              ),
                            ),
                            if (_seatData != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _seatData!.gradeSummary,
                                style: AdminTheme.sans(
                                  fontSize: 12,
                                  color: AdminTheme.textTertiary,
                                ),
                              ),
                            ],
                            if (_seatError != null) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  _seatError!,
                                  style: AdminTheme.sans(
                                    fontSize: 12,
                                    color: AdminTheme.error,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              ),

              // 파싱 결과 요약 (성공 시) — 디버그 접힌 상태
              if (_seatData != null && _parseResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AdminTheme.success.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.analytics_outlined,
                            size: 14,
                            color: AdminTheme.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '파싱 결과',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AdminTheme.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _parseDetailRow(
                        '감지 형식',
                        _formatName(_parseResult!.detectedFormat),
                      ),
                      _parseDetailRow('총 좌석', '${_seatData!.totalSeats}석'),
                      _parseDetailRow('등급별', _seatData!.gradeSummary),
                    ],
                  ),
                ),

                // 버튼 영역 — 파싱 결과 바로 아래
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AdminTheme.gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AdminTheme.gold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 0),
                        child: const Text('← 이전'),
                        style: TextButton.styleFrom(
                          foregroundColor: AdminTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: !_isUploadingSeats ? _uploadSeats : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: AdminTheme.gold),
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: _isUploadingSeats
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AdminTheme.gold,
                                ),
                              )
                            : Text(
                                '좌석 등록',
                                style: AdminTheme.sans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('공연 등록이 완료되었습니다'),
                              backgroundColor: AdminTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            context.go('/');
                          }
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          '공연 등록완료',
                          style: AdminTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminTheme.gold,
                          foregroundColor: Colors.black,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 2),
                        child: Text(
                          '주문 입력 →',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 디버그 정보 (접힌 상태)
                if (_parseResult!.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
                    initiallyExpanded: false,
                    dense: true,
                    title: Text(
                      '디버그 정보 (${_parseResult!.warnings.length}건)',
                      style: AdminTheme.sans(
                        fontSize: 10,
                        color: AdminTheme.textTertiary,
                      ),
                    ),
                    children: [
                      for (final w in _parseResult!.warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 10,
                                color: AdminTheme.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  w,
                                  style: AdminTheme.sans(
                                    fontSize: 10,
                                    color: AdminTheme.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],

              // 좌석 파싱 전 버튼
              if (_seatData == null) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _currentStep = 0),
                      child: const Text('← 이전'),
                      style: TextButton.styleFrom(
                        foregroundColor: AdminTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('공연 등록이 완료되었습니다. 좌석은 나중에 추가할 수 있습니다.'),
                            backgroundColor: AdminTheme.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          context.go('/');
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        '좌석 없이 등록 완료',
                        style: AdminTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminTheme.gold,
                        foregroundColor: Colors.black,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // 등급별 좌석 상세 (로드 성공 시)
              if (_seatData != null && _seatData!.seats.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildSeatDetailSection(),
              ],

              // 편집 모드 + 좌석 등록 완료 → 좌석 배정 섹션
              if (widget.editEventId != null && _seatsUploaded && _createdEventId != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AdminTheme.success.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AdminTheme.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, size: 18, color: AdminTheme.success),
                          const SizedBox(width: 8),
                          Text(
                            '좌석 등록 완료 — 미확정 티켓에 좌석을 배정할 수 있습니다',
                            style: AdminTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminTheme.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 등급별 배정 버튼
                      if (_seatData != null)
                        ..._getGradesFromSeatData().map((grade) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SeatAssignButton(
                              eventId: _createdEventId!,
                              grade: grade,
                              availableSeats: _seatData!.seats
                                  .where((s) => s['grade'] == grade)
                                  .length,
                            ),
                          )),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('좌석 배정이 완료되었습니다'),
                              backgroundColor: AdminTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            context.go('/');
                          }
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          '완료',
                          style: AdminTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminTheme.gold,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 좌석 수 적으면 경고
              if (_seatData != null && _seatData!.totalSeats < 10) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AdminTheme.warning.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AdminTheme.warning,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '좌석 수가 너무 적습니다',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AdminTheme.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '좌석배치도 이미지 파일이 아닌, 네이버 스마트스토어에서 다운받은\n'
                        '「상품별좌석현황」 엑셀 파일을 업로드해주세요.\n\n'
                        '헤더 형식: No | 이용(관람)일 | 회차 | 좌석등급 | 층 | 열 | 좌석수 | 좌석번호',
                        style: AdminTheme.sans(
                          fontSize: 11,
                          color: AdminTheme.warning,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 형식 안내 (좌석 파싱 전에만 표시)
              if (_seatData == null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '지원 형식',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• 네이버 좌석현황: 좌석등급/층/열/좌석번호 (VIP석, R석, S석, A석)\n'
                        '• 리스트: 구역/층/열/번호/등급 컬럼\n'
                        '• 비주얼: 셀 위치 = 좌석 위치, 값 = 등급 (VIP/R/S/A)\n'
                        '• 행열: 행 = 좌석열, 열 = 좌석번호, 값 = 등급',
                        style: AdminTheme.sans(
                          fontSize: 11,
                          color: AdminTheme.textTertiary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  Widget _buildSeatDetailSection() {
    if (_seatData == null) return const SizedBox.shrink();

    // Group seats by grade → zone → row → seat numbers
    final groupMap = <String, List<int>>{};
    for (final seat in _seatData!.seats) {
      final grade = seat['grade']?.toString() ?? 'S';
      final floor = seat['floor']?.toString() ?? '1층';
      final zone = seat['block']?.toString() ?? '';
      final row = seat['row']?.toString() ?? '?';
      final num = int.tryParse(seat['number']?.toString() ?? '') ?? 0;
      final key = '$grade|$floor|$zone|$row';
      groupMap.putIfAbsent(key, () => []);
      groupMap[key]!.add(num);
    }

    // Build _SeatRow list grouped by grade
    final gradeRows = <String, List<_SeatRow>>{};
    for (final entry in groupMap.entries) {
      final parts = entry.key.split('|');
      entry.value.sort();
      final grade = parts[0];
      gradeRows.putIfAbsent(grade, () => []);
      gradeRows[grade]!.add(
        _SeatRow(
          grade: grade,
          floor: parts[1],
          zone: parts[2],
          row: parts[3],
          seats: entry.value,
        ),
      );
    }
    // Sort each grade's rows: zone → row (numeric)
    for (final rows in gradeRows.values) {
      rows.sort((a, b) {
        final za = a.zone.compareTo(b.zone);
        if (za != 0) return za;
        final ra = int.tryParse(a.row) ?? 999;
        final rb = int.tryParse(b.row) ?? 999;
        return ra.compareTo(rb);
      });
    }

    // Build 4-column grid: VIP | R | S | A
    const gradeOrder = ['VIP', 'R', 'S', 'A'];
    final activeGrades = gradeOrder
        .where((g) => gradeRows.containsKey(g))
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
              const Icon(
                Icons.event_seat_outlined,
                size: 14,
                color: AdminTheme.gold,
              ),
              const SizedBox(width: 6),
              Text(
                '상품별 좌석현황',
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 등급별 카드 그리드 (2×2 또는 inline)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: activeGrades.map((grade) {
                  final rows = gradeRows[grade]!;
                  final totalSeats = rows.fold<int>(
                    0,
                    (sum, r) => sum + r.seats.length,
                  );
                  final color = _gradeColors[grade] ?? AdminTheme.textSecondary;
                  return SizedBox(
                    width: 280,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: color.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 등급 헤더
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '$grade석',
                                  style: AdminTheme.sans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$totalSeats석',
                                style: AdminTheme.sans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 테이블 헤더
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    '구역',
                                    style: AdminTheme.sans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AdminTheme.textTertiary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    '열',
                                    style: AdminTheme.sans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AdminTheme.textTertiary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    '수량',
                                    style: AdminTheme.sans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AdminTheme.textTertiary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '좌석번호',
                                    style: AdminTheme.sans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AdminTheme.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 좌석 행 목록
                          ...rows.map(
                            (sr) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      sr.zone.isEmpty ? '-' : sr.zone,
                                      style: AdminTheme.sans(
                                        fontSize: 9,
                                        color: AdminTheme.textTertiary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 30,
                                    child: Text(
                                      '${sr.row}',
                                      style: AdminTheme.sans(
                                        fontSize: 9,
                                        color: AdminTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 30,
                                    child: Text(
                                      '${sr.seats.length}',
                                      style: AdminTheme.sans(
                                        fontSize: 9,
                                        color: AdminTheme.textTertiary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _compactRange(sr.seats),
                                      style: AdminTheme.sans(
                                        fontSize: 9,
                                        color: AdminTheme.textTertiary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
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
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Convert sorted seat numbers to compact range string: "1~30" or "1~10, 15~20"
  String _compactRange(List<int> sorted) {
    if (sorted.isEmpty) return '';
    final ranges = <String>[];
    int start = sorted[0];
    int end = sorted[0];
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == end + 1) {
        end = sorted[i];
      } else {
        ranges.add(start == end ? '$start' : '$start~$end');
        start = sorted[i];
        end = sorted[i];
      }
    }
    ranges.add(start == end ? '$start' : '$start~$end');
    return ranges.join(', ');
  }

  Widget _parseDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AdminTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatName(ExcelFormat format) {
    switch (format) {
      case ExcelFormat.list:
        return '리스트 (네이버 좌석현황)';
      case ExcelFormat.colorCoded:
        return '색상 코딩 (좌석배치도)';
      case ExcelFormat.visual:
        return '비주얼 (등급 텍스트)';
      case ExcelFormat.rowCol:
        return '행열 매트릭스';
    }
  }

  static const _cfBaseUrl = 'https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net';

  Future<void> _pickSeatExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    final fileName = result.files.single.name;
    final bytes = result.files.single.bytes!;
    await _processExcelBytes(bytes, fileName);
  }

  /// 엑셀 파일을 CF로 정리(numFmt 제거) 후 파싱
  Future<void> _processExcelBytes(Uint8List bytes, String fileName) async {
    setState(() {
      _isParsingSeat = true;
      _seatError = null;
      _seatData = null;
      _parseResult = null;
    });

    await Future.delayed(const Duration(milliseconds: 300));

    try {
      // 모든 엑셀 파일을 CF를 통해 정리 (.xls 변환 + .xlsx numFmt 호환성 처리)
      final response = await http.post(
        Uri.parse('$_cfBaseUrl/convertXlsToXlsxHttp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'base64': base64Encode(bytes)}),
      );
      if (response.statusCode != 200) {
        final err = jsonDecode(response.body)['error'] ?? 'HTTP ${response.statusCode}';
        throw Exception('엑셀 처리 실패: $err');
      }
      final resultBase64 = jsonDecode(response.body)['base64'] as String;
      final xlsxBytes = base64Decode(resultBase64);

      final parseResult = EnhancedExcelParser.parse(xlsxBytes);

      if (!mounted) return;

      if (parseResult.errors.isNotEmpty) {
        setState(() {
          _isParsingSeat = false;
          _seatError = parseResult.errors.join('\n');
          _parseResult = parseResult;
        });
        return;
      }

      if (parseResult.seats.isEmpty) {
        setState(() {
          _isParsingSeat = false;
          _seatError =
              '좌석을 찾을 수 없습니다.\n'
              '네이버 스마트스토어의 「상품별좌석현황」 엑셀을 업로드해주세요.\n'
              '(좌석등급/층/열/좌석번호 컬럼이 필요합니다)';
          _parseResult = parseResult;
        });
        return;
      }

      setState(() {
        _isParsingSeat = false;
        _seatData = ParsedSeatData.fromParseResult(parseResult);
        _parseResult = parseResult;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsingSeat = false;
        _seatError = '파싱 오류: $e';
      });
    }
  }

  // ── 공연장에서 좌석 가져오기 ──

  Widget _buildVenueImportButton() {
    return OutlinedButton.icon(
      onPressed: _isParsingSeat ? null : _showVenuePickerDialog,
      icon: const Icon(Icons.apartment_rounded, size: 18),
      label: Text(
        '등록된 공연장에서 좌석 가져오기',
        style: AdminTheme.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminTheme.gold,
        side: const BorderSide(color: AdminTheme.gold),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Future<void> _showVenuePickerDialog() async {
    final venues = await FirebaseFirestore.instance
        .collection('venues')
        .orderBy('name')
        .get();

    if (!mounted) return;

    final venueList = venues.docs
        .map((doc) => Venue.fromFirestore(doc))
        .where((v) => v.totalSeats > 0)
        .toList();

    if (venueList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('등록된 공연장이 없거나 좌석 데이터가 없습니다'),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    final selected = await showDialog<Venue>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AdminTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  '공연장 선택',
                  style: AdminTheme.serif(fontSize: 18),
                ),
              ),
              const Divider(color: AdminTheme.border, height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: venueList.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AdminTheme.border, height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final v = venueList[i];
                    final hasSeatLayout = v.seatLayout != null && v.seatLayout!.seats.isNotEmpty;
                    final floorSummary = v.floors
                        .map((f) => '${f.name}: ${f.totalSeats}석')
                        .join(' · ');
                    return ListTile(
                      leading: Icon(
                        hasSeatLayout ? Icons.grid_on_rounded : Icons.list_alt_rounded,
                        color: hasSeatLayout ? AdminTheme.gold : AdminTheme.textTertiary,
                        size: 20,
                      ),
                      title: Text(
                        v.name,
                        style: AdminTheme.sans(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${v.totalSeats}석${floorSummary.isNotEmpty ? ' ($floorSummary)' : ''}',
                        style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary),
                      ),
                      onTap: () => Navigator.of(ctx).pop(v),
                    );
                  },
                ),
              ),
              const Divider(color: AdminTheme.border, height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      '취소',
                      style: AdminTheme.sans(color: AdminTheme.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;
    _importSeatsFromVenue(selected);
  }

  void _importSeatsFromVenue(Venue venue) {
    // seatLayout이 있으면 LayoutSeat에서 가져오기
    if (venue.seatLayout != null && venue.seatLayout!.seats.isNotEmpty) {
      final seats = venue.seatLayout!.seats
          .where((s) => s.seatType == SeatType.normal)
          .toList();

      final gradeCounts = <String, int>{};
      for (final s in seats) {
        gradeCounts[s.grade] = (gradeCounts[s.grade] ?? 0) + 1;
      }
      final summary = _gradeOrder
          .where((g) => gradeCounts.containsKey(g))
          .map((g) => '$g: ${gradeCounts[g]}')
          .join('  ·  ');

      setState(() {
        _seatData = ParsedSeatData(
          seats: seats
              .map((s) => <String, dynamic>{
                    'block': s.zone,
                    'floor': s.floor,
                    'row': s.row,
                    'number': s.number,
                    'grade': s.grade,
                  })
              .toList(),
          totalSeats: seats.length,
          gradeSummary: summary,
        );
        _parseResult = null;
        _seatError = null;
        // 공연장명 자동 채우기
        if (_venueNameCtrl.text.trim().isEmpty) {
          _venueNameCtrl.text = venue.name;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${venue.name}에서 ${seats.length}석 가져옴'),
          backgroundColor: AdminTheme.success,
        ),
      );
      return;
    }

    // seatLayout 없으면 floors/blocks 구조에서 좌석 생성
    final seatList = <Map<String, dynamic>>[];
    final gradeCounts = <String, int>{};

    for (final floor in venue.floors) {
      for (final block in floor.blocks) {
        final grade = block.grade ?? 'S';
        if (block.customRows.isNotEmpty) {
          for (final customRow in block.customRows) {
            for (int n = 1; n <= customRow.seatCount; n++) {
              seatList.add({
                'block': block.name,
                'floor': floor.name,
                'row': customRow.name,
                'number': n,
                'grade': grade,
              });
              gradeCounts[grade] = (gradeCounts[grade] ?? 0) + 1;
            }
          }
        } else {
          for (int r = 1; r <= block.rows; r++) {
            for (int n = 1; n <= block.seatsPerRow; n++) {
              seatList.add({
                'block': block.name,
                'floor': floor.name,
                'row': '$r',
                'number': n,
                'grade': grade,
              });
              gradeCounts[grade] = (gradeCounts[grade] ?? 0) + 1;
            }
          }
        }
      }
    }

    if (seatList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이 공연장에 좌석 데이터가 없습니다'),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    final summary = _gradeOrder
        .where((g) => gradeCounts.containsKey(g))
        .map((g) => '$g: ${gradeCounts[g]}')
        .join('  ·  ');

    setState(() {
      _seatData = ParsedSeatData(
        seats: seatList,
        totalSeats: seatList.length,
        gradeSummary: summary,
      );
      _parseResult = null;
      _seatError = null;
      if (_venueNameCtrl.text.trim().isEmpty) {
        _venueNameCtrl.text = venue.name;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${venue.name}에서 ${seatList.length}석 가져옴'),
        backgroundColor: AdminTheme.success,
      ),
    );
  }

  List<String> _getGradesFromSeatData() {
    if (_seatData == null) return [];
    final grades = <String>{};
    for (final seat in _seatData!.seats) {
      final g = seat['grade'] as String?;
      if (g != null) grades.add(g);
    }
    final sorted = grades.toList()
      ..sort((a, b) {
        final ai = _gradeOrder.indexOf(a);
        final bi = _gradeOrder.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });
    return sorted;
  }

  Future<void> _uploadSeats() async {
    if (_seatData == null) return;
    if (_createdEventId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 Step 1에서 공연을 등록해주세요')));
      return;
    }
    setState(() => _isUploadingSeats = true);

    try {
      final seatRepo = ref.read(seatRepositoryProvider);
      // 기존 좌석 삭제 (중복 방지)
      await seatRepo.deleteAllSeats(_createdEventId!);
      final seatList = _seatData!.toSeatDataList();
      await seatRepo.createSeatsFromCsv(_createdEventId!, seatList);

      // 이벤트 totalSeats / availableSeats 업데이트
      final eventRepo = ref.read(eventRepositoryProvider);
      await eventRepo.updateEvent(_createdEventId!, {
        'totalSeats': seatList.length,
        'availableSeats': seatList.length,
      });

      if (!mounted) return;
      setState(() {
        _isUploadingSeats = false;
        _seatsUploaded = true;
        if (widget.editEventId == null) {
          // 신규 등록 모드: 다음 스텝으로 이동
          _currentStep = 2;
        }
        // 편집 모드: 같은 스텝에 머무르며 배정 버튼 표시
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${seatList.length}석 등록 완료')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingSeats = false;
        _seatError = '업로드 오류: $e';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Step 3: 주문 입력
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStep3OrderInput() {
    if (_createdEventId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '먼저 공연을 등록하세요',
              style: AdminTheme.sans(color: AdminTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text('← Step 1로'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('step3'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step 3',
                style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold),
              ),
              const SizedBox(height: 4),
              Text('주문 입력', style: AdminTheme.serif(fontSize: 22)),
              const SizedBox(height: 4),
              Text(
                '네이버 스토어 주문 정보를 입력하세요',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 32),

              // 입력 폼
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _orderIdCtrl,
                      style: AdminTheme.sans(fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: '네이버 주문번호 *',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buyerNameCtrl,
                            style: AdminTheme.sans(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: '구매자명 *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _buyerPhoneCtrl,
                            style: AdminTheme.sans(fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: '연락처 *',
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // 등급 선택
                        Text(
                          '등급:',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ...(_enabledGrades.toList()..sort(
                              (a, b) => _gradeOrder
                                  .indexOf(a)
                                  .compareTo(_gradeOrder.indexOf(b)),
                            ))
                            .map(
                              (grade) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    grade,
                                    style: AdminTheme.sans(fontSize: 12),
                                  ),
                                  selected: _selectedGrade == grade,
                                  onSelected: (v) {
                                    if (v) {
                                      setState(() => _selectedGrade = grade);
                                    }
                                  },
                                  selectedColor: AdminTheme.gold,
                                  labelStyle: TextStyle(
                                    color: _selectedGrade == grade
                                        ? AdminTheme.onAccent
                                        : AdminTheme.textPrimary,
                                  ),
                                  side: BorderSide(
                                    color: AdminTheme.border,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                            ),
                        const Spacer(),
                        // 수량
                        Text(
                          '수량:',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 20,
                          ),
                          color: AdminTheme.textSecondary,
                        ),
                        Text(
                          '$_quantity',
                          style: AdminTheme.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _quantity++),
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          color: AdminTheme.gold,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 등록 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isCreatingOrder ? null : _createNaverOrder,
                        child: _isCreatingOrder
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AdminTheme.onAccent,
                                ),
                              )
                            : const Text('주문 등록 + 티켓 발급'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 테스트 주문 버튼
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: AdminTheme.gold,
                            width: 0.5,
                          ),
                        ),
                        onPressed: _isCreatingOrder ? null : _createTestOrder,
                        icon: const Icon(Icons.science_outlined, size: 16),
                        label: const Text('테스트 주문 추가 (SMS 없이)'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 최근 주문 목록
              _buildRecentOrders(),

              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 1),
                    child: const Text('← 좌석 등록'),
                    style: TextButton.styleFrom(
                      foregroundColor: AdminTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 3),
                    child: const Text('현황 보기 →'),
                    style: TextButton.styleFrom(
                      foregroundColor: AdminTheme.gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentOrders() {
    if (_createdEventId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('naverOrders')
          .where('eventId', isEqualTo: _createdEventId)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final orders = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '최근 주문',
              style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...orders.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final name = d['buyerName'] as String? ?? '';
              final grade = d['seatGrade'] as String? ?? '';
              final qty = d['quantity'] as int? ?? 1;
              final status = d['status'] as String? ?? '';
              final createdAt = (d['createdAt'] as Timestamp?)?.toDate();

              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 2,
                      height: 20,
                      color: status == 'confirmed'
                          ? AdminTheme.success
                          : AdminTheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$name  ·  $grade $qty매',
                        style: AdminTheme.sans(fontSize: 12),
                      ),
                    ),
                    // SMS status
                    _SmsBadgeInline(orderId: doc.id),
                    const SizedBox(width: 8),
                    Text(
                      createdAt != null
                          ? DateFormat('HH:mm').format(createdAt)
                          : '',
                      style: AdminTheme.sans(
                        fontSize: 11,
                        color: AdminTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // 가상 테스트 주문 생성 (SMS 발송 안 함)
  Future<void> _createTestOrder() async {
    final testNames = ['테스트관객A', '테스트관객B', '테스트관객C', '테스트관객D', '테스트관객E'];
    final random = DateTime.now().millisecondsSinceEpoch;
    final name = testNames[random % testNames.length];
    final phone = '010-0000-${(random % 9000 + 1000)}';
    final orderId = 'TEST-${random}';

    setState(() => _isCreatingOrder = true);

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .createNaverOrder(
            eventId: _createdEventId!,
            naverOrderId: orderId,
            buyerName: name,
            buyerPhone: phone,
            productName: '테스트 주문',
            seatGrade: _selectedGrade,
            quantity: _quantity,
            orderDate: DateTime.now().toIso8601String(),
            memo: '테스트 주문 (SMS 발송 안 함)',
            dryRun: true,
          );

      if (!mounted) return;

      final tickets = result['tickets'] as List<dynamic>? ?? [];
      if (tickets.isNotEmpty) {
        _showTicketUrls(name, tickets);
      }

      setState(() => _isCreatingOrder = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🧪 테스트: $name — $_selectedGrade ${tickets.length}장 발급 (SMS 없음)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingOrder = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _createNaverOrder() async {
    final orderId = _orderIdCtrl.text.trim();
    final name = _buyerNameCtrl.text.trim();
    final phone = _buyerPhoneCtrl.text.trim();

    if (orderId.isEmpty || name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('주문번호, 이름, 연락처를 모두 입력하세요')));
      return;
    }

    setState(() => _isCreatingOrder = true);

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .createNaverOrder(
            eventId: _createdEventId!,
            naverOrderId: orderId,
            buyerName: name,
            buyerPhone: phone,
            productName: _titleCtrl.text.trim(),
            seatGrade: _selectedGrade,
            quantity: _quantity,
            orderDate: DateTime.now().toIso8601String(),
          );

      if (!mounted) return;

      // 티켓 URL 표시
      final tickets = result['tickets'] as List<dynamic>? ?? [];
      if (tickets.isNotEmpty) {
        _showTicketUrls(name, tickets);
      }

      // 입력 초기화
      _orderIdCtrl.clear();
      _buyerNameCtrl.clear();
      _buyerPhoneCtrl.clear();
      setState(() {
        _quantity = 1;
        _isCreatingOrder = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name — $_selectedGrade ${tickets.length}장 발급 완료'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingOrder = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  void _showTicketUrls(String buyerName, List<dynamic> tickets) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$buyerName 티켓 URL', style: AdminTheme.serif(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: tickets.map((t) {
            final url = t['url'] as String? ?? '';
            final entry = t['entryNumber'] as int? ?? 0;
            return ListTile(
              dense: true,
              title: Text(
                '#$entry  $_selectedGrade석',
                style: AdminTheme.sans(fontSize: 13),
              ),
              subtitle: Text(
                url,
                style: AdminTheme.sans(
                  fontSize: 10,
                  color: AdminTheme.textTertiary,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: AdminTheme.gold,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(const SnackBar(content: Text('URL 복사됨')));
                },
              ),
            );
          }).toList(),
        ),
        actions: [
          if (tickets.length == 1)
            TextButton(
              onPressed: () {
                final url = tickets.first['url'] as String? ?? '';
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('URL 복사됨')));
              },
              child: const Text('URL 복사'),
            ),
          if (tickets.length > 1)
            TextButton(
              onPressed: () {
                final urls = tickets
                    .map((t) => t['url'] as String? ?? '')
                    .join('\n');
                Clipboard.setData(ClipboardData(text: urls));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('전체 URL 복사됨')));
              },
              child: const Text('전체 URL 복사'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Step 4: 현황 보기
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStep4Status() {
    if (_createdEventId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '먼저 공연을 등록하세요',
              style: AdminTheme.sans(color: AdminTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text('← Step 1로'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('step4'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step 4',
                style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold),
              ),
              const SizedBox(height: 4),
              Text('현황', style: AdminTheme.serif(fontSize: 22)),
              const SizedBox(height: 32),

              // 등급별 좌석 현황
              _buildSeatStatus(),
              const SizedBox(height: 24),

              // 주문 목록
              _buildOrderList(),

              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 2),
                    child: const Text('← 주문 입력'),
                    style: TextButton.styleFrom(
                      foregroundColor: AdminTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () =>
                        context.go('/events/$_createdEventId/naver-orders'),
                    child: const Text('상세 관리 →'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeatStatus() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seats')
          .where('eventId', isEqualTo: _createdEventId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final seats = snapshot.data!.docs;
        if (seats.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AdminTheme.border, width: 0.5),
            ),
            child: Center(
              child: Text(
                '좌석 미등록',
                style: AdminTheme.sans(color: AdminTheme.textTertiary),
              ),
            ),
          );
        }

        // 등급별 집계
        final gradeStats = <String, Map<String, int>>{};
        for (final doc in seats) {
          final d = doc.data() as Map<String, dynamic>;
          final grade = d['grade'] as String? ?? '기타';
          final status = d['status'] as String? ?? 'available';
          gradeStats.putIfAbsent(
            grade,
            () => {'total': 0, 'available': 0, 'reserved': 0},
          );
          gradeStats[grade]!['total'] = (gradeStats[grade]!['total'] ?? 0) + 1;
          if (status == 'available') {
            gradeStats[grade]!['available'] =
                (gradeStats[grade]!['available'] ?? 0) + 1;
          } else {
            gradeStats[grade]!['reserved'] =
                (gradeStats[grade]!['reserved'] ?? 0) + 1;
          }
        }

        final sortedGrades = gradeStats.keys.toList()
          ..sort(
            (a, b) => _gradeOrder.indexOf(a).compareTo(_gradeOrder.indexOf(b)),
          );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '등급별 좌석 현황',
              style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...sortedGrades.map((grade) {
              final stats = gradeStats[grade]!;
              final total = stats['total'] ?? 0;
              final reserved = stats['reserved'] ?? 0;
              final available = stats['available'] ?? 0;
              final ratio = total > 0 ? reserved / total : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          grade,
                          style: AdminTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$reserved / $total',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            color: AdminTheme.gold,
                          ),
                        ),
                        Text(
                          '  ($available 잔여)',
                          style: AdminTheme.sans(
                            fontSize: 11,
                            color: AdminTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ratio,
                        backgroundColor: AdminTheme.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AdminTheme.gold,
                        ),
                        minHeight: 4,
                      ),
                    ),
                    // 좌석 배정 버튼
                    if (available > 0)
                      _SeatAssignButton(
                        eventId: _createdEventId!,
                        grade: grade,
                        availableSeats: available,
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildOrderList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('naverOrders')
          .where('eventId', isEqualTo: _createdEventId)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final orders = snapshot.data!.docs;
        final confirmed = orders
            .where((d) => (d.data() as Map)['status'] == 'confirmed')
            .length;
        final totalTickets = orders.fold<int>(
          0,
          (sum, d) => sum + ((d.data() as Map)['quantity'] as int? ?? 0),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '주문 목록',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$confirmed건  ·  $totalTickets매',
                  style: AdminTheme.sans(fontSize: 12, color: AdminTheme.gold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (orders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '주문 없음',
                    style: AdminTheme.sans(color: AdminTheme.textTertiary),
                  ),
                ),
              )
            else
              ...orders.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final name = d['buyerName'] as String? ?? '';
                final grade = d['seatGrade'] as String? ?? '';
                final qty = d['quantity'] as int? ?? 1;
                final status = d['status'] as String? ?? '';
                final createdAt = (d['createdAt'] as Timestamp?)?.toDate();

                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AdminTheme.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AdminTheme.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 2,
                        height: 20,
                        color: status == 'confirmed'
                            ? AdminTheme.success
                            : AdminTheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$name  ·  $grade $qty매',
                          style: AdminTheme.sans(fontSize: 12),
                        ),
                      ),
                      _SmsBadgeInline(orderId: doc.id),
                      const SizedBox(width: 8),
                      Text(
                        createdAt != null
                            ? DateFormat('MM.dd HH:mm').format(createdAt)
                            : '',
                        style: AdminTheme.sans(
                          fontSize: 11,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// ─── Step Indicator ───

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> labels;
  final void Function(int)? onStepTap;
  const _StepIndicator({
    required this.currentStep,
    required this.labels,
    this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(labels.length, (i) {
        final isActive = i == currentStep;
        final isDone = i < currentStep;
        final canTap = onStepTap != null && i != currentStep;
        return Row(
          children: [
            if (i > 0)
              Container(
                width: 16,
                height: 1,
                color: isDone ? AdminTheme.gold : AdminTheme.border,
              ),
            GestureDetector(
              onTap: canTap ? () => onStepTap!(i) : null,
              child: MouseRegion(
                cursor: canTap
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AdminTheme.gold
                        : isDone
                        ? AdminTheme.gold.withValues(alpha: 0.3)
                        : AdminTheme.surface,
                    border: Border.all(
                      color: isActive || isDone
                          ? AdminTheme.gold
                          : AdminTheme.border,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check, size: 12, color: AdminTheme.gold)
                        : Text(
                            '${i + 1}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? AdminTheme.onAccent
                                  : AdminTheme.textTertiary,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─── Seat Assign Button (등급별 좌석 배정) ───

class _SeatAssignButton extends StatefulWidget {
  final String eventId;
  final String grade;
  final int availableSeats;
  const _SeatAssignButton({
    required this.eventId,
    required this.grade,
    required this.availableSeats,
  });

  @override
  State<_SeatAssignButton> createState() => _SeatAssignButtonState();
}

class _SeatAssignButtonState extends State<_SeatAssignButton> {
  bool _isAssigning = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mobileTickets')
          .where('eventId', isEqualTo: widget.eventId)
          .where('seatGrade', isEqualTo: widget.grade)
          .where('status', isEqualTo: 'active')
          .where('seatId', isNull: true)
          .snapshots(),
      builder: (context, snap) {
        final unassigned = snap.data?.docs.length ?? 0;
        if (unassigned == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: AdminTheme.warning),
              const SizedBox(width: 6),
              Text(
                '미확정 $unassigned매',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: _isAssigning
                      ? null
                      : () => _assignSeats(unassigned),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _isAssigning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AdminTheme.onAccent,
                          ),
                        )
                      : Text('좌석 배정 ($unassigned매)'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _assignSeats(int count) async {
    setState(() => _isAssigning = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'assignDeferredSeats',
      );
      final result = await callable.call({
        'eventId': widget.eventId,
        'seatGrade': widget.grade,
      });
      if (!mounted) return;
      final assigned = result.data['assigned'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.grade}석 $assigned매 배정 완료'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('배정 실패: ${e.message}'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), backgroundColor: AdminTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }
}

// ─── SMS Badge Inline ───

class _SmsBadgeInline extends StatelessWidget {
  final String orderId;
  const _SmsBadgeInline({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('smsTasks')
          .where('naverOrderId', isEqualTo: orderId)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final status =
            (snapshot.data!.docs.first.data() as Map)['status'] as String?;

        IconData icon;
        Color color;
        switch (status) {
          case 'sent':
            icon = Icons.sms_rounded;
            color = AdminTheme.success;
          case 'pending':
            icon = Icons.schedule_send_rounded;
            color = AdminTheme.gold;
          case 'failed':
            icon = Icons.sms_failed_rounded;
            color = AdminTheme.error;
          default:
            icon = Icons.sms_rounded;
            color = AdminTheme.textTertiary;
        }
        return Icon(icon, size: 14, color: color);
      },
    );
  }
}

// ─── Parsed Seat Data Helper ───

class _SeatRow {
  final String grade;
  final String floor;
  final String zone;
  final String row;
  final List<int> seats;

  const _SeatRow({
    required this.grade,
    required this.floor,
    required this.zone,
    required this.row,
    required this.seats,
  });
}

class ParsedSeatData {
  final List<Map<String, dynamic>> seats;
  final int totalSeats;
  final String gradeSummary;

  ParsedSeatData({
    required this.seats,
    required this.totalSeats,
    required this.gradeSummary,
  });

  factory ParsedSeatData.fromParseResult(ExcelParseResult result) {
    final gradeCounts = <String, int>{};
    for (final seat in result.seats) {
      final grade = seat.grade;
      gradeCounts[grade] = (gradeCounts[grade] ?? 0) + 1;
    }
    final summary = _gradeOrder
        .where((g) => gradeCounts.containsKey(g))
        .map((g) => '$g: ${gradeCounts[g]}')
        .join('  ·  ');

    return ParsedSeatData(
      seats: result.seats
          .map(
            (s) => {
              'block': s.zone,
              'floor': s.floor,
              'row': s.row,
              'number': s.number,
              'grade': s.grade,
            },
          )
          .toList(),
      totalSeats: result.seats.length,
      gradeSummary: summary,
    );
  }

  List<Map<String, String>> toSeatDataList() {
    return seats
        .map(
          (s) => {
            'block': s['block']?.toString() ?? '',
            'floor': s['floor']?.toString() ?? '1층',
            'row': s['row']?.toString() ?? '',
            'number': s['number']?.toString() ?? '',
            'grade': s['grade']?.toString() ?? 'S',
          },
        )
        .toList();
  }
}

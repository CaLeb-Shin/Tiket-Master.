import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/naver_order_repository.dart';
import 'package:melon_core/data/repositories/mobile_ticket_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/naver_order.dart';
import 'package:melon_core/infrastructure/firebase/functions_service.dart';
import 'excel_seat_upload_helper.dart';

// =============================================================================
// 네이버 티켓 전용 위자드 — 스텝 바이 스텝 흐름
// =============================================================================

const _ticketBaseUrl = 'https://melonticket-web-20260216.vercel.app/m/';
const _gradeOrder = ['VIP', 'R', 'S', 'A'];

class NaverTicketWizardScreen extends ConsumerStatefulWidget {
  const NaverTicketWizardScreen({super.key});

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
  String? _posterUrl;
  String? _naverProductUrl; // 네이버 스토어 상품 URL (모바일 티켓에서 포스터 클릭 시 이동)
  String? _venueAddress; // 공연장 주소
  bool _naverOnly = true; // 네이버 전용 (새 봇) vs 놀티켓 연계 (기존 봇)
  bool _isCreatingEvent = false;
  bool _isFetchingProduct = false;
  bool _isFetchingStore = false;
  List<Map<String, dynamic>> _storeProducts = [];

  // Step 2: 좌석 등록
  ParsedSeatData? _seatData;
  ExcelParseResult? _parseResult;
  bool _isParsingSeat = false;
  bool _isUploadingSeats = false;
  String? _seatError;

  // Step 3: 주문 입력
  final _orderIdCtrl = TextEditingController();
  final _buyerNameCtrl = TextEditingController();
  final _buyerPhoneCtrl = TextEditingController();
  String _selectedGrade = 'S';
  int _quantity = 1;
  bool _isCreatingOrder = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _venueNameCtrl.dispose();
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
                  icon: const Icon(Icons.west,
                      color: AdminTheme.textPrimary, size: 20),
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
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: _buildStep(),
          ),
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
              Text('Step 1',
                  style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
              const SizedBox(height: 4),
              Text('공연 등록',
                  style: AdminTheme.serif(fontSize: 22)),
              const SizedBox(height: 4),
              Text('공연 기본 정보를 입력하세요',
                  style: AdminTheme.sans(
                      fontSize: 13, color: AdminTheme.textTertiary)),
              const SizedBox(height: 32),

              // 네이버 URL 자동 채우기
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.store_rounded,
                            size: 18, color: AdminTheme.gold),
                        const SizedBox(width: 8),
                        Text('내 네이버 스토어',
                            style: AdminTheme.sans(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('melon_symphony_orchestra',
                            style: AdminTheme.sans(
                                fontSize: 11, color: AdminTheme.textTertiary)),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 불러오기 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isFetchingStore ? null : _fetchMyStore,
                        child: _isFetchingStore
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AdminTheme.onAccent))
                            : const Text('스토어에서 상품 불러오기'),
                      ),
                    ),

                    // 스토어 상품 목록
                    if (_storeProducts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('상품을 선택하세요 (${_storeProducts.length}개)',
                          style: AdminTheme.sans(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...List.generate(
                        _storeProducts.length,
                        (i) {
                          final p = _storeProducts[i];
                          final title = p['title'] as String? ?? '';
                          final price = p['price'] as int? ?? 0;
                          final imgUrl = p['imageUrl'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GestureDetector(
                              onTap: () => _selectStoreProduct(p),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AdminTheme.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: AdminTheme.border, width: 0.5),
                                ),
                                child: Row(
                                  children: [
                                    if (imgUrl.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: Image.network(imgUrl,
                                            width: 40, height: 40,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox(width: 40, height: 40)),
                                      ),
                                    if (imgUrl.isNotEmpty)
                                      const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(title,
                                              style: AdminTheme.sans(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          if (price > 0)
                                            Text(
                                                '₩${NumberFormat('#,###').format(price)}',
                                                style: AdminTheme.sans(
                                                    fontSize: 11,
                                                    color: AdminTheme
                                                        .textSecondary)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios,
                                        size: 12,
                                        color: AdminTheme.textTertiary),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 기존 공연 선택
              _buildExistingEventSelector(),
              const SizedBox(height: 16),

              // 또는 새로 만들기
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
                    Text('새 공연 등록',
                        style: AdminTheme.sans(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),

                    // 공연명
                    TextField(
                      controller: _titleCtrl,
                      style: AdminTheme.sans(fontSize: 14),
                      decoration: const InputDecoration(labelText: '공연명 *'),
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
                            const Icon(Icons.location_on,
                                size: 14, color: AdminTheme.gold),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _venueAddress!,
                                style: AdminTheme.sans(
                                    fontSize: 12,
                                    color: AdminTheme.textSecondary),
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _venueAddress = null),
                              child: const Icon(Icons.close,
                                  size: 14, color: AdminTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // 날짜/시간
                    Row(
                      children: [
                        Text('공연 일시:',
                            style: AdminTheme.sans(
                                fontSize: 13,
                                color: AdminTheme.textSecondary)),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startAt,
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date == null) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(_startAt),
                            );
                            if (time == null) return;
                            setState(() {
                              _startAt = DateTime(date.year, date.month,
                                  date.day, time.hour, time.minute);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AdminTheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: AdminTheme.border, width: 0.5),
                            ),
                            child: Text(
                              DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR')
                                  .format(_startAt),
                              style: AdminTheme.sans(
                                  fontSize: 13, color: AdminTheme.gold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 포스터
                    Row(
                      children: [
                        Text('포스터:',
                            style: AdminTheme.sans(
                                fontSize: 13,
                                color: AdminTheme.textSecondary)),
                        const SizedBox(width: 12),
                        if (_posterBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(_posterBytes!,
                                width: 48, height: 64, fit: BoxFit.cover),
                          )
                        else
                          TextButton.icon(
                            onPressed: _pickPoster,
                            icon: const Icon(Icons.image_outlined, size: 16),
                            label: const Text('업로드'),
                            style: TextButton.styleFrom(
                                foregroundColor: AdminTheme.gold),
                          ),
                        if (_posterBytes != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () =>
                                setState(() => _posterBytes = null),
                            icon: const Icon(Icons.close,
                                size: 16, color: AdminTheme.textTertiary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 공연 유형 (네이버 전용 vs 놀티켓 연계)
                    Text('공연 유형',
                        style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _naverOnly = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
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
                                  Icon(Icons.storefront_rounded,
                                      size: 20,
                                      color: _naverOnly
                                          ? AdminTheme.gold
                                          : AdminTheme.textTertiary),
                                  const SizedBox(height: 6),
                                  Text('네이버 전용',
                                      style: AdminTheme.sans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _naverOnly
                                              ? AdminTheme.gold
                                              : AdminTheme.textTertiary)),
                                  const SizedBox(height: 2),
                                  Text('좌석봇 자동배정',
                                      style: AdminTheme.sans(
                                          fontSize: 9,
                                          color: _naverOnly
                                              ? AdminTheme.gold
                                                  .withValues(alpha: 0.7)
                                              : AdminTheme.textTertiary)),
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
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
                                  Icon(Icons.link_rounded,
                                      size: 20,
                                      color: !_naverOnly
                                          ? AdminTheme.gold
                                          : AdminTheme.textTertiary),
                                  const SizedBox(height: 6),
                                  Text('놀티켓 연계',
                                      style: AdminTheme.sans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: !_naverOnly
                                              ? AdminTheme.gold
                                              : AdminTheme.textTertiary)),
                                  const SizedBox(height: 2),
                                  Text('기존 봇 처리',
                                      style: AdminTheme.sans(
                                          fontSize: 9,
                                          color: !_naverOnly
                                              ? AdminTheme.gold
                                                  .withValues(alpha: 0.7)
                                              : AdminTheme.textTertiary)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 등급별 가격
                    Text('등급별 가격',
                        style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
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
                                      color: AdminTheme.textTertiary),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(grade,
                                  style: AdminTheme.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: enabled
                                          ? AdminTheme.textPrimary
                                          : AdminTheme.textTertiary)),
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
                                        vertical: 4),
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

                    // 등록 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isCreatingEvent ? null : _createEvent,
                        child: _isCreatingEvent
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AdminTheme.onAccent),
                              )
                            : const Text('공연 등록'),
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
            Text('기존 공연 선택',
                style: AdminTheme.sans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...events.map((doc) {
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
                      _currentStep = 2; // 좌석 이미 있으면 바로 주문으로
                    });
                    // 좌석 유무 확인
                    _checkSeatsAndNavigate(doc.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AdminTheme.card,
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: AdminTheme.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: AdminTheme.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text('$venue  ·  $dateStr',
                                  style: AdminTheme.sans(
                                      fontSize: 11,
                                      color: AdminTheme.textTertiary)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: AdminTheme.textTertiary),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider(color: AdminTheme.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('또는',
                      style: AdminTheme.sans(
                          fontSize: 11, color: AdminTheme.textTertiary)),
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

  static const _myStoreUrl =
      'https://smartstore.naver.com/melon_symphony_orchestra';

  Future<void> _fetchMyStore() async {
    setState(() {
      _isFetchingStore = true;
      _storeProducts = [];
    });

    try {
      // Firestore naverProducts 컬렉션에서 봇이 동기화한 상품 목록 읽기
      final snap = await FirebaseFirestore.instance
          .collection('naverProducts')
          .orderBy('syncedAt', descending: true)
          .get();

      final products = snap.docs.map((doc) {
        final d = doc.data();
        return <String, dynamic>{
          'title': d['name'] ?? '',
          'price': d['price'] ?? 0,
          'url': d['url'] ?? '',
          'productNo': d['productNo'] ?? '',
        };
      }).toList();

      setState(() => _storeProducts = products);

      if (products.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동기화된 상품이 없습니다. 봇이 실행 중인지 확인하세요.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('상품 조회 실패: $e')),
      );
    } finally {
      setState(() => _isFetchingStore = false);
    }
  }

  Future<void> _selectStoreProduct(Map<String, dynamic> product) async {
    final productUrl = product['url'] as String? ?? '';
    setState(() {
      _naverProductUrl = productUrl;
      _titleCtrl.text = product['title'] as String? ?? '';
      _storeProducts = []; // 목록 닫기
    });

    // 상세 정보 가져오기 (옵션/가격)
    if (productUrl.isNotEmpty) {
      await _fetchNaverProductByUrl(productUrl);
    }
  }

  Future<void> _fetchNaverProductByUrl(String url) async {
    if (url.isEmpty || !url.contains('smartstore.naver.com')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네이버 스마트스토어 URL을 입력하세요')),
      );
      return;
    }

    setState(() => _isFetchingProduct = true);

    try {
      final fs = ref.read(functionsServiceProvider);
      final result = await fs.callHttpFunction('scrapeNaverProductHttp', {
        'url': url,
      });

      if (result['success'] == true && result['product'] != null) {
        final p = result['product'] as Map<String, dynamic>;
        setState(() {
          if (p['title'] != null && (p['title'] as String).isNotEmpty) {
            _titleCtrl.text = p['title'];
          }
          _naverProductUrl = url;

          // 옵션에서 등급+가격 추출
          final options = p['options'] as List<dynamic>? ?? [];
          if (options.isNotEmpty) {
            _enabledGrades.clear();
            for (final opt in options) {
              final name = (opt['name'] as String? ?? '').toUpperCase();
              for (final grade in _gradeOrder) {
                if (name.contains(grade)) {
                  _enabledGrades.add(grade);
                  final price = opt['price'] as int? ?? 0;
                  if (price > 0) {
                    _gradePriceControllers[grade]?.text = price.toString();
                  }
                  break;
                }
              }
            }
          }
        });

        // 포스터 이미지 URL → bytes
        final imageUrl = p['imageUrl'] as String? ?? '';
        if (imageUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(imageUrl));
            if (response.statusCode == 200) {
              setState(() => _posterBytes = response.bodyBytes);
            }
          } catch (_) {}
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상품 정보를 가져왔습니다')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('가져오기 실패: $e')),
      );
    } finally {
      setState(() => _isFetchingProduct = false);
    }
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

  // ── 카카오 키워드 검색으로 공연장 주소 찾기 ──
  Future<void> _showVenueSearchDialog() async {
    final searchCtrl = TextEditingController(text: _venueNameCtrl.text);
    List<Map<String, dynamic>> results = [];
    bool isSearching = false;

    Future<List<Map<String, dynamic>>> searchKakao(String query) async {
      // Cloud Function 프록시 경유 (CORS 우회)
      final url = Uri.parse(
        'https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net/searchAddressHttp'
        '?q=${Uri.encodeComponent(query)}',
      );
      final resp = await http.get(url);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['results'] as List? ?? []).cast<Map<String, dynamic>>();
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1F),
              title: Text('주소 검색',
                  style: AdminTheme.sans(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
                height: 400,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            style: AdminTheme.sans(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: '장소명 또는 주소 검색',
                            ),
                            onSubmitted: (_) async {
                              if (searchCtrl.text.trim().isEmpty) return;
                              setDialogState(() => isSearching = true);
                              results =
                                  await searchKakao(searchCtrl.text.trim());
                              setDialogState(() => isSearching = false);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                          onPressed: () async {
                            if (searchCtrl.text.trim().isEmpty) return;
                            setDialogState(() => isSearching = true);
                            results =
                                await searchKakao(searchCtrl.text.trim());
                            setDialogState(() => isSearching = false);
                          },
                          child: const Text('검색'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isSearching)
                      const Expanded(
                        child: Center(
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else if (results.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('장소명 또는 주소를 검색하세요',
                              style: AdminTheme.sans(
                                  fontSize: 13,
                                  color: AdminTheme.textSecondary)),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: Color(0xFF2A2A2F)),
                          itemBuilder: (_, i) {
                            final r = results[i];
                            final name = r['place_name'] ?? '';
                            final addr =
                                r['road_address_name'] ?? r['address_name'] ?? '';
                            final phone = r['phone'] ?? '';
                            return ListTile(
                              dense: true,
                              title: Text(name,
                                  style: AdminTheme.sans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(addr,
                                      style: AdminTheme.sans(
                                          fontSize: 12,
                                          color: AdminTheme.textSecondary)),
                                  if (phone.isNotEmpty)
                                    Text(phone,
                                        style: AdminTheme.sans(
                                            fontSize: 11,
                                            color: AdminTheme.textSecondary)),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 18, color: AdminTheme.gold),
                              onTap: () => Navigator.pop(ctx, r),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('취소',
                      style: AdminTheme.sans(
                          fontSize: 13, color: AdminTheme.textSecondary)),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _venueNameCtrl.text = selected['place_name'] ?? '';
        _venueAddress =
            selected['road_address_name'] ?? selected['address_name'] ?? '';
      });
    }
  }

  Future<void> _createEvent() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공연명을 입력하세요')),
      );
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
            'events/posters/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await storageRef.putData(
            _posterBytes!, SettableMetadata(contentType: 'image/jpeg'));
        imageUrl = await storageRef.getDownloadURL();
      }

      final event = Event(
        id: '',
        venueId: '',
        title: _titleCtrl.text.trim(),
        description: '',
        startAt: _startAt,
        revealAt: _startAt.subtract(const Duration(hours: 1)),
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
      final extraFields = <String, dynamic>{
        'naverOnly': _naverOnly,
      };
      if (_naverProductUrl != null && _naverProductUrl!.isNotEmpty) {
        extraFields['naverProductUrl'] = _naverProductUrl;
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공연이 등록되었습니다')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingEvent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
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
              Text('Step 2',
                  style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
              const SizedBox(height: 4),
              Text('좌석 등록',
                  style: AdminTheme.serif(fontSize: 22)),
              const SizedBox(height: 4),
              Text('네이버 스마트스토어의 좌석현황 엑셀을 업로드하세요',
                  style: AdminTheme.sans(
                      fontSize: 13, color: AdminTheme.textTertiary)),
              const SizedBox(height: 32),

              // 엑셀 업로드 영역
              GestureDetector(
                onTap: _isParsingSeat ? null : _pickSeatExcel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: AdminTheme.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _seatData != null
                          ? AdminTheme.success
                          : _seatError != null
                              ? AdminTheme.error
                              : AdminTheme.border,
                      width: _seatData != null || _seatError != null ? 1 : 0.5,
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
                                      : '엑셀 파일 선택 (.xlsx)',
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
                                    fontSize: 12, color: AdminTheme.textTertiary),
                              ),
                            ],
                            if (_seatError != null) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  _seatError!,
                                  style: AdminTheme.sans(
                                      fontSize: 12, color: AdminTheme.error),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
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
                          const Icon(Icons.analytics_outlined,
                              size: 14, color: AdminTheme.success),
                          const SizedBox(width: 6),
                          Text('파싱 결과',
                              style: AdminTheme.sans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AdminTheme.success)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _parseDetailRow(
                        '감지 형식',
                        _formatName(_parseResult!.detectedFormat),
                      ),
                      _parseDetailRow(
                        '총 좌석',
                        '${_seatData!.totalSeats}석',
                      ),
                      _parseDetailRow(
                        '등급별',
                        _seatData!.gradeSummary,
                      ),
                    ],
                  ),
                ),

                // 버튼 영역 — 파싱 결과 바로 아래
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AdminTheme.gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AdminTheme.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 0),
                        child: const Text('← 이전'),
                        style: TextButton.styleFrom(
                            foregroundColor: AdminTheme.textSecondary),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: !_isUploadingSeats ? _uploadSeats : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: AdminTheme.gold),
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        child: _isUploadingSeats
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AdminTheme.gold),
                              )
                            : Text('좌석 등록',
                                style: AdminTheme.sans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _currentStep = 2),
                        icon: const Icon(Icons.arrow_forward_rounded,
                            size: 18),
                        label: Text('다음 단계',
                            style: AdminTheme.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminTheme.gold,
                          foregroundColor: Colors.black,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
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
                    childrenPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    initiallyExpanded: false,
                    dense: true,
                    title: Text(
                        '디버그 정보 (${_parseResult!.warnings.length}건)',
                        style: AdminTheme.sans(
                            fontSize: 10,
                            color: AdminTheme.textTertiary)),
                    children: [
                      for (final w in _parseResult!.warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 10,
                                  color: AdminTheme.textTertiary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(w,
                                    style: AdminTheme.sans(
                                        fontSize: 10,
                                        color: AdminTheme.textTertiary)),
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
                          foregroundColor: AdminTheme.textSecondary),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _currentStep = 2),
                      child: const Text('건너뛰기 →'),
                      style: TextButton.styleFrom(
                          foregroundColor: AdminTheme.textTertiary),
                    ),
                  ],
                ),
              ],

              // 등급별 좌석 상세 (로드 성공 시)
              if (_seatData != null && _seatData!.seats.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildSeatDetailSection(),
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
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: AdminTheme.warning),
                          const SizedBox(width: 6),
                          Text('좌석 수가 너무 적습니다',
                              style: AdminTheme.sans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AdminTheme.warning)),
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
                      Text('지원 형식',
                          style: AdminTheme.sans(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        '• 네이버 좌석현황: 좌석등급/층/열/좌석번호 (VIP석, R석, S석, A석)\n'
                        '• 리스트: 구역/층/열/번호/등급 컬럼\n'
                        '• 비주얼: 셀 위치 = 좌석 위치, 값 = 등급 (VIP/R/S/A)\n'
                        '• 행열: 행 = 좌석열, 열 = 좌석번호, 값 = 등급',
                        style: AdminTheme.sans(
                            fontSize: 11,
                            color: AdminTheme.textTertiary,
                            height: 1.6),
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
      gradeRows[grade]!.add(_SeatRow(
        grade: grade,
        floor: parts[1],
        zone: parts[2],
        row: parts[3],
        seats: entry.value,
      ));
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
    final activeGrades =
        gradeOrder.where((g) => gradeRows.containsKey(g)).toList();

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
              const Icon(Icons.event_seat_outlined,
                  size: 14, color: AdminTheme.gold),
              const SizedBox(width: 6),
              Text('상품별 좌석현황',
                  style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.gold)),
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
                  final totalSeats =
                      rows.fold<int>(0, (sum, r) => sum + r.seats.length);
                  final color =
                      _gradeColors[grade] ?? AdminTheme.textSecondary;
                  return SizedBox(
                    width: 280,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: color.withValues(alpha: 0.2), width: 0.5),
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
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text('$grade석',
                                    style: AdminTheme.sans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                              const SizedBox(width: 8),
                              Text('$totalSeats석',
                                  style: AdminTheme.sans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: color)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 테이블 헤더
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 40,
                                    child: Text('구역',
                                        style: AdminTheme.sans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: AdminTheme
                                                .textTertiary))),
                                SizedBox(
                                    width: 30,
                                    child: Text('열',
                                        style: AdminTheme.sans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: AdminTheme
                                                .textTertiary))),
                                SizedBox(
                                    width: 30,
                                    child: Text('수량',
                                        style: AdminTheme.sans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: AdminTheme
                                                .textTertiary))),
                                Expanded(
                                    child: Text('좌석번호',
                                        style: AdminTheme.sans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: AdminTheme
                                                .textTertiary))),
                              ],
                            ),
                          ),
                          // 좌석 행 목록
                          ...rows.map((sr) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    SizedBox(
                                        width: 40,
                                        child: Text(
                                            sr.zone.isEmpty ? '-' : sr.zone,
                                            style: AdminTheme.sans(
                                                fontSize: 9,
                                                color: AdminTheme
                                                    .textTertiary))),
                                    SizedBox(
                                        width: 30,
                                        child: Text('${sr.row}',
                                            style: AdminTheme.sans(
                                                fontSize: 9,
                                                color: AdminTheme
                                                    .textPrimary))),
                                    SizedBox(
                                        width: 30,
                                        child: Text('${sr.seats.length}',
                                            style: AdminTheme.sans(
                                                fontSize: 9,
                                                color: AdminTheme
                                                    .textTertiary))),
                                    Expanded(
                                        child: Text(
                                            _compactRange(sr.seats),
                                            style: AdminTheme.sans(
                                                fontSize: 9,
                                                color: AdminTheme
                                                    .textTertiary),
                                            overflow:
                                                TextOverflow.ellipsis)),
                                  ],
                                ),
                              )),
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
              style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textTertiary),
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

  Future<void> _pickSeatExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    setState(() {
      _isParsingSeat = true;
      _seatError = null;
      _seatData = null;
      _parseResult = null;
    });

    // Brief delay so user sees the loading state
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final parseResult =
          EnhancedExcelParser.parse(result.files.single.bytes!.toList());

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

  Future<void> _uploadSeats() async {
    if (_seatData == null) return;
    if (_createdEventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 Step 1에서 공연을 등록해주세요')),
      );
      return;
    }
    setState(() => _isUploadingSeats = true);

    try {
      final seatRepo = ref.read(seatRepositoryProvider);
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
        _currentStep = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${seatList.length}석 등록 완료')),
      );
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
            Text('먼저 공연을 등록하세요',
                style: AdminTheme.sans(color: AdminTheme.textSecondary)),
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
              Text('Step 3',
                  style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
              const SizedBox(height: 4),
              Text('주문 입력',
                  style: AdminTheme.serif(fontSize: 22)),
              const SizedBox(height: 4),
              Text('네이버 스토어 주문 정보를 입력하세요',
                  style: AdminTheme.sans(
                      fontSize: 13, color: AdminTheme.textTertiary)),
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
                      decoration:
                          const InputDecoration(labelText: '네이버 주문번호 *'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buyerNameCtrl,
                            style: AdminTheme.sans(fontSize: 14),
                            decoration:
                                const InputDecoration(labelText: '구매자명 *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _buyerPhoneCtrl,
                            style: AdminTheme.sans(fontSize: 14),
                            decoration:
                                const InputDecoration(labelText: '연락처 *'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // 등급 선택
                        Text('등급:',
                            style: AdminTheme.sans(
                                fontSize: 13,
                                color: AdminTheme.textSecondary)),
                        const SizedBox(width: 12),
                        ...(_enabledGrades.toList()
                              ..sort((a, b) => _gradeOrder
                                  .indexOf(a)
                                  .compareTo(_gradeOrder.indexOf(b))))
                            .map((grade) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(grade,
                                        style: AdminTheme.sans(fontSize: 12)),
                                    selected: _selectedGrade == grade,
                                    onSelected: (v) {
                                      if (v) {
                                        setState(
                                            () => _selectedGrade = grade);
                                      }
                                    },
                                    selectedColor: AdminTheme.gold,
                                    labelStyle: TextStyle(
                                      color: _selectedGrade == grade
                                          ? AdminTheme.onAccent
                                          : AdminTheme.textPrimary,
                                    ),
                                    side: BorderSide(
                                        color: AdminTheme.border, width: 0.5),
                                  ),
                                )),
                        const Spacer(),
                        // 수량
                        Text('수량:',
                            style: AdminTheme.sans(
                                fontSize: 13,
                                color: AdminTheme.textSecondary)),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20),
                          color: AdminTheme.textSecondary,
                        ),
                        Text('$_quantity',
                            style: AdminTheme.sans(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        IconButton(
                          onPressed: () => setState(() => _quantity++),
                          icon:
                              const Icon(Icons.add_circle_outline, size: 20),
                          color: AdminTheme.gold,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 등록 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _isCreatingOrder ? null : _createNaverOrder,
                        child: _isCreatingOrder
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AdminTheme.onAccent),
                              )
                            : const Text('주문 등록 + 티켓 발급'),
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
                        foregroundColor: AdminTheme.textSecondary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 3),
                    child: const Text('현황 보기 →'),
                    style:
                        TextButton.styleFrom(foregroundColor: AdminTheme.gold),
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
            Text('최근 주문',
                style: AdminTheme.sans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      child: Text('$name  ·  $grade $qty매',
                          style: AdminTheme.sans(fontSize: 12)),
                    ),
                    // SMS status
                    _SmsBadgeInline(orderId: doc.id),
                    const SizedBox(width: 8),
                    Text(
                      createdAt != null
                          ? DateFormat('HH:mm').format(createdAt)
                          : '',
                      style: AdminTheme.sans(
                          fontSize: 11, color: AdminTheme.textTertiary),
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

  Future<void> _createNaverOrder() async {
    final orderId = _orderIdCtrl.text.trim();
    final name = _buyerNameCtrl.text.trim();
    final phone = _buyerPhoneCtrl.text.trim();

    if (orderId.isEmpty || name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주문번호, 이름, 연락처를 모두 입력하세요')),
      );
      return;
    }

    setState(() => _isCreatingOrder = true);

    try {
      final result =
          await ref.read(functionsServiceProvider).createNaverOrder(
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
            content: Text('$name — $_selectedGrade ${tickets.length}장 발급 완료')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreatingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    }
  }

  void _showTicketUrls(String buyerName, List<dynamic> tickets) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$buyerName 티켓 URL',
            style: AdminTheme.serif(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: tickets.map((t) {
            final url = t['url'] as String? ?? '';
            final entry = t['entryNumber'] as int? ?? 0;
            return ListTile(
              dense: true,
              title: Text('#$entry  $_selectedGrade석',
                  style: AdminTheme.sans(fontSize: 13)),
              subtitle: Text(url,
                  style: AdminTheme.sans(
                      fontSize: 10, color: AdminTheme.textTertiary)),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded,
                    size: 16, color: AdminTheme.gold),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('URL 복사됨')),
                  );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL 복사됨')),
                );
              },
              child: const Text('URL 복사'),
            ),
          if (tickets.length > 1)
            TextButton(
              onPressed: () {
                final urls =
                    tickets.map((t) => t['url'] as String? ?? '').join('\n');
                Clipboard.setData(ClipboardData(text: urls));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('전체 URL 복사됨')),
                );
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
            Text('먼저 공연을 등록하세요',
                style: AdminTheme.sans(color: AdminTheme.textSecondary)),
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
              Text('Step 4',
                  style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
              const SizedBox(height: 4),
              Text('현황',
                  style: AdminTheme.serif(fontSize: 22)),
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
                        foregroundColor: AdminTheme.textSecondary),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => context
                        .go('/events/$_createdEventId/naver-orders'),
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
              child: Text('좌석 미등록',
                  style: AdminTheme.sans(color: AdminTheme.textTertiary)),
            ),
          );
        }

        // 등급별 집계
        final gradeStats = <String, Map<String, int>>{};
        for (final doc in seats) {
          final d = doc.data() as Map<String, dynamic>;
          final grade = d['grade'] as String? ?? '기타';
          final status = d['status'] as String? ?? 'available';
          gradeStats.putIfAbsent(grade, () => {'total': 0, 'available': 0, 'reserved': 0});
          gradeStats[grade]!['total'] = (gradeStats[grade]!['total'] ?? 0) + 1;
          if (status == 'available') {
            gradeStats[grade]!['available'] = (gradeStats[grade]!['available'] ?? 0) + 1;
          } else {
            gradeStats[grade]!['reserved'] = (gradeStats[grade]!['reserved'] ?? 0) + 1;
          }
        }

        final sortedGrades = gradeStats.keys.toList()
          ..sort((a, b) => _gradeOrder.indexOf(a).compareTo(_gradeOrder.indexOf(b)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('등급별 좌석 현황',
                style: AdminTheme.sans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...sortedGrades.map((grade) {
              final stats = gradeStats[grade]!;
              final total = stats['total'] ?? 0;
              final reserved = stats['reserved'] ?? 0;
              final available = stats['available'] ?? 0;
              final ratio = total > 0 ? reserved / total : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        Text(grade,
                            style: AdminTheme.sans(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('$reserved / $total',
                            style: AdminTheme.sans(
                                fontSize: 13, color: AdminTheme.gold)),
                        Text('  ($available 잔여)',
                            style: AdminTheme.sans(
                                fontSize: 11,
                                color: AdminTheme.textTertiary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ratio,
                        backgroundColor: AdminTheme.surface,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AdminTheme.gold),
                        minHeight: 4,
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
            0, (sum, d) => sum + ((d.data() as Map)['quantity'] as int? ?? 0));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('주문 목록',
                    style: AdminTheme.sans(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('$confirmed건  ·  $totalTickets매',
                    style: AdminTheme.sans(
                        fontSize: 12, color: AdminTheme.gold)),
              ],
            ),
            const SizedBox(height: 8),
            if (orders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('주문 없음',
                      style:
                          AdminTheme.sans(color: AdminTheme.textTertiary)),
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
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AdminTheme.card,
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: AdminTheme.border, width: 0.5),
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
                        child: Text('$name  ·  $grade $qty매',
                            style: AdminTheme.sans(fontSize: 12)),
                      ),
                      _SmsBadgeInline(orderId: doc.id),
                      const SizedBox(width: 8),
                      Text(
                        createdAt != null
                            ? DateFormat('MM.dd HH:mm').format(createdAt)
                            : '',
                        style: AdminTheme.sans(
                            fontSize: 11, color: AdminTheme.textTertiary),
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
  const _StepIndicator({required this.currentStep, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(labels.length, (i) {
        final isActive = i == currentStep;
        final isDone = i < currentStep;
        return Row(
          children: [
            if (i > 0)
              Container(
                width: 16,
                height: 1,
                color: isDone ? AdminTheme.gold : AdminTheme.border,
              ),
            Container(
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
          ],
        );
      }),
    );
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
          .map((s) => {
                'block': s.zone,
                'floor': s.floor,
                'row': s.row,
                'number': s.number,
                'grade': s.grade,
              })
          .toList(),
      totalSeats: result.seats.length,
      gradeSummary: summary,
    );
  }

  List<Map<String, String>> toSeatDataList() {
    return seats
        .map((s) => {
              'block': s['block']?.toString() ?? '',
              'floor': s['floor']?.toString() ?? '1층',
              'row': s['row']?.toString() ?? '',
              'number': s['number']?.toString() ?? '',
              'grade': s['grade']?.toString() ?? 'S',
            })
        .toList();
  }
}

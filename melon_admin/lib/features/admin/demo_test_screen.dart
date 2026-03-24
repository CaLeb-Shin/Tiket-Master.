import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' if (dart.library.io) 'demo_test_stub.dart' as html;

import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/services/auth_service.dart';

// =============================================================================
// M 티켓 E2E 테스트 — 네이버 구매 → 공연 종료 전체 플로우
// 버튼 하나로 자동 실행 + 각 단계에서 모바일 확인 가능
// =============================================================================

const _ticketBaseUrl = 'https://melonticket-web-20260216.vercel.app/m/';

class DemoTestScreen extends ConsumerStatefulWidget {
  const DemoTestScreen({super.key});

  @override
  ConsumerState<DemoTestScreen> createState() => _DemoTestScreenState();
}

enum _Step {
  selectEvent,
  createOrder,
  seatReveal,
  entry,
  intermission,
  part2,
  ended,
  done,
}

class _DemoTestScreenState extends ConsumerState<DemoTestScreen> {
  _Step _step = _Step.selectEvent;
  bool _loading = false;
  bool _paused = false;
  String _statusMsg = '';

  // 데이터
  Event? _selectedEvent;
  String? _naverOrderDocId;
  String? _mobileTicketId;
  String? _accessToken;
  String? _ticketUrl;

  final _logs = <String>[];

  void _log(String msg) {
    setState(() {
      _logs.add('[${DateFormat('HH:mm:ss').format(DateTime.now())}] $msg');
    });
  }

  void _reset() {
    setState(() {
      _step = _Step.selectEvent;
      _loading = false;
      _paused = false;
      _statusMsg = '';
      _selectedEvent = null;
      _naverOrderDocId = null;
      _mobileTicketId = null;
      _accessToken = null;
      _ticketUrl = null;
      _logs.clear();
    });
  }

  // ══════════════════════════════════════════
  // 자동 실행 엔진
  // ══════════════════════════════════════════

  Future<void> _runAutoFlow() async {
    // Step 2: 주문 생성
    await _doCreateOrder();
    if (!mounted) return;

    // 일시정지: 모바일 티켓 확인
    _paused = true;
    setState(() {});
    return; // 사용자가 "계속" 누르면 _continueFlow 호출
  }

  Future<void> _continueFlow() async {
    _paused = false;
    setState(() {});

    switch (_step) {
      case _Step.createOrder:
        await _doPhaseTransition(_Step.seatReveal, 'seatReveal', '좌석 공개');
        break;
      case _Step.seatReveal:
        await _doEntryWithCheckIn();
        break;
      case _Step.entry:
        await _doPhaseTransition(_Step.intermission, 'intermission', '인터미션');
        break;
      case _Step.intermission:
        await _doPhaseTransition(_Step.part2, 'part2', '2부');
        // part2는 자동으로 ended로 진행
        if (mounted) {
          await Future.delayed(const Duration(seconds: 1));
          await _doPhaseTransition(_Step.ended, 'ended', '공연 종료');
        }
        break;
      case _Step.ended:
        setState(() => _step = _Step.done);
        _log('전체 플로우 완료!');
        return;
      default:
        return;
    }

    if (!mounted) return;
    _paused = true;
    setState(() {});
  }

  // ══════════════════════════════════════════
  // 각 단계 실행 로직
  // ══════════════════════════════════════════

  Future<void> _doCreateOrder() async {
    if (_loading || _selectedEvent == null) return;
    setState(() {
      _loading = true;
      _statusMsg = '테스트 주문 생성 중...';
    });

    try {
      final functions = ref.read(functionsServiceProvider);
      final event = _selectedEvent!;

      _log('createNaverOrder 호출');
      _log('  eventId: ${event.id}');
      _log('  buyerName: 테스트관객');
      _log('  seatGrade: ${_getDefaultGrade(event)}');

      final result = await functions.createNaverOrder(
        eventId: event.id,
        naverOrderId: 'E2E-${DateTime.now().millisecondsSinceEpoch}',
        buyerName: '테스트관객',
        buyerPhone: '010-0000-0001',
        productName: '${event.title} (E2E 테스트)',
        seatGrade: _getDefaultGrade(event),
        quantity: 1,
        orderDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );

      _naverOrderDocId = result['orderId'] as String?;
      _log('주문 생성 완료: $_naverOrderDocId');

      // 티켓 정보 추출
      final tickets = result['tickets'] as List<dynamic>?;
      if (tickets != null && tickets.isNotEmpty) {
        final ticket = tickets.first as Map<String, dynamic>;
        _mobileTicketId = ticket['ticketId'] as String?;
        _accessToken = ticket['accessToken'] as String?;
        if (_accessToken != null) {
          _ticketUrl = '$_ticketBaseUrl$_accessToken';
        }
        _log('M 티켓 발급: $_mobileTicketId');
        _log('티켓 URL: $_ticketUrl');
      } else {
        _log('⚠ 티켓 정보 없음 — Firestore에서 조회');
        // fallback: Firestore에서 직접 조회
        if (_naverOrderDocId != null) {
          final mtSnap = await FirebaseFirestore.instance
              .collection('mobileTickets')
              .where('naverOrderId', isEqualTo: _naverOrderDocId)
              .limit(1)
              .get();
          if (mtSnap.docs.isNotEmpty) {
            final mtDoc = mtSnap.docs.first;
            _mobileTicketId = mtDoc.id;
            _accessToken = mtDoc.data()['accessToken'] as String?;
            if (_accessToken != null) {
              _ticketUrl = '$_ticketBaseUrl$_accessToken';
            }
            _log('Firestore 조회 성공: $_mobileTicketId');
            _log('티켓 URL: $_ticketUrl');
          }
        }
      }

      setState(() {
        _loading = false;
        _statusMsg = '';
        _step = _Step.createOrder;
      });
    } catch (e) {
      _log('오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '오류: $e';
      });
    }
  }

  Future<void> _doPhaseTransition(_Step nextStep, String phaseName, String label) async {
    if (_loading || _selectedEvent == null) return;
    setState(() {
      _loading = true;
      _statusMsg = '$label 전환 중...';
    });

    try {
      final eventRepo = ref.read(eventRepositoryProvider);
      final eventId = _selectedEvent!.id;

      final updates = <String, dynamic>{
        'livePhase': phaseName,
        'livePhaseUpdatedAt': FieldValue.serverTimestamp(),
      };

      // seatReveal 단계 → 자동 revealAt 트리거
      if (phaseName == 'seatReveal') {
        updates['revealAt'] = Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 1)));
        _log('revealAt 자동 트리거 → 좌석/QR 공개');
      }

      await eventRepo.updateEvent(eventId, updates);
      _log('livePhase → $phaseName ($label)');

      setState(() {
        _loading = false;
        _statusMsg = '';
        _step = nextStep;
      });
    } catch (e) {
      _log('오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '오류: $e';
      });
    }
  }

  Future<void> _doEntryWithCheckIn() async {
    // 먼저 livePhase → entry
    await _doPhaseTransition(_Step.entry, 'entry', '입장 중');
    if (!mounted || _mobileTicketId == null || _accessToken == null) return;

    setState(() {
      _loading = true;
      _statusMsg = 'QR 발급 + 체크인 처리 중...';
    });

    try {
      final functions = ref.read(functionsServiceProvider);
      final user = ref.read(authStateProvider).value;
      final staffId = user?.uid ?? 'demo-staff';

      // QR 토큰 발급
      _log('issueMobileQrToken 호출');
      final qrResult = await functions.issueMobileQrToken(
        ticketId: _mobileTicketId!,
        accessToken: _accessToken!,
      );
      final qrToken = qrResult['token'] as String?;
      _log('QR 토큰: ${qrToken ?? "없음"}');

      if (qrToken != null) {
        // 자동 체크인
        _log('verifyAndCheckIn 호출 (셀프 스캔)');
        final checkResult = await functions.verifyAndCheckIn(
          ticketId: 'mt_$_mobileTicketId',
          qrToken: qrToken,
          staffId: staffId,
          scannerDeviceId: 'admin-e2e-test',
          checkinStage: 'entry',
        );
        final success = checkResult['success'] == true;
        _log('체크인 결과: ${success ? "SUCCESS" : "FAIL"}');
        if (checkResult['message'] != null) {
          _log('  메시지: ${checkResult['message']}');
        }
      }

      setState(() {
        _loading = false;
        _statusMsg = '';
      });
    } catch (e) {
      _log('체크인 오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '체크인 오류 (계속 진행 가능): $e';
      });
    }
  }

  Future<void> _doCleanup() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _statusMsg = '테스트 데이터 삭제 중...';
    });

    try {
      final db = FirebaseFirestore.instance;

      // 1. 모바일 티켓 삭제
      if (_mobileTicketId != null) {
        await db.collection('mobileTickets').doc(_mobileTicketId).delete();
        _log('삭제: mobileTickets/$_mobileTicketId');
      }

      // 2. 네이버 주문 삭제
      if (_naverOrderDocId != null) {
        await db.collection('naverOrders').doc(_naverOrderDocId).delete();
        _log('삭제: naverOrders/$_naverOrderDocId');
      }

      // 3. 체크인 기록 삭제
      if (_mobileTicketId != null) {
        final checkinSnap = await db
            .collection('checkins')
            .where('ticketId', isEqualTo: 'mt_$_mobileTicketId')
            .get();
        for (final doc in checkinSnap.docs) {
          await doc.reference.delete();
          _log('삭제: checkins/${doc.id}');
        }
      }

      // 4. livePhase 리셋
      if (_selectedEvent != null) {
        final eventRepo = ref.read(eventRepositoryProvider);
        await eventRepo.updateEvent(_selectedEvent!.id, {
          'livePhase': 'pre',
          'livePhaseUpdatedAt': FieldValue.serverTimestamp(),
        });
        _log('livePhase → pre (리셋)');
      }

      _log('테스트 데이터 정리 완료');

      setState(() {
        _loading = false;
        _statusMsg = '';
      });
    } catch (e) {
      _log('정리 오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '정리 오류: $e';
      });
    }
  }

  String _getDefaultGrade(Event event) {
    final grades = event.priceByGrade;
    if (grades != null && grades.isNotEmpty) {
      // VIP → R → S → A 순서로 우선
      for (final g in ['S', 'A', 'R', 'VIP']) {
        if (grades.containsKey(g)) return g;
      }
      return grades.keys.first;
    }
    return 'S';
  }

  // ══════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStepIndicator(),
                        const SizedBox(height: 24),
                        _buildCurrentStep(),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: AdminTheme.surface,
                    border: Border(
                      left: BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                  ),
                  child: _buildLogPanel(),
                ),
              ],
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
        left: 4, right: 16, bottom: 12,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.background.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(color: AdminTheme.border, width: 0.5),
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
            icon: const Icon(Icons.west, color: AdminTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('E2E TEST',
                    style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
                const SizedBox(height: 2),
                Text('M 티켓 전체 플로우 (네이버 구매 → 공연 종료)',
                    style: AdminTheme.sans(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: AdminTheme.textPrimary,
                    )),
              ],
            ),
          ),
          if (_step != _Step.selectEvent)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text('처음부터',
                  style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: AdminTheme.gold),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = [
      ('공연 선택', _Step.selectEvent),
      ('주문+발권', _Step.createOrder),
      ('좌석 공개', _Step.seatReveal),
      ('입장', _Step.entry),
      ('인터미션', _Step.intermission),
      ('2부', _Step.part2),
      ('종료', _Step.ended),
      ('완료', _Step.done),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1,
                  color: _step.index >= steps[i].$2.index
                      ? AdminTheme.gold.withValues(alpha: 0.6)
                      : AdminTheme.border,
                ),
              ),
            _StepDot(
              label: steps[i].$1,
              index: i + 1,
              isActive: _step == steps[i].$2,
              isComplete: _step.index > steps[i].$2.index,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    return switch (_step) {
      _Step.selectEvent => _buildEventSelect(),
      _Step.createOrder => _buildOrderResult(),
      _Step.seatReveal => _buildPhaseStep('좌석 공개', '모바일 티켓에서 좌석과 QR이 공개되었는지 확인하세요', Icons.visibility_rounded, const Color(0xFFA78BFA)),
      _Step.entry => _buildPhaseStep('입장 완료', '모바일 티켓에서 체크인 상태가 반영되었는지 확인하세요', Icons.login_rounded, const Color(0xFF4ADE80)),
      _Step.intermission => _buildPhaseStep('인터미션', '모바일 티켓에서 설문지가 표시되는지 확인하세요', Icons.coffee_rounded, AdminTheme.gold),
      _Step.part2 || _Step.ended => _buildPhaseStep('공연 종료', '모바일 티켓에서 네이버 리뷰 유도 카드가 표시되는지 확인하세요', Icons.flag_rounded, const Color(0xFFF87171)),
      _Step.done => _buildDoneStep(),
    };
  }

  // ─── Step 1: 공연 선택 ───
  Widget _buildEventSelect() {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('테스트할 공연 선택'),
        const SizedBox(height: 8),
        Text('공연을 선택하면 자동으로 전체 플로우가 시작됩니다.',
            style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textSecondary)),
        const SizedBox(height: 16),
        eventsAsync.when(
          data: (events) {
            final active = events.where((e) =>
                e.availableSeats > 0 && e.startAt.isAfter(DateTime.now())).toList();
            if (active.isEmpty) {
              return _infoCard(Icons.info_outline_rounded,
                  '예매 가능한 공연이 없습니다',
                  '공연 관리에서 공연을 먼저 등록해주세요.');
            }
            return Column(
              children: active.map((event) => _eventTile(event)).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: AdminTheme.gold),
            ),
          ),
          error: (e, _) => _infoCard(Icons.error_outline_rounded, '로딩 실패', '$e'),
        ),
      ],
    );
  }

  Widget _eventTile(Event event) {
    final fmt = NumberFormat('#,###');
    final dateFmt = DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedEvent = event);
            _log('공연 선택: ${event.title}');
            _runAutoFlow();
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AdminTheme.border, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 64,
                  decoration: BoxDecoration(
                    color: AdminTheme.cardElevated,
                    borderRadius: BorderRadius.circular(2),
                    image: event.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(event.imageUrl!),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  child: event.imageUrl == null
                      ? const Icon(Icons.music_note_rounded, color: AdminTheme.sage, size: 20)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          style: AdminTheme.sans(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: AdminTheme.textPrimary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(dateFmt.format(event.startAt),
                          style: AdminTheme.sans(fontSize: 12, color: AdminTheme.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${fmt.format(event.price)}원',
                        style: AdminTheme.sans(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AdminTheme.gold)),
                    const SizedBox(height: 2),
                    Text('잔여 ${event.availableSeats}석',
                        style: AdminTheme.sans(fontSize: 11, color: AdminTheme.textSecondary)),
                  ],
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right_rounded, color: AdminTheme.sage, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 2 결과: 주문 + 티켓 URL ───
  Widget _buildOrderResult() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('M 티켓 발급 완료'),
        const SizedBox(height: 12),
        _dataCard([
          _dataRow('주문 ID', _naverOrderDocId ?? '-'),
          _dataRow('티켓 ID', _mobileTicketId ?? '-'),
          _dataRow('Access Token', _accessToken ?? '-'),
        ]),
        if (_ticketUrl != null) ...[
          const SizedBox(height: 16),
          // 티켓 URL 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_iphone_rounded,
                        color: Color(0xFF4ADE80), size: 18),
                    const SizedBox(width: 8),
                    Text('모바일 티켓 URL',
                        style: AdminTheme.sans(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: Color(0xFF4ADE80))),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(_ticketUrl!,
                    style: AdminTheme.sans(fontSize: 12, color: AdminTheme.textPrimary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _smallButton('새 탭에서 열기', Icons.open_in_new_rounded, () {
                      try {
                        html.window.open(_ticketUrl!, '_blank');
                      } catch (_) {
                        _log('새 탭 열기 실패 — URL을 직접 복사하세요');
                      }
                    }),
                    const SizedBox(width: 8),
                    _smallButton('URL 복사', Icons.copy_rounded, () {
                      Clipboard.setData(ClipboardData(text: _ticketUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL 복사됨'), duration: Duration(seconds: 1)),
                      );
                      _log('티켓 URL 클립보드 복사');
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildStatusAndPause('모바일 티켓을 새 탭에서 열어 확인 후 [다음 단계]를 눌러주세요'),
      ],
    );
  }

  // ─── Phase 단계 공통 UI ───
  Widget _buildPhaseStep(String title, String guide, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(guide,
                    style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textPrimary)),
              ),
            ],
          ),
        ),
        if (_ticketUrl != null) ...[
          const SizedBox(height: 12),
          _smallButton('모바일 티켓 열기', Icons.open_in_new_rounded, () {
            try {
              html.window.open(_ticketUrl!, '_blank');
            } catch (_) {}
          }),
        ],
        const SizedBox(height: 20),
        _buildStatusAndPause('확인 후 [다음 단계]를 눌러주세요'),
      ],
    );
  }

  // ─── 완료 ───
  Widget _buildDoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('전체 플로우 완료'),
        const SizedBox(height: 12),
        _infoCard(
          Icons.check_circle_rounded,
          'E2E 테스트 완료',
          '네이버 주문 → M 티켓 발급 → 좌석 공개 → 입장 → 인터미션 → 2부 → 공연 종료\n전체 플로우가 정상 완료되었습니다.',
        ),
        const SizedBox(height: 16),
        _dataCard([
          _dataRow('공연', _selectedEvent?.title ?? '-'),
          _dataRow('주문 ID', _naverOrderDocId ?? '-'),
          _dataRow('티켓 ID', _mobileTicketId ?? '-'),
          _dataRow('티켓 URL', _ticketUrl ?? '-'),
        ]),
        const SizedBox(height: 20),
        if (_statusMsg.isNotEmpty)
          _buildStatusMsg(),
        Row(
          children: [
            Expanded(
              child: _actionButton('테스트 데이터 삭제 + 리셋', Icons.delete_outline_rounded,
                  () async {
                await _doCleanup();
                if (mounted) _reset();
              }, danger: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton('데이터 유지 + 다시 테스트', Icons.replay_rounded, _reset),
            ),
          ],
        ),
      ],
    );
  }

  // ─── 상태 + 일시정지 버튼 ───
  Widget _buildStatusAndPause(String pauseGuide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_statusMsg.isNotEmpty) _buildStatusMsg(),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AdminTheme.gold),
            ),
          ),
        if (!_loading && _paused)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminTheme.gold.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.2)),
                ),
                child: Text(pauseGuide,
                    style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textSecondary)),
              ),
              const SizedBox(height: 12),
              _actionButton('다음 단계 →', Icons.arrow_forward_rounded, _continueFlow),
            ],
          ),
      ],
    );
  }

  Widget _buildStatusMsg() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AdminTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (_loading)
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AdminTheme.gold),
            ),
          if (_loading) const SizedBox(width: 10),
          Expanded(
            child: Text(_statusMsg,
                style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  // ─── 로그 패널 ───
  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('CONSOLE LOG',
                  style: AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
              const Spacer(),
              if (_logs.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _logs.join('\n')));
                    _log('로그 전체 복사됨');
                  },
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.copy_all_rounded, size: 14, color: AdminTheme.sage),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _logs.isEmpty
              ? Center(
                  child: Text('공연을 선택하면 로그가 시작됩니다',
                      style: AdminTheme.sans(fontSize: 12, color: AdminTheme.sage)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final isError = log.contains('오류') || log.contains('FAIL');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(log,
                          style: TextStyle(
                            fontFamily: 'monospace', fontSize: 11,
                            color: isError ? const Color(0xFFFF6B6B) : AdminTheme.textSecondary,
                            height: 1.5,
                          )),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── 공통 위젯 ───

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(title,
            style: AdminTheme.serif(fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(width: 16),
        Expanded(
          child: Divider(
            color: AdminTheme.sage.withValues(alpha: 0.2), thickness: 0.5),
        ),
      ],
    );
  }

  Widget _dataCard(List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: AdminTheme.label(fontSize: 10, color: AdminTheme.sage)),
          ),
          Expanded(
            child: SelectableText(value,
                style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap,
      {bool danger = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _loading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: danger
                ? const Color(0xFFFF6B6B).withValues(alpha: 0.12)
                : AdminTheme.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: danger
                  ? const Color(0xFFFF6B6B).withValues(alpha: 0.3)
                  : AdminTheme.gold.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18,
                  color: danger ? const Color(0xFFFF6B6B) : AdminTheme.gold),
              const SizedBox(width: 8),
              Text(label,
                  style: AdminTheme.sans(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: danger ? const Color(0xFFFF6B6B) : AdminTheme.gold,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallButton(String label, IconData icon, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AdminTheme.border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AdminTheme.sage),
              const SizedBox(width: 6),
              Text(label,
                  style: AdminTheme.sans(fontSize: 12, color: AdminTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(icon, color: AdminTheme.gold, size: 32),
          const SizedBox(height: 12),
          Text(title,
              style: AdminTheme.sans(
                fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ─── Step Dot ───
class _StepDot extends StatelessWidget {
  final String label;
  final int index;
  final bool isActive;
  final bool isComplete;

  const _StepDot({
    required this.label,
    required this.index,
    required this.isActive,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? AdminTheme.gold
                : isComplete
                    ? AdminTheme.gold.withValues(alpha: 0.3)
                    : AdminTheme.cardElevated,
            border: Border.all(
              color: isActive || isComplete
                  ? AdminTheme.gold
                  : AdminTheme.border,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check_rounded, size: 14, color: AdminTheme.gold)
                : Text('$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive ? AdminTheme.onAccent : AdminTheme.textTertiary,
                    )),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
              fontSize: 9,
              color: isActive ? AdminTheme.gold : AdminTheme.textTertiary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            )),
      ],
    );
  }
}

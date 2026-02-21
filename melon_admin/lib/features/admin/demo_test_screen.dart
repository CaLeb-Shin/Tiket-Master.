import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/services/auth_service.dart';

// =============================================================================
// 데모 테스트 화면 — 예매→발권→QR입장→취소/환불 전체 모의 플로우
// 이 파일은 데모 전용이며, 나중에 삭제해도 앱에 영향 없음
// =============================================================================

class DemoTestScreen extends ConsumerStatefulWidget {
  const DemoTestScreen({super.key});

  @override
  ConsumerState<DemoTestScreen> createState() => _DemoTestScreenState();
}

enum _DemoStep { selectEvent, booking, ticketIssued, checkIn, done }

class _DemoTestScreenState extends ConsumerState<DemoTestScreen> {
  _DemoStep _step = _DemoStep.selectEvent;
  bool _loading = false;
  String _statusMsg = '';

  // 결과 데이터
  Event? _selectedEvent;
  String? _orderId;
  String? _ticketId;
  String? _qrData;
  Map<String, dynamic>? _checkInResult;

  final _logs = <String>[];

  void _log(String msg) {
    setState(() {
      _logs.add('[${DateFormat('HH:mm:ss').format(DateTime.now())}] $msg');
    });
  }

  void _reset() {
    setState(() {
      _step = _DemoStep.selectEvent;
      _loading = false;
      _statusMsg = '';
      _selectedEvent = null;
      _orderId = null;
      _ticketId = null;
      _qrData = null;
      _checkInResult = null;
      _logs.clear();
    });
  }

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
                // 왼쪽: 메인 플로우
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
                // 오른쪽: 로그
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
        left: 4,
        right: 16,
        bottom: 12,
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
            icon: const Icon(Icons.west,
                color: AdminTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEMO TEST',
                  style: AdminTheme.label(
                    fontSize: 10,
                    color: AdminTheme.gold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '예매 → 발권 → QR입장 전체 모의 플로우',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AdminTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (_step != _DemoStep.selectEvent)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                '처음부터',
                style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AdminTheme.gold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = [
      ('공연 선택', _DemoStep.selectEvent),
      ('예매/발권', _DemoStep.booking),
      ('티켓 확인', _DemoStep.ticketIssued),
      ('QR 입장', _DemoStep.checkIn),
      ('완료', _DemoStep.done),
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
    switch (_step) {
      case _DemoStep.selectEvent:
        return _buildEventSelect();
      case _DemoStep.booking:
        return _buildBookingStep();
      case _DemoStep.ticketIssued:
        return _buildTicketStep();
      case _DemoStep.checkIn:
        return _buildCheckInStep();
      case _DemoStep.done:
        return _buildDoneStep();
    }
  }

  // ─── Step 1: 공연 선택 ───
  Widget _buildEventSelect() {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('테스트할 공연 선택'),
        const SizedBox(height: 12),
        eventsAsync.when(
          data: (events) {
            final active = events.where((e) =>
                e.availableSeats > 0 && e.startAt.isAfter(DateTime.now()));
            if (active.isEmpty) {
              return _infoCard(
                Icons.info_outline_rounded,
                '예매 가능한 공연이 없습니다',
                '관리 > 새 공연 등록에서 공연을 먼저 만들어 주세요.',
              );
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
          error: (e, _) => _infoCard(
            Icons.error_outline_rounded,
            '공연 목록 로딩 실패',
            '$e',
          ),
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
            setState(() {
              _selectedEvent = event;
              _step = _DemoStep.booking;
            });
            _log('공연 선택: ${event.title}');
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
                // 포스터 썸네일
                Container(
                  width: 48,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AdminTheme.cardElevated,
                    borderRadius: BorderRadius.circular(2),
                    image: event.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(event.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: event.imageUrl == null
                      ? const Icon(Icons.music_note_rounded,
                          color: AdminTheme.sage, size: 20)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: AdminTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFmt.format(event.startAt),
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${fmt.format(event.price)}원',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.gold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '잔여 ${event.availableSeats}석',
                      style: AdminTheme.sans(
                        fontSize: 11,
                        color: AdminTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right_rounded,
                    color: AdminTheme.sage, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 2: 예매/발권 ───
  Widget _buildBookingStep() {
    final event = _selectedEvent!;
    final fmt = NumberFormat('#,###');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('모의 예매'),
        const SizedBox(height: 12),
        _dataCard([
          _dataRow('공연', event.title),
          _dataRow('가격', '${fmt.format(event.price)}원'),
          _dataRow('잔여', '${event.availableSeats}석'),
        ]),
        const SizedBox(height: 16),
        if (_statusMsg.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AdminTheme.gold.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                if (_loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AdminTheme.gold,
                    ),
                  ),
                if (_loading) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusMsg,
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_loading)
          _actionButton(
            '1매 모의 예매 실행',
            Icons.confirmation_number_outlined,
            _doMockBooking,
          ),
      ],
    );
  }

  Future<void> _doMockBooking() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _statusMsg = '주문 생성 중...';
    });

    try {
      final functions = ref.read(functionsServiceProvider);
      final event = _selectedEvent!;

      // 1) 주문 생성
      _log('createOrder 호출 (eventId: ${event.id}, qty: 1)');
      final orderResult = await functions.createOrder(
        eventId: event.id,
        quantity: 1,
      );
      _orderId = orderResult['orderId'] as String;
      _log('주문 생성 완료: $_orderId');

      setState(() => _statusMsg = '결제 확정 및 좌석 배정 중...');

      // 2) 결제 확정 + 좌석 배정
      _log('confirmPaymentAndAssignSeats 호출');
      final confirmResult = await functions.confirmPaymentAndAssignSeats(
        orderId: _orderId!,
      );
      if (confirmResult['success'] != true) {
        throw Exception(confirmResult['error'] ?? '좌석 배정 실패');
      }
      _log('결제 확정 완료');

      // 3) 티켓 ID 가져오기
      final ticketIds = confirmResult['ticketIds'] as List<dynamic>?;
      if (ticketIds != null && ticketIds.isNotEmpty) {
        _ticketId = ticketIds.first as String;
        _log('티켓 발급: $_ticketId');
      } else {
        // Firestore에서 직접 조회
        _log('티켓 ID를 Firestore에서 조회 중...');
        final ticketSnap = await FirebaseFirestore.instance
            .collection('tickets')
            .where('orderId', isEqualTo: _orderId)
            .limit(1)
            .get();
        if (ticketSnap.docs.isNotEmpty) {
          _ticketId = ticketSnap.docs.first.id;
          _log('티켓 조회 성공: $_ticketId');
        }
      }

      setState(() => _statusMsg = 'QR 토큰 발급 중...');

      // 4) QR 토큰 발급
      if (_ticketId != null) {
        _log('issueQrToken 호출');
        final qrResult = await functions.issueQrToken(ticketId: _ticketId!);
        _qrData = qrResult['token'] as String?;
        _log('QR 발급: ${_qrData ?? "데이터 없음"}');
      }

      setState(() {
        _loading = false;
        _statusMsg = '';
        _step = _DemoStep.ticketIssued;
      });
    } catch (e) {
      _log('오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '오류: $e';
      });
    }
  }

  // ─── Step 3: 티켓 확인 ───
  Widget _buildTicketStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('발권 완료'),
        const SizedBox(height: 12),
        _dataCard([
          _dataRow('주문 ID', _orderId ?? '-'),
          _dataRow('티켓 ID', _ticketId ?? '-'),
          _dataRow('QR Data', _qrData ?? '-'),
        ]),
        if (_qrData != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _smallButton('QR 복사', Icons.copy_rounded, () {
                Clipboard.setData(ClipboardData(text: _qrData!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('QR 데이터 복사됨'),
                    duration: Duration(seconds: 1),
                  ),
                );
                _log('QR 데이터 클립보드 복사');
              }),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                'QR 입장 테스트',
                Icons.qr_code_scanner_rounded,
                () {
                  setState(() => _step = _DemoStep.checkIn);
                  _log('QR 입장 단계로 이동');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                '티켓 취소/환불',
                Icons.cancel_outlined,
                _doCancelTicket,
                danger: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _doCancelTicket() async {
    if (_loading || _ticketId == null) return;
    setState(() {
      _loading = true;
      _statusMsg = '티켓 취소 요청 중...';
    });

    try {
      final functions = ref.read(functionsServiceProvider);
      _log('requestTicketCancellation 호출 (ticketId: $_ticketId)');
      final result = await functions.requestTicketCancellation(
        ticketId: _ticketId!,
      );
      _log('취소 결과: $result');

      setState(() {
        _loading = false;
        _statusMsg = '';
        _step = _DemoStep.done;
      });
      _log('티켓 취소 완료 → 테스트 종료');
    } catch (e) {
      _log('취소 오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '취소 오류: $e';
      });
    }
  }

  // ─── Step 4: QR 입장 ───
  Widget _buildCheckInStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('QR 입장 검증'),
        const SizedBox(height: 12),
        _dataCard([
          _dataRow('티켓 ID', _ticketId ?? '-'),
          _dataRow('QR Data', _qrData ?? '-'),
        ]),
        const SizedBox(height: 16),
        if (_statusMsg.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _statusMsg,
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textPrimary,
              ),
            ),
          ),
        ],
        if (_checkInResult != null) ...[
          _dataCard([
            _dataRow('결과', _checkInResult!['success'] == true ? 'SUCCESS' : 'FAIL'),
            if (_checkInResult!['message'] != null)
              _dataRow('메시지', '${_checkInResult!['message']}'),
            if (_checkInResult!['seatInfo'] != null)
              _dataRow('좌석', '${_checkInResult!['seatInfo']}'),
          ]),
          const SizedBox(height: 16),
        ],
        if (!_loading) ...[
          _actionButton(
            '입장 검증 실행 (verifyAndCheckIn)',
            Icons.verified_rounded,
            _doCheckIn,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  '테스트 완료',
                  Icons.check_circle_outline_rounded,
                  () {
                    setState(() => _step = _DemoStep.done);
                    _log('테스트 완료');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  '티켓 취소/환불',
                  Icons.cancel_outlined,
                  _doCancelTicket,
                  danger: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _doCheckIn() async {
    if (_loading || _ticketId == null || _qrData == null) return;
    setState(() {
      _loading = true;
      _statusMsg = '입장 검증 중...';
      _checkInResult = null;
    });

    try {
      final functions = ref.read(functionsServiceProvider);
      final user = ref.read(authStateProvider).value;
      final staffId = user?.uid ?? 'demo-staff';

      _log('verifyAndCheckIn 호출');
      _log('  ticketId: $_ticketId');
      _log('  qrToken: $_qrData');
      _log('  staffId: $staffId');

      final result = await functions.verifyAndCheckIn(
        ticketId: _ticketId!,
        qrToken: _qrData!,
        staffId: staffId,
        scannerDeviceId: 'admin-demo-device',
        checkinStage: 'entry',
      );

      _checkInResult = result;
      _log('입장 검증 결과: $result');

      setState(() {
        _loading = false;
        _statusMsg = '';
      });
    } catch (e) {
      _log('입장 검증 오류: $e');
      setState(() {
        _loading = false;
        _statusMsg = '오류: $e';
      });
    }
  }

  // ─── Step 5: 완료 ───
  Widget _buildDoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('테스트 완료'),
        const SizedBox(height: 12),
        _infoCard(
          Icons.check_circle_rounded,
          '전체 플로우 테스트 완료',
          '예매 → 발권 → QR입장 (또는 취소/환불) 테스트가 완료되었습니다.',
        ),
        const SizedBox(height: 16),
        _actionButton(
          '다시 테스트',
          Icons.replay_rounded,
          _reset,
        ),
      ],
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
            border: Border(
              bottom: BorderSide(color: AdminTheme.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Text(
                'CONSOLE LOG',
                style: AdminTheme.label(
                  fontSize: 10,
                  color: AdminTheme.gold,
                ),
              ),
              const Spacer(),
              if (_logs.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: _logs.join('\n')),
                    );
                    _log('로그 전체 복사됨');
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      Icons.copy_all_rounded,
                      size: 14,
                      color: AdminTheme.sage,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _logs.isEmpty
              ? Center(
                  child: Text(
                    '아직 로그가 없습니다',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.sage,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final isError = log.contains('오류') || log.contains('FAIL');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: isError
                              ? const Color(0xFFFF6B6B)
                              : AdminTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
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
        Text(
          title,
          style: AdminTheme.serif(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Divider(
            color: AdminTheme.sage.withValues(alpha: 0.2),
            thickness: 0.5,
          ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: AdminTheme.label(
                fontSize: 10,
                color: AdminTheme.sage,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool danger = false,
  }) {
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
              Icon(
                icon,
                size: 18,
                color: danger ? const Color(0xFFFF6B6B) : AdminTheme.gold,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AdminTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: danger ? const Color(0xFFFF6B6B) : AdminTheme.gold,
                ),
              ),
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
              Text(
                label,
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: AdminTheme.textSecondary,
                ),
              ),
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
          Text(
            title,
            style: AdminTheme.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AdminTheme.sans(
              fontSize: 13,
              color: AdminTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete
                ? AdminTheme.gold
                : isActive
                    ? AdminTheme.gold.withValues(alpha: 0.2)
                    : AdminTheme.cardElevated,
            border: Border.all(
              color: isActive || isComplete
                  ? AdminTheme.gold
                  : AdminTheme.border,
              width: isActive ? 1.5 : 0.5,
            ),
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF1E1E24))
                : Text(
                    '$index',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? AdminTheme.gold
                          : AdminTheme.sage,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive || isComplete
                ? AdminTheme.textPrimary
                : AdminTheme.sage,
          ),
        ),
      ],
    );
  }
}

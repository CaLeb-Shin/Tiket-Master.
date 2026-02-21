import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/functions_service.dart';

// =============================================================================
// 모의 티켓 생성 — 공연 선택 → 바로 티켓 발급 (마이티켓 디자인 확인용)
// =============================================================================

class MockTicketScreen extends ConsumerStatefulWidget {
  const MockTicketScreen({super.key});

  @override
  ConsumerState<MockTicketScreen> createState() => _MockTicketScreenState();
}

class _MockTicketScreenState extends ConsumerState<MockTicketScreen> {
  bool _loading = false;
  String _statusMsg = '';
  final _results = <_TicketResult>[];

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 왼쪽: 공연 목록
                Expanded(
                  flex: 3,
                  child: eventsAsync.when(
                    data: (events) => _buildEventList(events),
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AdminTheme.gold),
                    ),
                    error: (e, _) => Center(
                      child: Text('오류: $e',
                          style: AdminTheme.sans(color: AdminTheme.error)),
                    ),
                  ),
                ),
                // 오른쪽: 생성 결과 로그
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: AdminTheme.surface,
                    border: Border(
                      left: BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                  ),
                  child: _buildResultPanel(),
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
                  'MOCK TICKETS',
                  style: AdminTheme.label(
                    fontSize: 10,
                    color: AdminTheme.gold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '모의 티켓 생성 — 마이티켓 디자인 확인용',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AdminTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AdminTheme.gold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEventList(List<Event> events) {
    if (events.isEmpty) {
      return Center(
        child: Text('등록된 공연이 없습니다',
            style: AdminTheme.sans(color: AdminTheme.textSecondary)),
      );
    }

    final fmt = NumberFormat('#,###', 'ko_KR');
    final dateFmt = DateFormat('M/d(E) HH:mm', 'ko_KR');

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        return _EventCard(
          event: event,
          dateFmt: dateFmt,
          priceFmt: fmt,
          loading: _loading,
          onGenerate: () => _generateTicket(event, 1),
          onGenerate2: () => _generateTicket(event, 2),
        );
      },
    );
  }

  Future<void> _generateTicket(Event event, int quantity) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _statusMsg = '${event.title} — 주문 생성 중...';
    });

    try {
      final functions = ref.read(functionsServiceProvider);

      // 1) 주문 생성
      final orderResult = await functions.createOrder(
        eventId: event.id,
        quantity: quantity,
      );
      final orderId = orderResult['orderId'] as String;

      setState(() => _statusMsg = '결제 확정 및 좌석 배정 중...');

      // 2) 결제 확정 + 좌석 배정
      final confirmResult = await functions.confirmPaymentAndAssignSeats(
        orderId: orderId,
      );

      if (confirmResult['success'] != true) {
        throw Exception(confirmResult['error'] ?? '좌석 배정 실패');
      }

      final ticketIds = confirmResult['ticketIds'] as List<dynamic>? ?? [];

      setState(() {
        _results.insert(
          0,
          _TicketResult(
            eventTitle: event.title,
            orderId: orderId,
            ticketIds: ticketIds.map((e) => e as String).toList(),
            quantity: quantity,
            createdAt: DateTime.now(),
            success: true,
          ),
        );
        _statusMsg = '';
      });
    } catch (e) {
      setState(() {
        _results.insert(
          0,
          _TicketResult(
            eventTitle: event.title,
            orderId: null,
            ticketIds: [],
            quantity: quantity,
            createdAt: DateTime.now(),
            success: false,
            error: '$e',
          ),
        );
        _statusMsg = '';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildResultPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AdminTheme.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_rounded,
                  size: 16, color: AdminTheme.gold),
              const SizedBox(width: 8),
              Text(
                '생성 결과',
                style: AdminTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (_results.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _results.clear()),
                  child: Text(
                    '전체 삭제',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 상태 메시지
        if (_statusMsg.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AdminTheme.gold.withValues(alpha: 0.08),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AdminTheme.gold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusMsg,
                    style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 결과 목록
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 36,
                          color: AdminTheme.sage.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text(
                        '공연 옆 버튼을 눌러\n모의 티켓을 생성하세요',
                        textAlign: TextAlign.center,
                        style: AdminTheme.sans(
                          fontSize: 13,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _results.length,
                  itemBuilder: (_, i) => _ResultCard(result: _results[i]),
                ),
        ),
      ],
    );
  }
}

// ─── Data ───

class _TicketResult {
  final String eventTitle;
  final String? orderId;
  final List<String> ticketIds;
  final int quantity;
  final DateTime createdAt;
  final bool success;
  final String? error;

  const _TicketResult({
    required this.eventTitle,
    required this.orderId,
    required this.ticketIds,
    required this.quantity,
    required this.createdAt,
    required this.success,
    this.error,
  });
}

// ─── Widgets ───

class _EventCard extends StatelessWidget {
  final Event event;
  final DateFormat dateFmt;
  final NumberFormat priceFmt;
  final bool loading;
  final VoidCallback onGenerate;
  final VoidCallback onGenerate2;

  const _EventCard({
    required this.event,
    required this.dateFmt,
    required this.priceFmt,
    required this.loading,
    required this.onGenerate,
    required this.onGenerate2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminTheme.border),
      ),
      child: Row(
        children: [
          // 포스터
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: event.imageUrl != null
                ? Image.network(
                    event.imageUrl!,
                    width: 48,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _posterPlaceholder(),
                  )
                : _posterPlaceholder(),
          ),
          const SizedBox(width: 14),
          // 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dateFmt.format(event.startAt)}  ·  ${priceFmt.format(event.price)}원',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '잔여 ${event.availableSeats}석',
                  style: AdminTheme.sans(
                    fontSize: 11,
                    color: event.availableSeats > 0
                        ? AdminTheme.success
                        : AdminTheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 생성 버튼
          Column(
            children: [
              _ActionButton(
                label: '1매',
                onTap: loading ? null : onGenerate,
                enabled: event.availableSeats > 0 && !loading,
              ),
              const SizedBox(height: 6),
              _ActionButton(
                label: '2매',
                onTap: loading ? null : onGenerate2,
                enabled: event.availableSeats >= 2 && !loading,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      width: 48,
      height: 64,
      color: AdminTheme.cardElevated,
      child: const Icon(Icons.music_note_rounded,
          color: AdminTheme.sage, size: 22),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: enabled ? AdminTheme.goldGradient : null,
          color: enabled ? null : AdminTheme.cardElevated,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: enabled ? AdminTheme.onAccent : AdminTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _TicketResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm:ss');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.success
            ? AdminTheme.success.withValues(alpha: 0.06)
            : AdminTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.success
              ? AdminTheme.success.withValues(alpha: 0.2)
              : AdminTheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                size: 14,
                color:
                    result.success ? AdminTheme.success : AdminTheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.eventTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                timeFmt.format(result.createdAt),
                style: AdminTheme.sans(
                  fontSize: 10,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (result.success) ...[
            Text(
              '${result.quantity}매 발급 완료',
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminTheme.success,
              ),
            ),
            if (result.ticketIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...result.ticketIds.map((id) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'ticket: ${id.substring(0, id.length.clamp(0, 20))}…',
                      style: AdminTheme.sans(
                        fontSize: 10,
                        color: AdminTheme.textTertiary,
                      ),
                    ),
                  )),
            ],
          ] else
            Text(
              result.error ?? '알 수 없는 오류',
              style: AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

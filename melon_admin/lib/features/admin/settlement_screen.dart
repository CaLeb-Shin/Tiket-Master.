import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/settlement.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/settlement_repository.dart';

class SettlementScreen extends ConsumerStatefulWidget {
  const SettlementScreen({super.key});

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  final _fmt = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final settlementsAsync = ref.watch(settlementsStreamProvider);
    final eventsAsync = ref.watch(allEventsStreamProvider);

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 헤더 ──
            Row(
              children: [
                Icon(Icons.account_balance_rounded,
                    size: 28, color: AdminTheme.gold),
                const SizedBox(width: 12),
                Text('정산 관리',
                    style: AdminTheme.serif(
                        fontSize: 24, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text('공연별 매출 정산 및 수수료 관리',
                style: AdminTheme.sans(
                    fontSize: 14, color: AdminTheme.textSecondary)),
            const SizedBox(height: 32),

            // ── 공연별 매출 요약 ──
            eventsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e'),
              data: (events) {
                final completedEvents = events
                    .where((e) =>
                        e.status == EventStatus.completed ||
                        e.startAt.isBefore(DateTime.now()))
                    .toList();

                if (completedEvents.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AdminTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AdminTheme.border, width: 0.5),
                    ),
                    child: Center(
                      child: Text('정산 가능한 공연이 없습니다.',
                          style: AdminTheme.sans(
                              fontSize: 14,
                              color: AdminTheme.textSecondary)),
                    ),
                  );
                }

                return Expanded(
                  child: settlementsAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator()),
                    error: (e, _) => Text('오류: $e'),
                    data: (settlements) {
                      return _buildSettlementList(
                          completedEvents, settlements);
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettlementList(
      List<Event> events, List<Settlement> settlements) {
    // 정산된 이벤트 ID 셋
    final settledEventIds =
        settlements.map((s) => s.eventId).toSet();

    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final eventSettlements = settlements
            .where((s) => s.eventId == event.id)
            .toList();
        final hasSettlement = eventSettlements.isNotEmpty;
        final latestSettlement =
            hasSettlement ? eventSettlements.first : null;

        final soldSeats = event.totalSeats - event.availableSeats;
        final totalSales = soldSeats * event.price;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminTheme.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(event.title,
                            style: AdminTheme.sans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AdminTheme.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('yyyy.MM.dd').format(event.startAt)} · ${soldSeats}매 판매',
                          style: AdminTheme.sans(
                              fontSize: 13,
                              color: AdminTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (latestSettlement != null)
                    _statusChip(latestSettlement.status)
                  else
                    _statusChip(null),
                ],
              ),
              const SizedBox(height: 16),
              // 매출 정보
              Row(
                children: [
                  _infoCell('총 매출', '${_fmt.format(totalSales)}원'),
                  _infoCell(
                      '수수료 (10%)',
                      '${_fmt.format((totalSales * 0.10).round())}원'),
                  _infoCell(
                      '정산 예정액',
                      '${_fmt.format((totalSales * 0.90).round())}원',
                      highlight: true),
                ],
              ),
              const SizedBox(height: 16),
              // 액션 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (latestSettlement == null)
                    _actionButton(
                      '정산 요청',
                      Icons.request_page_rounded,
                      AdminTheme.gold,
                      () => _requestSettlement(event, totalSales),
                    ),
                  if (latestSettlement?.status ==
                      SettlementStatus.pending) ...[
                    _actionButton(
                      '승인',
                      Icons.check_circle_outline_rounded,
                      AdminTheme.success,
                      () => _approveSettlement(latestSettlement!.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (latestSettlement?.status ==
                      SettlementStatus.approved)
                    _actionButton(
                      '입금 완료',
                      Icons.account_balance_wallet_rounded,
                      AdminTheme.info,
                      () => _markTransferred(latestSettlement!.id),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoCell(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AdminTheme.sans(
                  fontSize: 12, color: AdminTheme.textTertiary)),
          const SizedBox(height: 4),
          Text(value,
              style: AdminTheme.sans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: highlight ? AdminTheme.gold : AdminTheme.textPrimary,
              )),
        ],
      ),
    );
  }

  Widget _statusChip(SettlementStatus? status) {
    final text = status?.displayName ?? '미정산';
    final color = switch (status) {
      SettlementStatus.pending => AdminTheme.warning,
      SettlementStatus.approved => AdminTheme.success,
      SettlementStatus.transferred => AdminTheme.info,
      null => AdminTheme.textTertiary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: AdminTheme.sans(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: AdminTheme.sans(fontSize: 12, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  Future<void> _requestSettlement(Event event, int totalSales) async {
    try {
      await ref.read(settlementRepositoryProvider).requestSettlement(
            eventId: event.id,
            sellerId: 'admin', // 현재 단일 어드민
            totalSales: totalSales,
            refundAmount: 0,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정산 요청이 생성되었습니다.'),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정산 요청 실패: $e'),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  Future<void> _approveSettlement(String settlementId) async {
    try {
      await ref
          .read(settlementRepositoryProvider)
          .approveSettlement(settlementId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정산이 승인되었습니다.'),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('승인 실패: $e'),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  Future<void> _markTransferred(String settlementId) async {
    try {
      await ref
          .read(settlementRepositoryProvider)
          .markTransferred(settlementId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('입금 완료 처리되었습니다.'),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('처리 실패: $e'),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }
}

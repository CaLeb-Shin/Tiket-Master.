import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/order_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/models/order.dart';
import 'package:melon_core/data/models/seat_block.dart';
import 'package:melon_core/services/functions_service.dart';

// =============================================================================
// 배정 현황 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

class AssignmentCheckScreen extends ConsumerWidget {
  final String eventId;

  const AssignmentCheckScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(eventId));
    final ordersAsync = ref.watch(orderRepositoryProvider).getPaidOrdersByEvent(eventId);
    final seatBlocksAsync = ref.watch(seatRepositoryProvider).getSeatBlocksByEvent(eventId);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── Editorial App Bar ──
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 4,
              right: 16,
              bottom: 12,
            ),
            decoration: BoxDecoration(
              color: AppTheme.background.withValues(alpha: 0.95),
              border: const Border(
                bottom: BorderSide(color: AppTheme.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.west,
                      color: AppTheme.textPrimary, size: 20),
                ),
                const SizedBox(width: 4),
                Text(
                  'Seat Assignment',
                  style: AppTheme.serif(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                // 좌석 공개 버튼
                GestureDetector(
                  onTap: () => _revealSeats(context, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.sage.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility_outlined,
                            size: 14, color: AppTheme.gold),
                        const SizedBox(width: 6),
                        Text(
                          'REVEAL',
                          style: AppTheme.label(
                            fontSize: 9,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: eventAsync.when(
              data: (event) {
                if (event == null) {
                  return Center(
                    child: Text(
                      '공연을 찾을 수 없습니다',
                      style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Event Info Card ──
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: AppTheme.sage.withValues(alpha: 0.1),
                                width: 0.5,
                              ),
                              boxShadow: AppShadows.card,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EVENT',
                                  style: AppTheme.label(fontSize: 9),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  event.title,
                                  style: AppTheme.serif(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  height: 0.5,
                                  color: AppTheme.sage.withValues(alpha: 0.15),
                                ),
                                const SizedBox(height: 16),
                                _InfoRow(
                                  label: 'TOTAL SEATS',
                                  value: '${event.totalSeats}',
                                ),
                                const SizedBox(height: 10),
                                _InfoRow(
                                  label: 'AVAILABLE',
                                  value: '${event.availableSeats}',
                                ),
                                const SizedBox(height: 10),
                                _InfoRow(
                                  label: 'REVEALED',
                                  value: event.isSeatsRevealed
                                      ? 'YES'
                                      : 'NO',
                                  valueColor: event.isSeatsRevealed
                                      ? AppTheme.success
                                      : AppTheme.warning,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          // ── Section Header ──
                          Row(
                            children: [
                              Text(
                                'Paid Orders',
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
                                  color: AppTheme.sage
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Orders List ──
                          StreamBuilder<List<Order>>(
                            stream: ordersAsync,
                            builder: (context, orderSnapshot) {
                              if (orderSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: CircularProgressIndicator(
                                        color: AppTheme.gold),
                                  ),
                                );
                              }

                              final orders = orderSnapshot.data ?? [];
                              if (orders.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius:
                                        BorderRadius.circular(2),
                                    border: Border.all(
                                      color: AppTheme.sage
                                          .withValues(alpha: 0.1),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '결제 완료된 주문이 없습니다',
                                      style: AppTheme.sans(
                                        fontSize: 13,
                                        color: AppTheme.textTertiary,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return StreamBuilder<List<SeatBlock>>(
                                stream: seatBlocksAsync,
                                builder: (context, blockSnapshot) {
                                  final seatBlocks =
                                      blockSnapshot.data ?? [];

                                  return ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: orders.length,
                                    itemBuilder: (context, index) {
                                      final order = orders[index];
                                      final block =
                                          seatBlocks.firstWhere(
                                        (b) => b.orderId == order.id,
                                        orElse: () => SeatBlock(
                                          id: '',
                                          eventId: eventId,
                                          orderId: order.id,
                                          quantity: 0,
                                          seatIds: [],
                                          hidden: true,
                                          assignedAt: DateTime.now(),
                                        ),
                                      );

                                      return _OrderAssignmentCard(
                                        order: order,
                                        seatBlock: block,
                                        index: index + 1,
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
              error: (error, stack) => Center(
                child: Text('오류: $error',
                    style: AppTheme.sans(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _revealSeats(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        title: Text(
          '좌석 공개',
          style: AppTheme.serif(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '모든 좌석을 공개하시겠습니까?\n(테스트용 - 실제로는 자동 실행됩니다)',
          style: AppTheme.sans(
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: AppTheme.sans(
                fontSize: 13,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: AppTheme.onAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            child: Text(
              'REVEAL',
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.onAccent,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(functionsServiceProvider).revealSeatsForEvent(
            eventId: eventId,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '좌석이 공개되었습니다',
              style: AppTheme.sans(
                fontSize: 13,
                color: AppTheme.onAccent,
              ),
            ),
            backgroundColor: AppTheme.gold,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}

// ─── Info Row (editorial) ───

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTheme.label(
            fontSize: 9,
            color: AppTheme.sage,
          ),
        ),
        Text(
          value,
          style: AppTheme.sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Order Assignment Card (editorial) ───

class _OrderAssignmentCard extends ConsumerWidget {
  final Order order;
  final SeatBlock seatBlock;
  final int index;

  const _OrderAssignmentCard({
    required this.order,
    required this.seatBlock,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MM.dd HH:mm');
    final priceFormat = NumberFormat('#,###', 'ko_KR');

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.sage.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: Row(
            children: [
              // Status indicator
              Container(
                width: 2,
                height: 28,
                decoration: BoxDecoration(
                  color: seatBlock.hidden
                      ? AppTheme.warning
                      : AppTheme.success,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${order.id.substring(0, 8)}',
                      style: AppTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${order.quantity}매  ·  ${priceFormat.format(order.totalAmount)}원  ·  ${dateFormat.format(order.createdAt)}',
                      style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: Text(
            seatBlock.hidden ? 'HIDDEN' : 'VISIBLE',
            style: AppTheme.label(
              fontSize: 9,
              color: seatBlock.hidden
                  ? AppTheme.warning
                  : AppTheme.success,
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 0.5,
                  color: AppTheme.sage.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 12),
                Text(
                  'USER',
                  style: AppTheme.label(fontSize: 8),
                ),
                const SizedBox(height: 4),
                Text(
                  order.userId,
                  style: AppTheme.sans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'ASSIGNED SEATS',
                  style: AppTheme.label(fontSize: 8),
                ),
                const SizedBox(height: 8),
                if (seatBlock.seatIds.isEmpty)
                  Text(
                    '배정 정보 없음',
                    style: AppTheme.sans(
                      fontSize: 12,
                      color: AppTheme.error,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: seatBlock.seatIds
                        .map(
                          (seatId) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.cardElevated,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: AppTheme.sage
                                    .withValues(alpha: 0.1),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              seatId.length > 8
                                  ? seatId.substring(0, 8)
                                  : seatId,
                              style: AppTheme.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

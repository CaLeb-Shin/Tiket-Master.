import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/order.dart';
import 'package:melon_core/data/repositories/order_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';

// =============================================================================
// 주문 관리 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

class AdminOrdersScreen extends ConsumerWidget {
  final String eventId;
  const AdminOrdersScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(
      StreamProvider<List<Order>>((ref) {
        return ref.watch(orderRepositoryProvider).getOrdersByEvent(eventId);
      }),
    );
    final eventAsync = ref.watch(eventStreamProvider(eventId));

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
                    } else {
                      context.go('/');
                    }
                  },
                  icon: const Icon(Icons.west,
                      color: AppTheme.textPrimary, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: eventAsync.when(
                    data: (event) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orders',
                          style: AppTheme.serif(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (event != null)
                          Text(
                            event.title,
                            style: AppTheme.sans(
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    loading: () => Text(
                      'Orders',
                      style: AppTheme.serif(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    error: (_, __) => Text(
                      'Orders',
                      style: AppTheme.serif(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_rounded,
                            size: 36,
                            color: AppTheme.sage.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          '주문이 없습니다',
                          style: AppTheme.sans(
                            fontSize: 14,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Summary
                final paid = orders.where((o) => o.status == OrderStatus.paid);
                final refunded =
                    orders.where((o) => o.status == OrderStatus.refunded);
                final canceled =
                    orders.where((o) => o.status == OrderStatus.canceled);
                final totalRevenue =
                    paid.fold<int>(0, (sum, o) => sum + o.totalAmount);
                final priceFormat = NumberFormat('#,###');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary Cards ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        'SUMMARY',
                        style: AppTheme.label(fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _SummaryCard(
                            label: 'PAID',
                            value: '${paid.length}',
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 10),
                          _SummaryCard(
                            label: 'REFUNDED',
                            value: '${refunded.length}',
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 10),
                          _SummaryCard(
                            label: 'CANCELED',
                            value: '${canceled.length}',
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(width: 10),
                          _SummaryCard(
                            label: 'REVENUE',
                            value: priceFormat.format(totalRevenue),
                            color: AppTheme.gold,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Section header ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            'All Orders',
                            style: AppTheme.serif(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 0.5,
                              color: AppTheme.sage.withValues(alpha: 0.3),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${orders.length}',
                            style: AppTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Order list ──
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 0.5,
                          color: AppTheme.sage.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (_, i) =>
                            _AdminOrderRow(order: orders[i]),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
              error: (e, _) => Center(
                child: Text('오류: $e',
                    style: AppTheme.sans(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Card (editorial white surface) ───

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppTheme.sage.withValues(alpha: 0.1),
            width: 0.5,
          ),
          boxShadow: AppShadows.small,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTheme.label(
                fontSize: 9,
                color: AppTheme.sage,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTheme.serif(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Order Row (editorial minimal) ───

class _AdminOrderRow extends StatelessWidget {
  final Order order;
  const _AdminOrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final priceFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('MM.dd HH:mm', 'ko_KR');

    Color statusColor;
    String statusLabel;
    switch (order.status) {
      case OrderStatus.paid:
        statusColor = AppTheme.success;
        statusLabel = 'PAID';
      case OrderStatus.pending:
        statusColor = AppTheme.warning;
        statusLabel = 'PENDING';
      case OrderStatus.refunded:
        statusColor = AppTheme.error;
        statusLabel = 'REFUNDED';
      case OrderStatus.canceled:
        statusColor = AppTheme.textTertiary;
        statusLabel = 'CANCELED';
      case OrderStatus.failed:
        statusColor = AppTheme.error.withValues(alpha: 0.6);
        statusLabel = 'FAILED';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          // Status indicator — thin vertical line
          Container(
            width: 2,
            height: 32,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 14),

          // Order info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.id.substring(0, 8),
                  style: AppTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${order.quantity}매  ·  ${dateFormat.format(order.createdAt)}',
                  style: AppTheme.sans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Amount + status label
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${priceFormat.format(order.totalAmount)}원',
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                statusLabel,
                style: AppTheme.label(
                  fontSize: 9,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

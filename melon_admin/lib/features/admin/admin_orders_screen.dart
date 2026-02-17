import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/order.dart';
import 'package:melon_core/data/repositories/order_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';

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
          // App bar
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 4,
              right: 16,
              bottom: 12,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(
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
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppTheme.textPrimary, size: 20),
                ),
                Expanded(
                  child: eventAsync.when(
                    data: (event) => Text(
                      event != null ? '주문관리 - ${event.title}' : '주문관리',
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    loading: () => Text(
                      '주문관리',
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    error: (_, __) => Text(
                      '주문관리',
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_rounded,
                            size: 40,
                            color: AppTheme.textTertiary.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          '주문이 없습니다',
                          style: GoogleFonts.notoSans(
                              fontSize: 14, color: AppTheme.textTertiary),
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
                  children: [
                    // ── Summary cards ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _SummaryCard(
                            label: '결제완료',
                            value: '${paid.length}건',
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 8),
                          _SummaryCard(
                            label: '환불',
                            value: '${refunded.length}건',
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 8),
                          _SummaryCard(
                            label: '취소',
                            value: '${canceled.length}건',
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          _SummaryCard(
                            label: '매출',
                            value: '${priceFormat.format(totalRevenue)}원',
                            color: AppTheme.gold,
                          ),
                        ],
                      ),
                    ),

                    // ── Order list ──
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                    style: GoogleFonts.notoSans(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 11,
                color: color.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.notoSans(
                fontSize: 13,
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

class _AdminOrderRow extends StatelessWidget {
  final Order order;
  const _AdminOrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final priceFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('MM.dd HH:mm', 'ko_KR');

    Color statusColor;
    switch (order.status) {
      case OrderStatus.paid:
        statusColor = AppTheme.success;
      case OrderStatus.pending:
        statusColor = AppTheme.warning;
      case OrderStatus.refunded:
        statusColor = AppTheme.error;
      case OrderStatus.canceled:
        statusColor = AppTheme.textTertiary;
      case OrderStatus.failed:
        statusColor = AppTheme.error.withOpacity(0.6);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),

          // Order info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.id.substring(0, 8)}...',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.quantity}매 · ${dateFormat.format(order.createdAt)}',
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Amount + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${priceFormat.format(order.totalAmount)}원',
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  order.status.displayName,
                  style: GoogleFonts.notoSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

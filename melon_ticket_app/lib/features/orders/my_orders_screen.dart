import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/order.dart';
import 'package:melon_core/data/repositories/order_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/auth_service.dart';

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.value?.uid;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildAppBar(context),
          Expanded(
            child: userId == null
                ? _CenteredMessage(
                    icon: Icons.login_rounded,
                    text: '로그인이 필요합니다',
                  )
                : _OrderList(userId: userId),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
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
          Text(
            '주문 내역',
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  final String userId;
  const _OrderList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersStreamProvider(userId));

    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return _CenteredMessage(
            icon: Icons.receipt_long_rounded,
            text: '주문 내역이 없습니다',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _OrderCard(order: orders[i]),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.gold),
      ),
      error: (e, _) => _CenteredMessage(
        icon: Icons.error_outline_rounded,
        text: '오류가 발생했습니다',
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  final Order order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(order.eventId));
    final priceFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 상태 뱃지 + 날짜 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                _StatusBadge(status: order.status),
                const Spacer(),
                Text(
                  dateFormat.format(order.createdAt),
                  style: GoogleFonts.notoSans(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // ── 공연 정보 + 주문 상세 ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 공연명
                eventAsync.when(
                  data: (event) => event != null
                      ? GestureDetector(
                          onTap: () => context.push('/event/${event.id}'),
                          child: Text(
                            event.title,
                            style: GoogleFonts.notoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text(
                          '공연 정보 없음',
                          style: GoogleFonts.notoSans(
                            fontSize: 15,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                  loading: () => Container(
                    height: 16,
                    width: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  error: (_, __) => Text(
                    '공연 정보 조회 실패',
                    style: GoogleFonts.notoSans(
                        fontSize: 14, color: AppTheme.textTertiary),
                  ),
                ),

                const SizedBox(height: 12),

                // 주문 정보 행
                Row(
                  children: [
                    _InfoChip(
                      label: '수량',
                      value: '${order.quantity}매',
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      label: '금액',
                      value: '${priceFormat.format(order.totalAmount)}원',
                    ),
                  ],
                ),

                // 환불 정보
                if (order.status == OrderStatus.refunded &&
                    order.refundedAt != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppTheme.error.withOpacity(0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.replay_rounded,
                            size: 14, color: AppTheme.error.withOpacity(0.8)),
                        const SizedBox(width: 6),
                        Text(
                          '환불완료 ${dateFormat.format(order.refundedAt!)}',
                          style: GoogleFonts.notoSans(
                            fontSize: 12,
                            color: AppTheme.error.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 실패 사유
                if (order.status == OrderStatus.failed &&
                    order.failReason != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.failReason!,
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── 하단: 내 티켓 보기 버튼 ──
          if (order.status == OrderStatus.paid)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: () => context.push('/tickets'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.gold,
                    side: const BorderSide(color: AppTheme.gold, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    '내 티켓 보기',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color fgColor;

    switch (status) {
      case OrderStatus.paid:
        bgColor = AppTheme.success.withOpacity(0.15);
        fgColor = AppTheme.success;
      case OrderStatus.pending:
        bgColor = AppTheme.warning.withOpacity(0.15);
        fgColor = AppTheme.warning;
      case OrderStatus.refunded:
        bgColor = AppTheme.error.withOpacity(0.15);
        fgColor = AppTheme.error;
      case OrderStatus.canceled:
        bgColor = AppTheme.textTertiary.withOpacity(0.15);
        fgColor = AppTheme.textTertiary;
      case OrderStatus.failed:
        bgColor = AppTheme.error.withOpacity(0.1);
        fgColor = AppTheme.error.withOpacity(0.7);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.displayName,
        style: GoogleFonts.notoSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.goldSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: GoogleFonts.notoSans(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.notoSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CenteredMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: AppTheme.textTertiary.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            text,
            style: GoogleFonts.notoSans(
              fontSize: 14,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

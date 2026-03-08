import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/naver_order.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/naver_order_repository.dart';
import 'package:melon_core/infrastructure/firebase/functions_service.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

class NaverLinkedOrdersScreen extends ConsumerWidget {
  const NaverLinkedOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.value?.uid;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _NaverOrdersAppBar(onClaim: () => _showClaimDialog(context, ref)),
          Expanded(
            child: userId == null
                ? const _NaverCenteredMessage(
                    icon: Icons.login_rounded,
                    title: '로그인이 필요합니다',
                    subtitle: '네이버 예매를 연결하려면 먼저 로그인해주세요.',
                  )
                : _NaverLinkedOrderList(
                    userId: userId,
                    onClaim: () => _showClaimDialog(context, ref),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showClaimDialog(BuildContext context, WidgetRef ref) async {
    final orderIdController = TextEditingController();
    final phoneController = TextEditingController();
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text(
              '네이버 주문 연결',
              style: AppTheme.nanum(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '주문번호와 연락처를 확인하면 내 계정에 네이버 예매를 연결합니다.',
                  style: AppTheme.nanum(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: orderIdController,
                  decoration: const InputDecoration(
                    labelText: '네이버 주문번호',
                    hintText: '예: 20260308-0001',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '연락처 뒤 4자리 또는 전체',
                    hintText: '예: 1234',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          await ref
                              .read(functionsServiceProvider)
                              .claimNaverOrder(
                                naverOrderId: orderIdController.text.trim(),
                                buyerPhone: phoneController.text.trim(),
                              );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('네이버 주문이 연결되었습니다')),
                            );
                          }
                        } catch (error) {
                          setDialogState(() => isSubmitting = false);
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(SnackBar(content: Text('$error')));
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('연결하기'),
              ),
            ],
          );
        },
      ),
    );

    orderIdController.dispose();
    phoneController.dispose();
  }
}

class _NaverOrdersAppBar extends StatelessWidget {
  final VoidCallback onClaim;

  const _NaverOrdersAppBar({required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
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
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary,
              size: 20,
            ),
          ),
          Text(
            '네이버 예매 내역',
            style: AppTheme.nanum(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onClaim,
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('주문 연결'),
          ),
        ],
      ),
    );
  }
}

class _NaverLinkedOrderList extends ConsumerWidget {
  final String userId;
  final VoidCallback onClaim;

  const _NaverLinkedOrderList({required this.userId, required this.onClaim});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myLinkedNaverOrdersStreamProvider(userId));

    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return _NaverCenteredMessage(
            icon: Icons.receipt_long_rounded,
            title: '연결된 네이버 예매가 없습니다',
            subtitle: '주문번호와 연락처를 입력하면 내 공연과 회차를 앱에서 바로 볼 수 있습니다.',
            actionLabel: '주문 연결',
            onAction: onClaim,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => PressableScale(
            child: _NaverLinkedOrderCard(order: orders[index]),
          ),
        );
      },
      loading: () => Column(
        children: List.generate(
          4,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ShimmerLoading(height: 96, borderRadius: 14),
          ),
        ),
      ),
      error: (error, _) => _NaverCenteredMessage(
        icon: Icons.error_outline_rounded,
        title: '네이버 예매를 불러오지 못했습니다',
        subtitle: '$error',
        actionLabel: '다시 연결',
        onAction: onClaim,
      ),
    );
  }
}

class _NaverLinkedOrderCard extends ConsumerWidget {
  final NaverOrder order;

  const _NaverLinkedOrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(order.eventId));
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');
    final linkedAt = order.linkedAt;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${order.seatGrade}석 ${order.quantity}매',
                    style: AppTheme.nanum(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  order.status.displayName,
                  style: AppTheme.nanum(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            eventAsync.when(
              data: (event) => Text(
                event?.title ?? order.productName,
                style: AppTheme.nanum(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              loading: () => Container(
                height: 16,
                width: 140,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              error: (_, __) => Text(
                order.productName,
                style: AppTheme.nanum(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '주문번호 ${order.naverOrderId}',
              style: AppTheme.nanum(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '구매 ${dateFormat.format(order.createdAt)}'
              '${linkedAt != null ? ' · 연결 ${dateFormat.format(linkedAt)}' : ''}',
              style: AppTheme.nanum(fontSize: 12, color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NaverCenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _NaverCenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppTheme.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.nanum(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.nanum(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

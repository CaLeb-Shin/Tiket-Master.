import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/data/repositories/mileage_repository.dart';
import 'package:melon_core/data/models/mileage.dart';
import 'package:melon_core/data/models/mileage_history.dart';

class MileageHistoryScreen extends ConsumerWidget {
  const MileageHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.value;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const Text('마일리지')),
        body: const Center(child: Text('로그인이 필요합니다')),
      );
    }

    final mileage = user.mileage;
    final historyAsync = ref.watch(
      mileageHistoryStreamProvider((userId: user.id, limit: 50)),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text(
          '마일리지',
          style: AppTheme.serif(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Mileage summary card
          _MileageSummaryCard(mileage: mileage),
          const SizedBox(height: 24),

          // History section header
          Text(
            'HISTORY',
            style: AppTheme.label(
              fontSize: 10,
              color: AppTheme.sage,
            ),
          ),
          const SizedBox(height: 12),

          // History list
          historyAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppTheme.border, width: 0.5),
                  ),
                  child: Center(
                    child: Text(
                      '마일리지 내역이 없습니다',
                      style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: history
                    .map((item) => _MileageHistoryItem(item: item))
                    .toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '내역을 불러올 수 없습니다',
                  style: AppTheme.sans(
                    fontSize: 14,
                    color: AppTheme.error,
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

class _MileageSummaryCard extends StatelessWidget {
  final Mileage mileage;
  const _MileageSummaryCard({required this.mileage});

  Color _tierColor(MileageTier tier) {
    switch (tier) {
      case MileageTier.bronze:
        return const Color(0xFFCD7F32);
      case MileageTier.silver:
        return const Color(0xFFC0C0C0);
      case MileageTier.gold:
        return const Color(0xFFC9A84C);
      case MileageTier.platinum:
        return const Color(0xFFE5E4E2);
    }
  }

  IconData _tierIcon(MileageTier tier) {
    switch (tier) {
      case MileageTier.bronze:
        return Icons.circle;
      case MileageTier.silver:
        return Icons.hexagon_outlined;
      case MileageTier.gold:
        return Icons.star_rounded;
      case MileageTier.platinum:
        return Icons.diamond_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor(mileage.tier);
    final nextTier = mileage.tier.next;
    final progress = nextTier != null
        ? (mileage.totalEarned - mileage.tier.minPoints) /
            (nextTier.minPoints - mileage.tier.minPoints)
        : 1.0;
    final remaining =
        nextTier != null ? nextTier.minPoints - mileage.totalEarned : 0;
    final formatter = NumberFormat('#,###');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier badge + balance
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_tierIcon(mileage.tier), size: 14, color: tierColor),
                    const SizedBox(width: 4),
                    Text(
                      mileage.tier.displayName,
                      style: AppTheme.label(
                        fontSize: 10,
                        color: tierColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${formatter.format(mileage.balance)}P',
                style: AppTheme.serif(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  shadows: AppTheme.textShadowStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress to next tier
          if (nextTier != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '다음 등급까지',
                  style: AppTheme.sans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  '${formatter.format(remaining)}P 남음',
                  style: AppTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppTheme.cardElevated,
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  mileage.tier.displayName,
                  style: AppTheme.sans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
                Text(
                  nextTier.displayName,
                  style: AppTheme.sans(
                    fontSize: 11,
                    color: _tierColor(nextTier),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              '최고 등급입니다',
              style: AppTheme.sans(
                fontSize: 12,
                color: tierColor,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _MileageHistoryItem extends StatelessWidget {
  final MileageHistory item;
  const _MileageHistoryItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isPositive = item.amount > 0;
    final formatter = NumberFormat('#,###');
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isPositive
                  ? AppTheme.success.withValues(alpha: 0.08)
                  : AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              _typeIcon(item.type),
              size: 18,
              color: isPositive ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.type.displayName,
                  style: AppTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason,
                  style: AppTheme.sans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Amount + date
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : ''}${formatter.format(item.amount)}P',
                style: AppTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isPositive ? AppTheme.success : AppTheme.error,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateFormat.format(item.createdAt),
                style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(MileageType type) {
    switch (type) {
      case MileageType.purchase:
        return Icons.shopping_bag_outlined;
      case MileageType.referral:
        return Icons.people_outline_rounded;
      case MileageType.upgrade:
        return Icons.upgrade_rounded;
    }
  }
}

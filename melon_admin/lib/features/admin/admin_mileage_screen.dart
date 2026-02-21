import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/app_user.dart';
import 'package:melon_core/data/models/mileage.dart';
import 'package:melon_core/data/models/mileage_history.dart';
import 'package:melon_core/widgets/premium_effects.dart';

// =============================================================================
// 마일리지 관리 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

/// 전체 사용자 목록 (마일리지 포함) 스트림
final _allUsersStreamProvider = StreamProvider<List<AppUser>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => AppUser.fromFirestore(d)).toList());
});

class AdminMileageScreen extends ConsumerStatefulWidget {
  const AdminMileageScreen({super.key});

  @override
  ConsumerState<AdminMileageScreen> createState() => _AdminMileageScreenState();
}

class _AdminMileageScreenState extends ConsumerState<AdminMileageScreen> {
  MileageTier? _filterTier;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(_allUsersStreamProvider);

    return Scaffold(
      backgroundColor: AdminTheme.background,
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
                Text(
                  'Mileage',
                  style: AdminTheme.serif(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '마일리지 관리',
                  style: AdminTheme.sans(
                    fontSize: 11,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: usersAsync.when(
              data: (users) => _buildContent(users),
              loading: () => Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Row(
                      children: List.generate(
                        4,
                        (_) => const Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: ShimmerLoading(height: 100, borderRadius: 4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const ShimmerLoading(height: 300, borderRadius: 4),
                  ],
                ),
              ),
              error: (e, _) => Center(
                child: Text('오류: $e',
                    style: AdminTheme.sans(color: AdminTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<AppUser> allUsers) {
    // Tier distribution
    final tierCounts = <MileageTier, int>{};
    for (final tier in MileageTier.values) {
      tierCounts[tier] = allUsers.where((u) => u.mileage.tier == tier).length;
    }
    final totalMileage =
        allUsers.fold<int>(0, (s, u) => s + u.mileage.balance);
    final totalEarned =
        allUsers.fold<int>(0, (s, u) => s + u.mileage.totalEarned);

    // Filter and search
    var filteredUsers = allUsers.toList();
    if (_filterTier != null) {
      filteredUsers =
          filteredUsers.where((u) => u.mileage.tier == _filterTier).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredUsers = filteredUsers.where((u) {
        return (u.email.toLowerCase().contains(q)) ||
            (u.displayName?.toLowerCase().contains(q) ?? false) ||
            (u.referralCode?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // Sort by mileage balance desc
    filteredUsers.sort((a, b) => b.mileage.balance.compareTo(a.mileage.balance));

    final priceFormat = NumberFormat('#,###');

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 28, 40, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Summary Cards ──
              Text(
                'OVERVIEW',
                style: AdminTheme.label(fontSize: 10),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _SummaryCard(
                    label: 'USERS',
                    value: '${allUsers.length}',
                    color: AdminTheme.sage,
                    footnote: '전체 등록 사용자',
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    label: 'TOTAL BALANCE',
                    value: '${priceFormat.format(totalMileage)}P',
                    color: AdminTheme.gold,
                    footnote: '유통 마일리지',
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    label: 'TOTAL EARNED',
                    value: '${priceFormat.format(totalEarned)}P',
                    color: AdminTheme.success,
                    footnote: '누적 적립',
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    label: 'REFERRAL USERS',
                    value: '${allUsers.where((u) => u.referralCode != null).length}',
                    color: AdminTheme.info,
                    footnote: '추천코드 보유',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Tier Distribution ──
              Text(
                'TIER DISTRIBUTION',
                style: AdminTheme.label(fontSize: 10),
              ),
              const SizedBox(height: 12),
              Row(
                children: MileageTier.values.map((tier) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: tier != MileageTier.platinum ? 10 : 0,
                      ),
                      child: _TierCard(
                        tier: tier,
                        count: tierCounts[tier] ?? 0,
                        total: allUsers.length,
                        isSelected: _filterTier == tier,
                        onTap: () {
                          setState(() {
                            _filterTier = _filterTier == tier ? null : tier;
                          });
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 28),

              // ── Search + Filter bar ──
              Row(
                children: [
                  Text(
                    'Users',
                    style: AdminTheme.serif(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 0.5,
                      color: AdminTheme.sage.withValues(alpha: 0.3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_filterTier != null)
                    GestureDetector(
                      onTap: () => setState(() => _filterTier = null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _tierColor(_filterTier!).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: _tierColor(_filterTier!).withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _filterTier!.displayName,
                              style: AdminTheme.label(
                                fontSize: 9,
                                color: _tierColor(_filterTier!),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.close,
                                size: 12,
                                color: _tierColor(_filterTier!)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 240,
                    height: 36,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: AdminTheme.sans(
                        fontSize: 13,
                        color: AdminTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '이메일, 이름, 추천코드 검색',
                        hintStyle: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textTertiary,
                        ),
                        prefixIcon: const Icon(Icons.search,
                            size: 16, color: AdminTheme.textTertiary),
                        filled: true,
                        fillColor: AdminTheme.surface,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: AdminTheme.border, width: 0.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: AdminTheme.border, width: 0.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(
                              color: AdminTheme.gold.withValues(alpha: 0.5),
                              width: 0.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${filteredUsers.length}명',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── User Table ──
              Container(
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                  boxShadow: AdminShadows.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      color: AdminTheme.cardElevated,
                      child: Row(
                        children: [
                          _tableHeader('사용자', flex: 3),
                          _tableHeader('추천코드'),
                          _tableHeader('등급'),
                          _tableHeader('잔액'),
                          _tableHeader('누적 적립'),
                          _tableHeader('액션'),
                        ],
                      ),
                    ),
                    Container(height: 0.5, color: AdminTheme.border),

                    // Rows
                    if (filteredUsers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(60),
                        child: Center(
                          child: Text(
                            '조건에 맞는 사용자가 없습니다',
                            style: AdminTheme.sans(
                              fontSize: 14,
                              color: AdminTheme.textTertiary,
                            ),
                          ),
                        ),
                      )
                    else
                      ...filteredUsers.map(
                        (user) => _UserRow(
                          user: user,
                          onAdjust: () => _showAdjustDialog(user),
                          onHistory: () => _showHistoryDialog(user),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: flex > 1 ? TextAlign.left : TextAlign.center,
        style: AdminTheme.label(fontSize: 10, color: AdminTheme.textTertiary),
      ),
    );
  }

  // ── Adjust Mileage Dialog ──
  void _showAdjustDialog(AppUser user) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    bool isDeduct = false;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AdminTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '마일리지 수동 조정',
                    style: AdminTheme.serif(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.displayName ?? user.email,
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '현재 잔액: ${NumberFormat('#,###').format(user.mileage.balance)}P',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Toggle: 지급 / 차감
                  Row(
                    children: [
                      _ToggleChip(
                        label: '지급',
                        isSelected: !isDeduct,
                        color: AdminTheme.success,
                        onTap: () =>
                            setDialogState(() => isDeduct = false),
                      ),
                      const SizedBox(width: 8),
                      _ToggleChip(
                        label: '차감',
                        isSelected: isDeduct,
                        color: AdminTheme.error,
                        onTap: () =>
                            setDialogState(() => isDeduct = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: AdminTheme.sans(
                      fontSize: 14,
                      color: AdminTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: '금액 (P)',
                      labelStyle: AdminTheme.sans(
                          fontSize: 12, color: AdminTheme.textTertiary),
                      filled: true,
                      fillColor: AdminTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                            color: AdminTheme.border, width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                            color: AdminTheme.border, width: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reason
                  TextField(
                    controller: reasonController,
                    style: AdminTheme.sans(
                      fontSize: 14,
                      color: AdminTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: '사유',
                      labelStyle: AdminTheme.sans(
                          fontSize: 12, color: AdminTheme.textTertiary),
                      filled: true,
                      fillColor: AdminTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                            color: AdminTheme.border, width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                            color: AdminTheme.border, width: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed:
                                isLoading ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AdminTheme.textPrimary,
                              side: const BorderSide(
                                  color: AdminTheme.border, width: 0.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                            child: Text('취소',
                                style: AdminTheme.sans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AdminTheme.textSecondary)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    final amount = int.tryParse(
                                        amountController.text.trim());
                                    if (amount == null || amount <= 0) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text('올바른 금액을 입력하세요'),
                                        backgroundColor: AdminTheme.error,
                                      ));
                                      return;
                                    }
                                    final reason =
                                        reasonController.text.trim();
                                    if (reason.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text('사유를 입력하세요'),
                                        backgroundColor: AdminTheme.error,
                                      ));
                                      return;
                                    }

                                    setDialogState(() => isLoading = true);
                                    try {
                                      final callable = FirebaseFunctions
                                          .instance
                                          .httpsCallable('addMileage');
                                      await callable.call({
                                        'userId': user.id,
                                        'amount':
                                            isDeduct ? -amount : amount,
                                        'type': 'purchase',
                                        'reason':
                                            '[관리자] $reason',
                                      });
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(isDeduct
                                              ? '${NumberFormat('#,###').format(amount)}P 차감 완료'
                                              : '${NumberFormat('#,###').format(amount)}P 지급 완료'),
                                          backgroundColor:
                                              AdminTheme.success,
                                          behavior:
                                              SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4)),
                                        ));
                                      }
                                    } catch (e) {
                                      setDialogState(
                                          () => isLoading = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text('오류: $e'),
                                          backgroundColor: AdminTheme.error,
                                          behavior:
                                              SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4)),
                                        ));
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDeduct
                                  ? AdminTheme.error
                                  : AdminTheme.gold,
                              foregroundColor: isDeduct
                                  ? Colors.white
                                  : AdminTheme.onAccent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : Text(
                                    isDeduct ? '차감' : '지급',
                                    style: AdminTheme.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDeduct
                                          ? Colors.white
                                          : AdminTheme.onAccent,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── History Dialog ──
  void _showHistoryDialog(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AdminTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '마일리지 내역',
                            style: AdminTheme.serif(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AdminTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${user.displayName ?? user.email} · ${user.mileage.tier.displayName} · ${NumberFormat('#,###').format(user.mileage.balance)}P',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              color: AdminTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close,
                          size: 18, color: AdminTheme.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 0.5, color: AdminTheme.border),
                const SizedBox(height: 8),
                Flexible(
                  child: _MileageHistoryList(userId: user.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? footnote;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AdminTheme.border, width: 0.5),
          boxShadow: AdminShadows.small,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    label,
                    style: AdminTheme.label(fontSize: 9, color: color),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(height: 0.5, color: AdminTheme.border),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: AdminTheme.serif(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary,
                height: 1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (footnote != null) ...[
              const SizedBox(height: 8),
              Text(
                footnote!,
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatefulWidget {
  final MileageTier tier;
  final int count;
  final int total;
  final bool isSelected;
  final VoidCallback onTap;

  const _TierCard({
    required this.tier,
    required this.count,
    required this.total,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends State<_TierCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(widget.tier);
    final ratio = widget.total > 0 ? widget.count / widget.total : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? color.withValues(alpha: 0.06)
                : AdminTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isSelected
                  ? color.withValues(alpha: 0.3)
                  : _isHovered
                      ? color.withValues(alpha: 0.15)
                      : AdminTheme.border,
              width: 0.5,
            ),
            boxShadow:
                _isHovered || widget.isSelected ? AdminShadows.card : AdminShadows.small,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.tier.displayName.toUpperCase(),
                    style: AdminTheme.label(fontSize: 10, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.count}',
                style: AdminTheme.serif(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 3,
                child: shad.Progress(
                  progress: ratio,
                  backgroundColor: AdminTheme.border,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatefulWidget {
  final AppUser user;
  final VoidCallback onAdjust;
  final VoidCallback onHistory;

  const _UserRow({
    required this.user,
    required this.onAdjust,
    required this.onHistory,
  });

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final priceFormat = NumberFormat('#,###');
    final tierColor = _tierColor(user.mileage.tier);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _isHovered
            ? AdminTheme.sage.withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            // User info
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (user.displayName ?? user.email)[0].toUpperCase(),
                        style: AdminTheme.serif(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tierColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName ?? '(이름 없음)',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AdminTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: AdminTheme.sans(
                            fontSize: 11,
                            color: AdminTheme.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Referral code
            Expanded(
              child: Center(
                child: Text(
                  user.referralCode ?? '—',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: user.referralCode != null
                        ? AdminTheme.textSecondary
                        : AdminTheme.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Tier
            Expanded(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    user.mileage.tier.displayName,
                    style: AdminTheme.label(fontSize: 9, color: tierColor),
                  ),
                ),
              ),
            ),

            // Balance
            Expanded(
              child: Center(
                child: Text(
                  '${priceFormat.format(user.mileage.balance)}P',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.gold,
                  ),
                ),
              ),
            ),

            // Total earned
            Expanded(
              child: Center(
                child: Text(
                  '${priceFormat.format(user.mileage.totalEarned)}P',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            ),

            // Actions
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onAdjust,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AdminTheme.gold.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: AdminTheme.gold.withValues(alpha: 0.2),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '조정',
                          style: AdminTheme.sans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AdminTheme.gold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onHistory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AdminTheme.sage.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: AdminTheme.sage.withValues(alpha: 0.15),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '내역',
                          style: AdminTheme.sans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : AdminTheme.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.4) : AdminTheme.border,
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? color : AdminTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 마일리지 내역 리스트 (StreamBuilder 사용)
class _MileageHistoryList extends StatelessWidget {
  final String userId;

  const _MileageHistoryList({required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mileageHistory')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('오류: ${snapshot.error}',
                style: AdminTheme.sans(color: AdminTheme.error, fontSize: 12)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                '마일리지 내역이 없습니다',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ),
          );
        }

        final histories =
            docs.map((d) => MileageHistory.fromFirestore(d)).toList();

        return ListView.separated(
          shrinkWrap: true,
          itemCount: histories.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.12),
          ),
          itemBuilder: (_, i) {
            final h = histories[i];
            final isPositive = h.amount > 0;
            final dateStr =
                DateFormat('MM.dd HH:mm').format(h.createdAt);
            final priceFormat = NumberFormat('#,###');

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  // Type indicator
                  Container(
                    width: 2,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isPositive
                          ? AdminTheme.success
                          : AdminTheme.error,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              h.type.displayName,
                              style: AdminTheme.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AdminTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: AdminTheme.sans(
                                fontSize: 11,
                                color: AdminTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          h.reason,
                          style: AdminTheme.sans(
                            fontSize: 11,
                            color: AdminTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Amount
                  Text(
                    '${isPositive ? '+' : ''}${priceFormat.format(h.amount)}P',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isPositive
                          ? AdminTheme.success
                          : AdminTheme.error,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Tier color helper ──
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

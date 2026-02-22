import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/app_user.dart';
import 'package:melon_core/data/models/escrow.dart';
import 'package:melon_core/data/models/settlement.dart';
import 'package:melon_core/data/repositories/seller_repository.dart';
import 'package:melon_core/data/repositories/settlement_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/firestore_service.dart';

class SuperAdminScreen extends ConsumerStatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  ConsumerState<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends ConsumerState<SuperAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _fmt = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    // ── 슈퍼어드민 가드 ──
    if (currentUser.isLoading) {
      return const Scaffold(
        backgroundColor: AdminTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AdminTheme.gold),
        ),
      );
    }

    if (currentUser.value?.isSuperAdmin != true) {
      return Scaffold(
        backgroundColor: AdminTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded,
                  size: 48, color: AdminTheme.error.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text('슈퍼어드민 전용 페이지입니다',
                  style: AdminTheme.serif(fontSize: 20)),
              const SizedBox(height: 8),
              Text('접근 권한이 없습니다.',
                  style: AdminTheme.sans(
                      fontSize: 14, color: AdminTheme.textSecondary)),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('돌아가기',
                    style: AdminTheme.sans(color: AdminTheme.gold)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          // ── 헤더 + 탭 ──
          Container(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              border: Border(
                bottom: BorderSide(color: AdminTheme.border, width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AdminTheme.goldGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          size: 20, color: AdminTheme.onAccent),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SUPER ADMIN',
                            style: AdminTheme.label(
                                fontSize: 10, color: AdminTheme.gold)),
                        const SizedBox(height: 2),
                        Text('플랫폼 운영 대시보드',
                            style: AdminTheme.serif(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: AdminTheme.textSecondary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  indicatorColor: AdminTheme.gold,
                  indicatorWeight: 2,
                  labelColor: AdminTheme.gold,
                  unselectedLabelColor: AdminTheme.textSecondary,
                  labelStyle:
                      AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle:
                      AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w400),
                  dividerHeight: 0,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(text: '셀러 관리'),
                    Tab(text: '에스크로 현황'),
                    Tab(text: '정산 관리'),
                    Tab(text: '감사 로그'),
                  ],
                ),
              ],
            ),
          ),

          // ── 탭 내용 ──
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _SellerManagementTab(fmt: _fmt),
                _EscrowOverviewTab(fmt: _fmt),
                _SettlementManagementTab(fmt: _fmt),
                _AuditLogTab(fmt: _fmt),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 1) 셀러 관리 탭
// ══════════════════════════════════════════════
class _SellerManagementTab extends ConsumerStatefulWidget {
  final NumberFormat fmt;
  const _SellerManagementTab({required this.fmt});

  @override
  ConsumerState<_SellerManagementTab> createState() =>
      _SellerManagementTabState();
}

class _SellerManagementTabState extends ConsumerState<_SellerManagementTab> {
  String _filterStatus = 'all'; // all, pending, active, suspended

  @override
  Widget build(BuildContext context) {
    final sellersAsync = ref.watch(sellersStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 필터 칩
          Row(
            children: [
              for (final entry in {
                'all': '전체',
                'pending': '승인 대기',
                'active': '활성',
                'suspended': '정지',
              }.entries) ...[
                _FilterChip(
                  label: entry.value,
                  selected: _filterStatus == entry.key,
                  onTap: () => setState(() => _filterStatus = entry.key),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 24),

          // 셀러 목록
          Expanded(
            child: sellersAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AdminTheme.gold)),
              error: (e, _) => Center(
                  child: Text('오류: $e',
                      style: AdminTheme.sans(color: AdminTheme.error))),
              data: (sellers) {
                final filtered = _filterStatus == 'all'
                    ? sellers
                    : sellers
                        .where((s) =>
                            s.sellerProfile?.sellerStatus == _filterStatus)
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 48,
                            color: AdminTheme.textTertiary),
                        const SizedBox(height: 12),
                        Text('셀러가 없습니다.',
                            style: AdminTheme.sans(
                                color: AdminTheme.textSecondary)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final seller = filtered[index];
                    return _SellerCard(seller: seller, fmt: widget.fmt);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerCard extends ConsumerWidget {
  final AppUser seller;
  final NumberFormat fmt;
  const _SellerCard({required this.seller, required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = seller.sellerProfile;
    final status = profile?.sellerStatus ?? 'pending';

    return Container(
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
              // 셀러 아바타
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AdminTheme.cardElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  (profile?.businessName ?? '?').substring(0, 1),
                  style: AdminTheme.serif(
                      fontSize: 18, color: AdminTheme.gold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.businessName ?? '미등록',
                      style: AdminTheme.sans(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${seller.email} · ${seller.displayName ?? ''}',
                      style: AdminTheme.sans(
                          fontSize: 12, color: AdminTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              _sellerStatusChip(status),
            ],
          ),
          const SizedBox(height: 16),

          // 셀러 정보
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              if (profile?.businessNumber != null)
                _infoItem('사업자번호', profile!.businessNumber!),
              if (profile?.representativeName != null)
                _infoItem('대표자', profile!.representativeName!),
              if (profile?.contactNumber != null)
                _infoItem('연락처', profile!.contactNumber!),
              _infoItem('가입일',
                  DateFormat('yyyy.MM.dd').format(seller.createdAt)),
            ],
          ),
          const SizedBox(height: 16),

          // 액션 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (status == 'pending') ...[
                _actionBtn('승인', Icons.check_circle_outline_rounded,
                    AdminTheme.success, () async {
                  await ref
                      .read(sellerRepositoryProvider)
                      .approveSeller(seller.id);
                  if (context.mounted) _showSnack(context, '셀러가 승인되었습니다.');
                }),
                const SizedBox(width: 8),
              ],
              if (status == 'active')
                _actionBtn('정지', Icons.block_rounded, AdminTheme.warning,
                    () async {
                  final confirmed = await _confirmDialog(
                      context, '${profile?.businessName} 셀러를 정지하시겠습니까?');
                  if (confirmed == true) {
                    await ref
                        .read(sellerRepositoryProvider)
                        .suspendSeller(seller.id);
                    if (context.mounted) _showSnack(context, '셀러가 정지되었습니다.');
                  }
                }),
              if (status == 'suspended') ...[
                _actionBtn('재활성화', Icons.play_circle_outline_rounded,
                    AdminTheme.success, () async {
                  await ref
                      .read(sellerRepositoryProvider)
                      .reactivateSeller(seller.id);
                  if (context.mounted) _showSnack(context, '셀러가 재활성화되었습니다.');
                }),
                const SizedBox(width: 8),
              ],
              _actionBtn('탈퇴 처리', Icons.person_remove_rounded,
                  AdminTheme.error, () async {
                final confirmed = await _confirmDialog(
                    context, '${profile?.businessName} 셀러를 탈퇴 처리하시겠습니까?\n이 작업은 셀러 권한을 제거합니다.');
                if (confirmed == true) {
                  await ref
                      .read(sellerRepositoryProvider)
                      .removeSeller(seller.id);
                  if (context.mounted) _showSnack(context, '셀러가 탈퇴 처리되었습니다.');
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AdminTheme.sans(
                fontSize: 11, color: AdminTheme.textTertiary)),
        const SizedBox(height: 2),
        Text(value,
            style: AdminTheme.sans(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _sellerStatusChip(String status) {
    final (text, color) = switch (status) {
      'pending' => ('승인 대기', AdminTheme.warning),
      'active' => ('활성', AdminTheme.success),
      'suspended' => ('정지', AdminTheme.error),
      _ => (status, AdminTheme.textTertiary),
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

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label,
            style:
                AdminTheme.sans(fontSize: 12, fontWeight: FontWeight.w600)),
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

  Future<bool?> _confirmDialog(BuildContext context, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Text('확인', style: AdminTheme.serif(fontSize: 18)),
        content: Text(message,
            style: AdminTheme.sans(
                fontSize: 14, color: AdminTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(color: AdminTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.gold,
              foregroundColor: AdminTheme.onAccent,
            ),
            child: Text('확인',
                style: AdminTheme.sans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AdminTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 2) 에스크로 현황 탭
// ══════════════════════════════════════════════
class _EscrowOverviewTab extends ConsumerWidget {
  final NumberFormat fmt;
  const _EscrowOverviewTab({required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fs = ref.watch(firestoreServiceProvider);

    return StreamBuilder<QuerySnapshot>(
      stream: fs.instance
          .collection('escrowAccounts')
          .orderBy('balance', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AdminTheme.gold));
        }

        final docs = snap.data?.docs ?? [];
        final accounts =
            docs.map((d) => EscrowAccount.fromFirestore(d)).toList();

        // 집계
        final totalBalance =
            accounts.fold<int>(0, (sum, a) => sum + a.balance);
        final totalPending =
            accounts.fold<int>(0, (sum, a) => sum + a.pendingAmount);
        final totalDeposited =
            accounts.fold<int>(0, (sum, a) => sum + a.totalDeposited);
        final totalWithdrawn =
            accounts.fold<int>(0, (sum, a) => sum + a.totalWithdrawn);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 요약 카드
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _SummaryCard(
                    icon: Icons.account_balance_wallet_rounded,
                    label: '총 예치금',
                    value: '${fmt.format(totalBalance)}원',
                    color: AdminTheme.gold,
                  ),
                  _SummaryCard(
                    icon: Icons.hourglass_top_rounded,
                    label: '정산 대기금',
                    value: '${fmt.format(totalPending)}원',
                    color: AdminTheme.warning,
                  ),
                  _SummaryCard(
                    icon: Icons.arrow_downward_rounded,
                    label: '총 입금',
                    value: '${fmt.format(totalDeposited)}원',
                    color: AdminTheme.success,
                  ),
                  _SummaryCard(
                    icon: Icons.arrow_upward_rounded,
                    label: '총 출금',
                    value: '${fmt.format(totalWithdrawn)}원',
                    color: AdminTheme.info,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Text('셀러별 잔액',
                  style: AdminTheme.serif(fontSize: 18)),
              const SizedBox(height: 16),

              if (accounts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AdminTheme.border, width: 0.5),
                  ),
                  child: Center(
                    child: Text('에스크로 계정이 없습니다.',
                        style: AdminTheme.sans(
                            color: AdminTheme.textSecondary)),
                  ),
                )
              else
                // 테이블
                Container(
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AdminTheme.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      // 헤더
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: AdminTheme.cardElevated,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                        ),
                        child: Row(
                          children: [
                            _tableHeader('셀러 ID', flex: 3),
                            _tableHeader('잔액', flex: 2),
                            _tableHeader('대기금', flex: 2),
                            _tableHeader('총 입금', flex: 2),
                            _tableHeader('총 출금', flex: 2),
                            _tableHeader('상태', flex: 1),
                          ],
                        ),
                      ),
                      ...accounts.map((a) {
                        final isAnomalous = a.balance < 0 ||
                            (a.totalDeposited > 0 &&
                                a.balance >
                                    a.totalDeposited - a.totalWithdrawn + 1000);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: isAnomalous
                                ? AdminTheme.error.withValues(alpha: 0.06)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                  color: AdminTheme.border, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              _tableCell(a.id, flex: 3),
                              _tableCell('${fmt.format(a.balance)}원',
                                  flex: 2, bold: true),
                              _tableCell(
                                  '${fmt.format(a.pendingAmount)}원',
                                  flex: 2),
                              _tableCell(
                                  '${fmt.format(a.totalDeposited)}원',
                                  flex: 2),
                              _tableCell(
                                  '${fmt.format(a.totalWithdrawn)}원',
                                  flex: 2),
                              Expanded(
                                flex: 1,
                                child: isAnomalous
                                    ? Row(
                                        children: [
                                          Icon(Icons.warning_amber_rounded,
                                              size: 16,
                                              color: AdminTheme.error),
                                          const SizedBox(width: 4),
                                          Text('이상',
                                              style: AdminTheme.sans(
                                                  fontSize: 12,
                                                  color: AdminTheme.error,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ],
                                      )
                                    : Text('정상',
                                        style: AdminTheme.sans(
                                            fontSize: 12,
                                            color: AdminTheme.success)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              // 정합성 체크
              const SizedBox(height: 32),
              _ConsistencyCheck(accounts: accounts, fmt: fmt),
            ],
          ),
        );
      },
    );
  }

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textSecondary)),
    );
  }

  Widget _tableCell(String text,
      {int flex = 1, bool bold = false}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: AdminTheme.sans(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          )),
    );
  }
}

/// 일일 정합성 체크 위젯
class _ConsistencyCheck extends StatelessWidget {
  final List<EscrowAccount> accounts;
  final NumberFormat fmt;
  const _ConsistencyCheck({required this.accounts, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final anomalies = <String>[];

    for (final a in accounts) {
      final expected = a.totalDeposited - a.totalWithdrawn;
      if ((a.balance - expected).abs() > 100) {
        anomalies.add(
            '${a.id}: 잔액 ${fmt.format(a.balance)}원 vs 예상 ${fmt.format(expected)}원 (차이: ${fmt.format(a.balance - expected)}원)');
      }
      if (a.balance < 0) {
        anomalies.add('${a.id}: 음수 잔액 ${fmt.format(a.balance)}원');
      }
    }

    final isClean = anomalies.isEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isClean
            ? AdminTheme.success.withValues(alpha: 0.06)
            : AdminTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isClean
              ? AdminTheme.success.withValues(alpha: 0.3)
              : AdminTheme.error.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isClean
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 20,
                color: isClean ? AdminTheme.success : AdminTheme.error,
              ),
              const SizedBox(width: 10),
              Text(
                isClean ? '정합성 체크: 이상 없음' : '정합성 체크: ${anomalies.length}건 이상 발견',
                style: AdminTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isClean ? AdminTheme.success : AdminTheme.error,
                ),
              ),
            ],
          ),
          if (!isClean) ...[
            const SizedBox(height: 12),
            for (final a in anomalies) ...[
              Text('• $a',
                  style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textSecondary)),
              const SizedBox(height: 4),
            ],
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 3) 정산 관리 탭
// ══════════════════════════════════════════════
class _SettlementManagementTab extends ConsumerWidget {
  final NumberFormat fmt;
  const _SettlementManagementTab({required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementsAsync = ref.watch(settlementsStreamProvider);

    return settlementsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AdminTheme.gold)),
      error: (e, _) => Center(
          child:
              Text('오류: $e', style: AdminTheme.sans(color: AdminTheme.error))),
      data: (settlements) {
        if (settlements.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_rounded,
                    size: 48, color: AdminTheme.textTertiary),
                const SizedBox(height: 12),
                Text('정산 내역이 없습니다.',
                    style:
                        AdminTheme.sans(color: AdminTheme.textSecondary)),
              ],
            ),
          );
        }

        // 상태별 집계
        final pending =
            settlements.where((s) => s.status == SettlementStatus.pending);
        final approved =
            settlements.where((s) => s.status == SettlementStatus.approved);
        final transferred =
            settlements.where((s) => s.status == SettlementStatus.transferred);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 요약
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _SummaryCard(
                    icon: Icons.hourglass_top_rounded,
                    label: '대기 중',
                    value: '${pending.length}건',
                    color: AdminTheme.warning,
                  ),
                  _SummaryCard(
                    icon: Icons.check_circle_outline_rounded,
                    label: '승인됨',
                    value: '${approved.length}건',
                    color: AdminTheme.success,
                  ),
                  _SummaryCard(
                    icon: Icons.account_balance_wallet_rounded,
                    label: '입금 완료',
                    value: '${transferred.length}건',
                    color: AdminTheme.info,
                  ),
                  _SummaryCard(
                    icon: Icons.paid_rounded,
                    label: '총 정산액',
                    value:
                        '${fmt.format(settlements.fold<int>(0, (s, e) => s + e.settlementAmount))}원',
                    color: AdminTheme.gold,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Text('정산 요청 목록',
                  style: AdminTheme.serif(fontSize: 18)),
              const SizedBox(height: 16),

              // 목록
              for (final s in settlements) ...[
                _SettlementCard(settlement: s, fmt: fmt),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SettlementCard extends ConsumerWidget {
  final Settlement settlement;
  final NumberFormat fmt;
  const _SettlementCard({required this.settlement, required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settlement;

    return Container(
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
                    Text('이벤트: ${s.eventId}',
                        style: AdminTheme.sans(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '셀러: ${s.sellerId} · ${DateFormat('yyyy.MM.dd HH:mm').format(s.requestedAt)}',
                        style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textSecondary)),
                  ],
                ),
              ),
              _statusChip(s.status),
            ],
          ),
          const SizedBox(height: 16),

          // 금액 정보
          Row(
            children: [
              _infoCell('총 매출', '${fmt.format(s.totalSales)}원'),
              _infoCell('환불',
                  '${fmt.format(s.refundAmount)}원'),
              _infoCell('수수료 (${(s.platformFeeRate * 100).round()}%)',
                  '${fmt.format(s.platformFeeAmount)}원'),
              _infoCell('정산액', '${fmt.format(s.settlementAmount)}원',
                  highlight: true),
            ],
          ),
          const SizedBox(height: 16),

          // 액션
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (s.status == SettlementStatus.pending) ...[
                _actionBtn(context, ref, '승인',
                    Icons.check_circle_outline_rounded, AdminTheme.success,
                    () async {
                  final confirmed = await _doubleConfirm(context,
                      '정산 승인',
                      '${fmt.format(s.settlementAmount)}원을 정산 승인하시겠습니까?\n수수료 ${fmt.format(s.platformFeeAmount)}원이 차감됩니다.');
                  if (confirmed == true) {
                    await ref
                        .read(settlementRepositoryProvider)
                        .approveSettlement(s.id);
                  }
                }),
                const SizedBox(width: 8),
              ],
              if (s.status == SettlementStatus.approved)
                _actionBtn(context, ref, '입금 완료',
                    Icons.account_balance_wallet_rounded, AdminTheme.info,
                    () async {
                  final confirmed = await _doubleConfirm(context,
                      '입금 완료',
                      '${fmt.format(s.settlementAmount)}원 입금 완료 처리하시겠습니까?');
                  if (confirmed == true) {
                    await ref
                        .read(settlementRepositoryProvider)
                        .markTransferred(s.id);
                  }
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(SettlementStatus status) {
    final color = switch (status) {
      SettlementStatus.pending => AdminTheme.warning,
      SettlementStatus.approved => AdminTheme.success,
      SettlementStatus.transferred => AdminTheme.info,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(status.displayName,
          style: AdminTheme.sans(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _infoCell(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AdminTheme.sans(
                  fontSize: 11, color: AdminTheme.textTertiary)),
          const SizedBox(height: 4),
          Text(value,
              style: AdminTheme.sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color:
                    highlight ? AdminTheme.gold : AdminTheme.textPrimary,
              )),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, WidgetRef ref, String label,
      IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label,
            style:
                AdminTheme.sans(fontSize: 12, fontWeight: FontWeight.w600)),
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

  /// 더블 확인 다이얼로그
  Future<bool?> _doubleConfirm(
      BuildContext context, String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AdminTheme.warning, size: 22),
            const SizedBox(width: 10),
            Text(title, style: AdminTheme.serif(fontSize: 18)),
          ],
        ),
        content: Text(message,
            style: AdminTheme.sans(
                fontSize: 14, color: AdminTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(color: AdminTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.gold,
              foregroundColor: AdminTheme.onAccent,
            ),
            child: Text('확인',
                style: AdminTheme.sans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 4) 감사 로그 탭
// ══════════════════════════════════════════════
class _AuditLogTab extends ConsumerStatefulWidget {
  final NumberFormat fmt;
  const _AuditLogTab({required this.fmt});

  @override
  ConsumerState<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends ConsumerState<_AuditLogTab> {
  String _typeFilter = 'all';
  String _sellerFilter = '';

  @override
  Widget build(BuildContext context) {
    final fs = ref.watch(firestoreServiceProvider);

    // 기본 쿼리: 최근 200건
    Query query = fs.instance
        .collection('escrowTransactions')
        .orderBy('createdAt', descending: true)
        .limit(200);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 필터
          Row(
            children: [
              // 유형 필터
              for (final entry in {
                'all': '전체',
                'deposit': '입금',
                'refund': '환불',
                'settlement': '정산',
                'platformFee': '수수료',
                'topup': '충전',
              }.entries) ...[
                _FilterChip(
                  label: entry.value,
                  selected: _typeFilter == entry.key,
                  onTap: () => setState(() => _typeFilter = entry.key),
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 16),
              // 셀러 검색
              SizedBox(
                width: 180,
                height: 36,
                child: TextField(
                  onChanged: (v) => setState(() => _sellerFilter = v.trim()),
                  style: AdminTheme.sans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '셀러 ID 검색',
                    hintStyle: AdminTheme.sans(
                        fontSize: 12, color: AdminTheme.textTertiary),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: AdminTheme.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: AdminTheme.gold, width: 1),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // CSV 내보내기
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () => _exportCsv(context),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text('CSV',
                      style: AdminTheme.sans(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.gold.withValues(alpha: 0.15),
                    foregroundColor: AdminTheme.gold,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 로그 테이블
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AdminTheme.gold));
                }

                final docs = snap.data?.docs ?? [];
                var txns = docs
                    .map((d) => EscrowTransaction.fromFirestore(d))
                    .toList();

                // 클라이언트 필터
                if (_typeFilter != 'all') {
                  txns = txns
                      .where((t) => t.type.name == _typeFilter)
                      .toList();
                }
                if (_sellerFilter.isNotEmpty) {
                  txns = txns
                      .where((t) => t.sellerId.contains(_sellerFilter))
                      .toList();
                }

                if (txns.isEmpty) {
                  return Center(
                    child: Text('트랜잭션이 없습니다.',
                        style: AdminTheme.sans(
                            color: AdminTheme.textSecondary)),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AdminTheme.border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      // 헤더
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AdminTheme.cardElevated,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                        ),
                        child: Row(
                          children: [
                            _tHeader('일시', flex: 3),
                            _tHeader('셀러', flex: 2),
                            _tHeader('유형', flex: 1),
                            _tHeader('금액', flex: 2),
                            _tHeader('잔액 전', flex: 2),
                            _tHeader('잔액 후', flex: 2),
                            _tHeader('설명', flex: 3),
                          ],
                        ),
                      ),
                      // 목록
                      Expanded(
                        child: ListView.builder(
                          itemCount: txns.length,
                          itemBuilder: (context, i) {
                            final t = txns[i];
                            final isNegative = t.amount < 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                      color: AdminTheme.border,
                                      width: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _tCell(
                                    DateFormat('MM.dd HH:mm')
                                        .format(t.createdAt),
                                    flex: 3,
                                  ),
                                  _tCell(t.sellerId, flex: 2),
                                  Expanded(
                                    flex: 1,
                                    child: _txTypeChip(t.type),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${isNegative ? "" : "+"}${widget.fmt.format(t.amount)}원',
                                      style: AdminTheme.sans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isNegative
                                            ? AdminTheme.error
                                            : AdminTheme.success,
                                      ),
                                    ),
                                  ),
                                  _tCell(
                                      '${widget.fmt.format(t.balanceBefore)}원',
                                      flex: 2),
                                  _tCell(
                                      '${widget.fmt.format(t.balanceAfter)}원',
                                      flex: 2),
                                  _tCell(t.description ?? '-', flex: 3),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: AdminTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textSecondary)),
    );
  }

  Widget _tCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: AdminTheme.sans(fontSize: 12),
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _txTypeChip(EscrowTxType type) {
    final color = switch (type) {
      EscrowTxType.deposit => AdminTheme.success,
      EscrowTxType.refund => AdminTheme.error,
      EscrowTxType.settlement => AdminTheme.info,
      EscrowTxType.platformFee => AdminTheme.warning,
      EscrowTxType.topup => AdminTheme.gold,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(type.displayName,
          style: AdminTheme.sans(
              fontSize: 10, fontWeight: FontWeight.w600, color: color),
          textAlign: TextAlign.center),
    );
  }

  void _exportCsv(BuildContext context) {
    // CSV 내보내기 (간단 구현 — 클립보드)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('CSV 내보내기 기능은 추후 업데이트 예정입니다.'),
        backgroundColor: AdminTheme.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 공통 위젯
// ══════════════════════════════════════════════
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AdminTheme.gold.withValues(alpha: 0.15)
                : AdminTheme.cardElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AdminTheme.gold.withValues(alpha: 0.5)
                  : AdminTheme.border,
              width: 0.5,
            ),
          ),
          child: Text(label,
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AdminTheme.gold : AdminTheme.textSecondary,
              )),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label,
                  style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: AdminTheme.sans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ],
      ),
    );
  }
}

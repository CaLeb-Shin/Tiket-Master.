import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/scanner_device.dart';
import 'package:melon_core/data/repositories/scanner_device_repository.dart';
import 'package:melon_core/services/functions_service.dart';

// =============================================================================
// 스캐너 기기 승인 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

enum _DeviceFilter {
  pending,
  approved,
  blocked,
  all;

  String get label {
    switch (this) {
      case _DeviceFilter.pending:
        return '승인대기';
      case _DeviceFilter.approved:
        return '승인됨';
      case _DeviceFilter.blocked:
        return '차단됨';
      case _DeviceFilter.all:
        return '전체';
    }
  }

  String get upperLabel {
    switch (this) {
      case _DeviceFilter.pending:
        return 'PENDING';
      case _DeviceFilter.approved:
        return 'APPROVED';
      case _DeviceFilter.blocked:
        return 'BLOCKED';
      case _DeviceFilter.all:
        return 'ALL';
    }
  }
}

class ScannerDeviceApprovalScreen extends ConsumerStatefulWidget {
  const ScannerDeviceApprovalScreen({super.key});

  @override
  ConsumerState<ScannerDeviceApprovalScreen> createState() =>
      _ScannerDeviceApprovalScreenState();
}

class _ScannerDeviceApprovalScreenState
    extends ConsumerState<ScannerDeviceApprovalScreen> {
  _DeviceFilter _filter = _DeviceFilter.pending;

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(scannerDeviceRepositoryProvider).streamAllDevices();

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: StreamBuilder<List<ScannerDevice>>(
              stream: devicesAsync,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AdminTheme.gold,
                      strokeWidth: 2,
                    ),
                  );
                }

                final all = snapshot.data ?? const <ScannerDevice>[];
                final filtered = all.where(_matchesFilter).toList();

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).size.width >= 900 ? 40 : 20,
                    vertical: 32,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Page Title + Invite Button ──
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '스캐너 기기 승인',
                                      style: AdminTheme.serif(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 12,
                                      height: 1,
                                      color: AdminTheme.gold,
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showInviteDialog(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AdminTheme.gold,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.link,
                                          size: 14, color: AdminTheme.onAccent),
                                      const SizedBox(width: 6),
                                      Text(
                                        '초대링크 생성',
                                        style: AdminTheme.label(
                                          fontSize: 10,
                                          color: AdminTheme.onAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),

                          // ── Filter Tabs ──
                          _buildFilterTabs(),
                          const SizedBox(height: 24),

                          // ── Summary ──
                          _buildSummary(all.length, filtered.length),
                          const SizedBox(height: 24),

                          // ── Device List ──
                          if (filtered.isEmpty)
                            _buildEmptyState()
                          else
                            ...filtered.map((device) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _DeviceCard(
                                    device: device,
                                    onApprove: () => _setApproval(
                                        device.id,
                                        approved: true,
                                        blocked: false),
                                    onRevoke: () => _setApproval(
                                        device.id,
                                        approved: false,
                                        blocked: false),
                                    onBlock: () => _setApproval(
                                        device.id,
                                        approved: false,
                                        blocked: true),
                                    onUnblock: () => _setApproval(
                                        device.id,
                                        approved: false,
                                        blocked: false),
                                  ),
                                )),

                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP BAR
  // ═══════════════════════════════════════════════════════════════════════════

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
          bottom: BorderSide(
            color: AdminTheme.border,
            width: 0.5,
          ),
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
                color: AdminTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Editorial Admin',
            style: AdminTheme.serif(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILTER TABS — Editorial minimal
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFilterTabs() {
    return Row(
      children: _DeviceFilter.values.map((filter) {
        final selected = filter == _filter;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => setState(() => _filter = filter),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AdminTheme.gold
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: selected
                      ? AdminTheme.gold
                      : AdminTheme.sage.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Text(
                filter.upperLabel,
                style: AdminTheme.label(
                  fontSize: 9,
                  color: selected
                      ? AdminTheme.onAccent
                      : AdminTheme.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSummary(int totalCount, int filteredCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Text(
            'DEVICES',
            style: AdminTheme.label(
              fontSize: 9,
              color: AdminTheme.sage,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 0.5,
            height: 12,
            color: AdminTheme.sage.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 12),
          Text(
            '총 $totalCount대',
            style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '·',
            style: AdminTheme.sans(
              fontSize: 12,
              color: AdminTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '표시 $filteredCount대',
            style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.devices_other_outlined,
            size: 36,
            color: AdminTheme.sage.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '표시할 기기가 없습니다',
            style: AdminTheme.sans(
              fontSize: 14,
              color: AdminTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(ScannerDevice device) {
    switch (_filter) {
      case _DeviceFilter.pending:
        return !device.approved && !device.blocked;
      case _DeviceFilter.approved:
        return device.approved && !device.blocked;
      case _DeviceFilter.blocked:
        return device.blocked;
      case _DeviceFilter.all:
        return true;
    }
  }

  Future<void> _showInviteDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ScannerInviteDialog(ref: ref),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('초대링크가 클립보드에 복사되었습니다'),
          backgroundColor: AdminTheme.success,
        ),
      );
    }
  }

  Future<void> _setApproval(
    String deviceId, {
    required bool approved,
    required bool blocked,
  }) async {
    try {
      await ref.read(functionsServiceProvider).setScannerDeviceApproval(
            deviceId: deviceId,
            approved: approved,
            blocked: blocked,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? '기기 차단 완료'
                : approved
                    ? '기기 승인 완료'
                    : '승인 해제 완료',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('처리 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    }
  }
}

// =============================================================================
// DEVICE CARD — Editorial white card with thin borders
// =============================================================================

class _DeviceCard extends StatefulWidget {
  final ScannerDevice device;
  final VoidCallback onApprove;
  final VoidCallback onRevoke;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  const _DeviceCard({
    required this.device,
    required this.onApprove,
    required this.onRevoke,
    required this.onBlock,
    required this.onUnblock,
  });

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  String? _loadingAction; // 현재 로딩 중인 액션 이름

  Future<void> _handleAction(String action, VoidCallback callback) async {
    if (_loadingAction != null) return; // 중복 클릭 방지
    setState(() => _loadingAction = action);
    try {
      callback();
      // 스트림이 업데이트되면 카드가 rebuild되므로 짧은 딜레이 후 해제
      await Future.delayed(const Duration(milliseconds: 1500));
    } finally {
      if (mounted) setState(() => _loadingAction = null);
    }
  }

  ScannerDevice get device => widget.device;

  @override
  Widget build(BuildContext context) {
    final lastSeen = device.lastSeenAt == null
        ? '-'
        : DateFormat('MM.dd HH:mm', 'ko_KR').format(device.lastSeenAt!);
    final requested = device.requestedAt == null
        ? '-'
        : DateFormat('MM.dd HH:mm', 'ko_KR').format(device.requestedAt!);

    Color stateColor;
    String stateLabel;
    if (device.blocked) {
      stateColor = AdminTheme.error;
      stateLabel = 'BLOCKED';
    } else if (device.approved) {
      stateColor = AdminTheme.success;
      stateLabel = 'APPROVED';
    } else {
      stateColor = AdminTheme.warning;
      stateLabel = 'PENDING';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
        boxShadow: AdminShadows.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Device name + Status badge ──
          Row(
            children: [
              Expanded(
                child: Text(
                  device.label.isEmpty ? device.id : device.label,
                  style: AdminTheme.serif(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: stateColor.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  stateLabel,
                  style: AdminTheme.label(
                    fontSize: 9,
                    color: stateColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Divider ──
          Container(
            width: double.infinity,
            height: 0.5,
            color: AdminTheme.sage.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),

          // ── Owner info ──
          Row(
            children: [
              Text(
                'OWNER',
                style: AdminTheme.label(
                  fontSize: 9,
                  color: AdminTheme.sage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${device.ownerDisplayName} · ${device.ownerEmail}',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Device meta ──
          Row(
            children: [
              _metaItem('PLATFORM', device.platform),
              const SizedBox(width: 16),
              _metaItem('REQUESTED', requested),
              const SizedBox(width: 16),
              _metaItem('LAST SEEN', lastSeen),
            ],
          ),
          const SizedBox(height: 16),

          // ── Action buttons ──
          Row(
            children: [
              if (!device.approved && !device.blocked)
                _actionButton(
                  label: 'APPROVE',
                  onPressed: () => _handleAction('approve', widget.onApprove),
                  color: AdminTheme.success,
                  filled: true,
                  loading: _loadingAction == 'approve',
                ),
              if (device.approved)
                _actionButton(
                  label: 'REVOKE',
                  onPressed: () => _handleAction('revoke', widget.onRevoke),
                  color: AdminTheme.warning,
                  filled: false,
                  loading: _loadingAction == 'revoke',
                ),
              if (!device.blocked)
                _actionButton(
                  label: 'BLOCK',
                  onPressed: () => _handleAction('block', widget.onBlock),
                  color: AdminTheme.error,
                  filled: false,
                  loading: _loadingAction == 'block',
                ),
              if (device.blocked)
                _actionButton(
                  label: 'UNBLOCK',
                  onPressed: () => _handleAction('unblock', widget.onUnblock),
                  color: AdminTheme.warning,
                  filled: true,
                  loading: _loadingAction == 'unblock',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AdminTheme.label(
              fontSize: 8,
              color: AdminTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AdminTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required bool filled,
    bool loading = false,
  }) {
    final disabled = _loadingAction != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: disabled ? null : onPressed,
        child: AnimatedOpacity(
          opacity: disabled && !loading ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: filled ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: filled ? color : color.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: loading
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: filled ? Colors.white : color,
                    ),
                  )
                : Text(
                    label,
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: filled ? Colors.white : color,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SCANNER INVITE DIALOG
// =============================================================================

class _ScannerInviteDialog extends StatefulWidget {
  final WidgetRef ref;
  const _ScannerInviteDialog({required this.ref});

  @override
  State<_ScannerInviteDialog> createState() => _ScannerInviteDialogState();
}

class _ScannerInviteDialogState extends State<_ScannerInviteDialog> {
  bool _loading = false;
  String? _generatedLink;
  String? _error;
  int _expiresInHours = 24;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.ref
          .read(functionsServiceProvider)
          .createScannerInvite(expiresInHours: _expiresInHours);
      final token = result['token'] as String;
      final link =
          'https://melonticket-web-20260216.vercel.app/staff/scanner?invite=$token';
      final copyText =
          '[멜론티켓 스캐너 초대]\n'
          '아래 링크를 눌러 스캐너에 접속하세요.\n'
          '로그인 후 자동으로 기기가 승인됩니다.\n\n'
          '$link';
      await Clipboard.setData(ClipboardData(text: copyText));
      if (!mounted) return;
      setState(() {
        _generatedLink = link;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──
              Text(
                '스캐너 초대링크',
                style: AdminTheme.serif(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '링크를 받은 스태프가 접속하면 자동으로 기기 승인됩니다',
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // ── Expires selector ──
              Row(
                children: [
                  Text(
                    'EXPIRES',
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: AdminTheme.sage,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ...[6, 12, 24, 48].map((h) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _expiresInHours = h),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _expiresInHours == h
                                  ? AdminTheme.gold
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: _expiresInHours == h
                                    ? AdminTheme.gold
                                    : AdminTheme.sage.withValues(alpha: 0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              '${h}h',
                              style: AdminTheme.label(
                                fontSize: 9,
                                color: _expiresInHours == h
                                    ? AdminTheme.onAccent
                                    : AdminTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 24),

              // ── Generated link ──
              if (_generatedLink != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminTheme.background,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: AdminTheme.success.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: AdminTheme.success),
                          const SizedBox(width: 6),
                          Text(
                            '링크 생성 + 복사 완료',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AdminTheme.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _generatedLink!,
                        style: AdminTheme.sans(
                          fontSize: 10,
                          color: AdminTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final copyText =
                              '[멜론티켓 스캐너 초대]\n'
                              '아래 링크를 눌러 스캐너에 접속하세요.\n'
                              '로그인 후 자동으로 기기가 승인됩니다.\n\n'
                              '${_generatedLink!}';
                          Clipboard.setData(ClipboardData(text: copyText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('복사됨')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AdminTheme.sage.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '다시 복사',
                            style: AdminTheme.label(
                              fontSize: 10,
                              color: AdminTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            Navigator.of(context).pop(_generatedLink),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: AdminTheme.gold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '닫기',
                            style: AdminTheme.label(
                              fontSize: 10,
                              color: AdminTheme.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // ── Generate button ──
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: AdminTheme.sans(
                        fontSize: 11, color: AdminTheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AdminTheme.sage.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '취소',
                            style: AdminTheme.label(
                              fontSize: 10,
                              color: AdminTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _loading ? null : _generate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: AdminTheme.gold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.center,
                          child: _loading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AdminTheme.onAccent,
                                  ),
                                )
                              : Text(
                                  '생성 + 복사',
                                  style: AdminTheme.label(
                                    fontSize: 10,
                                    color: AdminTheme.onAccent,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

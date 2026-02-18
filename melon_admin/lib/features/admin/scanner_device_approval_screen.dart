import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;
import 'package:melon_core/app/theme.dart';
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
      backgroundColor: AppTheme.background,
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
                      color: AppTheme.gold,
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
                          // ── Page Title ──
                          Text(
                            '스캐너 기기 승인',
                            style: AppTheme.serif(
                              fontSize: 28,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 12,
                            height: 1,
                            color: AppTheme.gold,
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
        color: AppTheme.background.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(
            color: AppTheme.border,
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
                color: AppTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Editorial Admin',
            style: AppTheme.serif(
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
                    ? AppTheme.gold
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: selected
                      ? AppTheme.gold
                      : AppTheme.sage.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Text(
                filter.upperLabel,
                style: AppTheme.label(
                  fontSize: 9,
                  color: selected
                      ? AppTheme.onAccent
                      : AppTheme.textSecondary,
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
    return shad.Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: BorderRadius.circular(2),
      borderWidth: 0.5,
      borderColor: AppTheme.sage.withValues(alpha: 0.15),
      fillColor: AppTheme.surface,
      filled: true,
      child: Row(
        children: [
          Text(
            'DEVICES',
            style: AppTheme.label(
              fontSize: 9,
              color: AppTheme.sage,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 0.5,
            height: 12,
            color: AppTheme.sage.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 12),
          Text(
            '총 $totalCount대',
            style: AppTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '·',
            style: AppTheme.sans(
              fontSize: 12,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '표시 $filteredCount대',
            style: AppTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
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
            color: AppTheme.sage.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '표시할 기기가 없습니다',
            style: AppTheme.sans(
              fontSize: 14,
              color: AppTheme.textTertiary,
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
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}

// =============================================================================
// DEVICE CARD — Editorial white card with thin borders
// =============================================================================

class _DeviceCard extends StatelessWidget {
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
      stateColor = AppTheme.error;
      stateLabel = 'BLOCKED';
    } else if (device.approved) {
      stateColor = AppTheme.success;
      stateLabel = 'APPROVED';
    } else {
      stateColor = AppTheme.warning;
      stateLabel = 'PENDING';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppTheme.sage.withValues(alpha: 0.15),
          width: 0.5,
        ),
        boxShadow: AppShadows.small,
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
                  style: AppTheme.serif(
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
                  style: AppTheme.label(
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
            color: AppTheme.sage.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),

          // ── Owner info ──
          Row(
            children: [
              Text(
                'OWNER',
                style: AppTheme.label(
                  fontSize: 9,
                  color: AppTheme.sage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${device.ownerDisplayName} · ${device.ownerEmail}',
                  style: AppTheme.sans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
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
                  onPressed: onApprove,
                  color: AppTheme.success,
                  filled: true,
                ),
              if (device.approved)
                _actionButton(
                  label: 'REVOKE',
                  onPressed: onRevoke,
                  color: AppTheme.warning,
                  filled: false,
                ),
              if (!device.blocked)
                _actionButton(
                  label: 'BLOCK',
                  onPressed: onBlock,
                  color: AppTheme.error,
                  filled: false,
                ),
              if (device.blocked)
                _actionButton(
                  label: 'UNBLOCK',
                  onPressed: onUnblock,
                  color: AppTheme.warning,
                  filled: true,
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
            style: AppTheme.label(
              fontSize: 8,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onPressed,
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
          child: Text(
            label,
            style: AppTheme.label(
              fontSize: 9,
              color: filled ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

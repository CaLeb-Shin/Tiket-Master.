import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/scanner_device.dart';
import 'package:melon_core/data/repositories/scanner_device_repository.dart';
import 'package:melon_core/services/functions_service.dart';

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
      appBar: AppBar(
        title: Text(
          '스캐너 기기 승인',
          style: GoogleFonts.notoSans(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<List<ScannerDevice>>(
        stream: devicesAsync,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.gold),
            );
          }

          final all = snapshot.data ?? const <ScannerDevice>[];
          final filtered = all.where(_matchesFilter).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _DeviceFilter.values.map((filter) {
                    final selected = filter == _filter;
                    return ChoiceChip(
                      label: Text(filter.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = filter),
                      selectedColor: AppTheme.goldSubtle,
                      backgroundColor: AppTheme.card,
                      side: BorderSide(
                        color: selected ? AppTheme.gold : AppTheme.border,
                        width: 0.8,
                      ),
                      labelStyle: GoogleFonts.notoSans(
                        color: selected ? AppTheme.gold : AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    '총 ${all.length}대 · 표시 ${filtered.length}대',
                    style: GoogleFonts.notoSans(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '표시할 기기가 없습니다.',
                          style: GoogleFonts.notoSans(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final device = filtered[index];
                          return _DeviceCard(
                            device: device,
                            onApprove: () => _setApproval(device.id, approved: true, blocked: false),
                            onRevoke: () => _setApproval(
                              device.id,
                              approved: false,
                              blocked: false,
                            ),
                            onBlock: () => _setApproval(
                              device.id,
                              approved: false,
                              blocked: true,
                            ),
                            onUnblock: () => _setApproval(
                              device.id,
                              approved: false,
                              blocked: false,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
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
      stateLabel = '차단';
    } else if (device.approved) {
      stateColor = AppTheme.success;
      stateLabel = '승인';
    } else {
      stateColor = AppTheme.warning;
      stateLabel = '대기';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  device.label.isEmpty ? device.id : device.label,
                  style: GoogleFonts.notoSans(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stateLabel,
                  style: GoogleFonts.notoSans(
                    color: stateColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${device.ownerDisplayName} · ${device.ownerEmail}',
            style: GoogleFonts.notoSans(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '플랫폼 ${device.platform} | 요청 $requested | 최근접속 $lastSeen',
            style: GoogleFonts.notoSans(color: AppTheme.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!device.approved && !device.blocked)
                FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(86, 34),
                  ),
                  child: Text(
                    '승인',
                    style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                  ),
                ),
              if (device.approved)
                OutlinedButton(
                  onPressed: onRevoke,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(86, 34),
                    side: const BorderSide(color: AppTheme.warning),
                    foregroundColor: AppTheme.warning,
                  ),
                  child: Text(
                    '승인해제',
                    style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                  ),
                ),
              if (!device.blocked)
                OutlinedButton(
                  onPressed: onBlock,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(86, 34),
                    side: const BorderSide(color: AppTheme.error),
                    foregroundColor: AppTheme.error,
                  ),
                  child: Text(
                    '차단',
                    style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                  ),
                ),
              if (device.blocked)
                FilledButton(
                  onPressed: onUnblock,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    foregroundColor: const Color(0xFF1A1119),
                    minimumSize: const Size(86, 34),
                  ),
                  child: Text(
                    '차단해제',
                    style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}


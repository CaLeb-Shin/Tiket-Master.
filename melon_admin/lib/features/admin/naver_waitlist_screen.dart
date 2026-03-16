import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/infrastructure/firebase/functions_service.dart';

// =============================================================================
// 대기열 관리 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

const _gradeOrder = ['VIP', 'R', 'S', 'A'];

const _gradeColors = {
  'VIP': Color(0xFFE53935),
  'R': Color(0xFF1E88E5),
  'S': Color(0xFF43A047),
  'A': Color(0xFFFDD835),
};

enum _WaitlistFilter { all, waiting, assigned, cancelled }

class NaverWaitlistScreen extends ConsumerStatefulWidget {
  final String eventId;
  const NaverWaitlistScreen({super.key, required this.eventId});

  @override
  ConsumerState<NaverWaitlistScreen> createState() =>
      _NaverWaitlistScreenState();
}

class _NaverWaitlistScreenState extends ConsumerState<NaverWaitlistScreen> {
  _WaitlistFilter _filter = _WaitlistFilter.all;
  String? _expandedEntryId;
  bool _assignLoading = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _waitlistStream =>
      FirebaseFirestore.instance
          .collection('waitlist')
          .where('eventId', isEqualTo: widget.eventId)
          .orderBy('requestedAt', descending: false)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          // ── Editorial App Bar ──
          _buildAppBar(),

          // ── Content ──
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _waitlistStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '오류: ${snapshot.error}',
                      style: AdminTheme.sans(color: AdminTheme.error),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AdminTheme.gold),
                  );
                }

                final docs = snapshot.data!.docs;
                final entries = docs.map((doc) {
                  final data = Map<String, dynamic>.from(doc.data());
                  data['id'] = doc.id;
                  return data;
                }).toList();

                return _buildContent(entries);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── App Bar ───

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
          bottom: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
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
                  Icons.west,
                  color: AdminTheme.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waitlist',
                      style: AdminTheme.serif(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      widget.eventId,
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
          // Action buttons row
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 자동 배정
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: _assignLoading ? null : _assignFromWaitlist,
                    icon: _assignLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AdminTheme.info,
                            ),
                          )
                        : const Icon(Icons.assignment_turned_in_rounded,
                            size: 14),
                    label: Text(
                      '자동 배정',
                      style: AdminTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.info,
                      side: BorderSide(
                        color: AdminTheme.info.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                // 대기 등록
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddDialog(),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      '대기 등록',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Content ───

  Widget _buildContent(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: 36,
              color: AdminTheme.sage.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '대기열이 비어 있습니다',
              style: AdminTheme.sans(
                fontSize: 14,
                color: AdminTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\'대기 등록\' 버튼으로 첫 대기를 추가하세요',
              style: AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    final waiting =
        entries.where((e) => e['status'] == 'waiting').toList();
    final assigned =
        entries.where((e) => e['status'] == 'assigned').toList();
    final cancelled =
        entries.where((e) => e['status'] == 'cancelled').toList();

    // Filter
    List<Map<String, dynamic>> filtered;
    switch (_filter) {
      case _WaitlistFilter.all:
        filtered = entries;
      case _WaitlistFilter.waiting:
        filtered = waiting;
      case _WaitlistFilter.assigned:
        filtered = assigned;
      case _WaitlistFilter.cancelled:
        filtered = cancelled;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary Cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text('SUMMARY', style: AdminTheme.label(fontSize: 10)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _SummaryCard(
                  label: 'WAITING',
                  value: '${waiting.length}',
                  color: AdminTheme.gold,
                ),
                const SizedBox(width: 10),
                _SummaryCard(
                  label: 'ASSIGNED',
                  value: '${assigned.length}',
                  color: AdminTheme.info,
                ),
                const SizedBox(width: 10),
                _SummaryCard(
                  label: 'CANCELLED',
                  value: '${cancelled.length}',
                  color: AdminTheme.error,
                ),
                const SizedBox(width: 10),
                _SummaryCard(
                  label: 'TOTAL',
                  value: '${entries.length}',
                  color: AdminTheme.textPrimary,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Filter Tabs ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ..._WaitlistFilter.values.map((f) {
                  final selected = f == _filter;
                  final label = switch (f) {
                    _WaitlistFilter.all => 'ALL',
                    _WaitlistFilter.waiting => 'WAITING',
                    _WaitlistFilter.assigned => 'ASSIGNED',
                    _WaitlistFilter.cancelled => 'CANCELLED',
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              selected ? AdminTheme.gold : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: selected
                                ? AdminTheme.gold
                                : AdminTheme.sage.withValues(alpha: 0.25),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          label,
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
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Section Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Entries',
                  style: AdminTheme.serif(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
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
                Text(
                  '${filtered.length}',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Entry List ──
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              thickness: 0.5,
              color: AdminTheme.sage.withValues(alpha: 0.12),
            ),
            itemBuilder: (_, i) {
              final entry = filtered[i];
              final entryId = entry['id'] as String;
              final isExpanded = _expandedEntryId == entryId;
              return _WaitlistRow(
                entry: entry,
                isExpanded: isExpanded,
                onToggleExpand: () {
                  setState(() {
                    _expandedEntryId = isExpanded ? null : entryId;
                  });
                },
                onCancel: () => _cancelEntry(entryId),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Add to Waitlist Dialog ───

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final memoCtrl = TextEditingController();
    String selectedGrade = 'VIP';
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AdminTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          title: Text(
            '대기 등록',
            style: AdminTheme.serif(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grade dropdown
                Text('좌석 등급',
                    style: AdminTheme.label(color: AdminTheme.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedGrade,
                  dropdownColor: AdminTheme.card,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  ),
                  items: _gradeOrder.map((g) {
                    final color = _gradeColors[g] ?? AdminTheme.textPrimary;
                    return DropdownMenuItem(
                      value: g,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(g),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedGrade = v);
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Name
                Text('구매자명',
                    style: AdminTheme.label(color: AdminTheme.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(hintText: '이름'),
                ),
                const SizedBox(height: 16),
                // Phone
                Text('전화번호',
                    style: AdminTheme.label(color: AdminTheme.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration:
                      const InputDecoration(hintText: '010-0000-0000'),
                ),
                const SizedBox(height: 16),
                // Memo
                Text('메모',
                    style: AdminTheme.label(color: AdminTheme.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: memoCtrl,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(hintText: '(선택)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: Text(
                '취소',
                style: AdminTheme.sans(color: AdminTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          phoneCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('이름과 전화번호를 입력하세요')),
                        );
                        return;
                      }
                      setDialogState(() => isLoading = true);
                      try {
                        await ref
                            .read(functionsServiceProvider)
                            .addToWaitlist(
                              eventId: widget.eventId,
                              seatGrade: selectedGrade,
                              buyerName: nameCtrl.text.trim(),
                              buyerPhone: phoneCtrl.text.trim(),
                              memo: memoCtrl.text.trim().isEmpty
                                  ? null
                                  : memoCtrl.text.trim(),
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('대기 등록 완료')),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('오류: $e')),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AdminTheme.onAccent,
                      ),
                    )
                  : Text(
                      '등록',
                      style: AdminTheme.sans(
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.onAccent,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Assign from Waitlist ───

  Future<void> _assignFromWaitlist() async {
    setState(() => _assignLoading = true);
    try {
      final result = await ref
          .read(functionsServiceProvider)
          .assignFromWaitlist(eventId: widget.eventId);
      if (mounted) {
        final assigned = result['assignedCount'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$assigned건 배정 완료')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('배정 오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _assignLoading = false);
    }
  }

  // ─── Cancel Entry ───

  Future<void> _cancelEntry(String waitlistId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        title: Text(
          '대기 취소',
          style: AdminTheme.serif(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '이 대기 항목을 취소하시겠습니까?',
          style: AdminTheme.sans(color: AdminTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '아니오',
              style: AdminTheme.sans(color: AdminTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.error,
              foregroundColor: Colors.white,
            ),
            child: Text(
              '취소 확인',
              style: AdminTheme.sans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(functionsServiceProvider)
          .cancelWaitlistEntry(waitlistId: waitlistId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('대기 취소 완료')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 오류: $e')),
        );
      }
    }
  }
}

// =============================================================================
// Summary Card
// =============================================================================

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
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AdminTheme.sage.withValues(alpha: 0.1),
            width: 0.5,
          ),
          boxShadow: AdminShadows.small,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AdminTheme.label(fontSize: 9, color: AdminTheme.sage),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: AdminTheme.serif(
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

// =============================================================================
// Waitlist Row (Expandable)
// =============================================================================

class _WaitlistRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCancel;

  const _WaitlistRow({
    required this.entry,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onCancel,
  });

  String _maskPhone(String phone) {
    // 010-1234-5678 → 010-****-5678
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) {
      return '${digits.substring(0, 3)}-****-${digits.substring(digits.length - 4)}';
    }
    return phone;
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    if (ts is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
    }
    return ts.toString();
  }

  @override
  Widget build(BuildContext context) {
    final grade = entry['seatGrade'] as String? ?? '';
    final buyerName = entry['buyerName'] as String? ?? '';
    final buyerPhone = entry['buyerPhone'] as String? ?? '';
    final status = entry['status'] as String? ?? 'waiting';
    final requestedAt = entry['requestedAt'];
    final assignedAt = entry['assignedAt'];
    final memo = entry['memo'] as String? ?? '';
    final naverOrderId = entry['naverOrderId'] as String? ?? '';

    final gradeColor = _gradeColors[grade] ?? AdminTheme.textPrimary;

    final statusColor = switch (status) {
      'waiting' => AdminTheme.gold,
      'assigned' => AdminTheme.info,
      'cancelled' => AdminTheme.error,
      'expired' => AdminTheme.sage,
      _ => AdminTheme.textSecondary,
    };

    final statusLabel = switch (status) {
      'waiting' => 'WAITING',
      'assigned' => 'ASSIGNED',
      'cancelled' => 'CANCELLED',
      'expired' => 'EXPIRED',
      _ => status.toUpperCase(),
    };

    return GestureDetector(
      onTap: onToggleExpand,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main Row ──
            Row(
              children: [
                // Grade badge
                Container(
                  width: 36,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: gradeColor.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    grade,
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: gradeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name + phone
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        buyerName,
                        style: AdminTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _maskPhone(buyerPhone),
                        style: AdminTheme.sans(
                          fontSize: 11,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Requested at
                Text(
                  _formatTimestamp(requestedAt),
                  style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 12),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: AdminTheme.label(
                      fontSize: 8,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Expand icon
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AdminTheme.sage.withValues(alpha: 0.5),
                ),
              ],
            ),

            // ── Expanded Detail ──
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminTheme.card,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AdminTheme.sage.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (memo.isNotEmpty) ...[
                      Text('MEMO',
                          style: AdminTheme.label(
                              fontSize: 9, color: AdminTheme.sage)),
                      const SizedBox(height: 4),
                      Text(
                        memo,
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (assignedAt != null) ...[
                      Text('ASSIGNED AT',
                          style: AdminTheme.label(
                              fontSize: 9, color: AdminTheme.sage)),
                      const SizedBox(height: 4),
                      Text(
                        _formatTimestamp(assignedAt),
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (naverOrderId.isNotEmpty) ...[
                      Text('NAVER ORDER ID',
                          style: AdminTheme.label(
                              fontSize: 9, color: AdminTheme.sage)),
                      const SizedBox(height: 4),
                      Text(
                        naverOrderId,
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.gold,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('PHONE',
                        style: AdminTheme.label(
                            fontSize: 9, color: AdminTheme.sage)),
                    const SizedBox(height: 4),
                    Text(
                      buyerPhone,
                      style: AdminTheme.sans(
                        fontSize: 12,
                        color: AdminTheme.textSecondary,
                      ),
                    ),
                    // Cancel button (only for waiting entries)
                    if (status == 'waiting') ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(Icons.cancel_outlined, size: 14),
                          label: Text(
                            '대기 취소',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminTheme.error,
                            side: BorderSide(
                              color: AdminTheme.error.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'scanner_device_approval_screen.dart';

// ─────────────────────────────────────────────
// 실시간 체크인 대시보드
// 태블릿 QR 스캔 → PC에서 실시간 입장 현황 확인
// ─────────────────────────────────────────────

class CheckinDashboardScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const CheckinDashboardScreen({super.key, this.eventId});

  @override
  ConsumerState<CheckinDashboardScreen> createState() =>
      _CheckinDashboardScreenState();
}

class _CheckinDashboardScreenState
    extends ConsumerState<CheckinDashboardScreen> {
  String? _selectedEventId;
  String? _gradeFilter; // null=전체, 'VIP'/'R'/'S'/'A'=등급 필터
  int _viewMode = 0; // 0=명단, 1=체크인 로그
  final _timeFmt = DateFormat('HH:mm:ss');
  final _dateFmt = DateFormat('MM.dd HH:mm');

  @override
  void initState() {
    super.initState();
    _selectedEventId = widget.eventId;
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(allEventsStreamProvider);

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            eventsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('오류: $e',
                  style: const TextStyle(color: AdminTheme.error)),
              data: (events) => _buildEventSelector(events),
            ),
            const SizedBox(height: 16),
            if (_selectedEventId != null) ...[
              _buildStatsRow(),
              const SizedBox(height: 12),
              _buildViewToggle(),
              const SizedBox(height: 8),
              Expanded(
                child: _viewMode == 0
                    ? _buildCheckinList()
                    : _buildCheckinFeed(),
              ),
            ] else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded,
                          size: 64,
                          color: AdminTheme.textTertiary),
                      const SizedBox(height: 16),
                      Text(
                        '공연을 선택하면 실시간 체크인 현황이 표시됩니다',
                        style: TextStyle(
                          color: AdminTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 3,
          height: 28,
          decoration: BoxDecoration(
            color: AdminTheme.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '실시간 체크인',
          style: AdminTheme.serif(fontSize: 22, color: AdminTheme.textPrimary),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AdminTheme.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AdminTheme.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LIVE',
                style: AdminTheme.label(
                    fontSize: 10, color: AdminTheme.success),
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ScannerDeviceApprovalScreen(),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AdminTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.devices_other,
                    size: 14, color: AdminTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '스캐너 기기 관리',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventSelector(List<Event> events) {
    final active = events.where((e) =>
        e.status != EventStatus.completed &&
        e.status != EventStatus.canceled).toList();
    final sorted = active
      ..sort((a, b) => (b.startAt ?? DateTime(2000))
          .compareTo(a.startAt ?? DateTime(2000)));
    final recent = sorted.take(20).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedEventId,
          hint: Text('공연 선택',
              style: TextStyle(color: AdminTheme.textSecondary)),
          dropdownColor: AdminTheme.cardElevated,
          style: TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
          items: recent.map((e) {
            final dateStr = e.startAt != null
                ? _dateFmt.format(e.startAt!)
                : '';
            return DropdownMenuItem(
              value: e.id,
              child: Text(
                '${e.title}  $dateStr',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (v) => setState(() {
            _selectedEventId = v;
            _gradeFilter = null;
          }),
        ),
      ),
    );
  }

  // ── 축소된 통계 카드 (클릭으로 필터) ──
  Widget _buildStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mobileTickets')
          .where('eventId', isEqualTo: _selectedEventId)
          .snapshots(),
      builder: (context, snapshot) {
        int total = 0;
        int entryChecked = 0;
        int intermissionChecked = 0;
        final gradeCount = <String, int>{};
        final gradeChecked = <String, int>{};

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
          total = docs.length;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final grade = (data['seatGrade'] as String?) ?? '미지정';
            gradeCount[grade] = (gradeCount[grade] ?? 0) + 1;

            if (data['entryCheckedInAt'] != null) {
              entryChecked++;
              gradeChecked[grade] = (gradeChecked[grade] ?? 0) + 1;
            }
            if (data['intermissionCheckedInAt'] != null) {
              intermissionChecked++;
            }
          }
        }

        final gradeOrder = ['VIP', 'R', 'S', 'A'];
        final sortedGrades = gradeCount.keys.toList()
          ..sort((a, b) {
            final ai = gradeOrder.indexOf(a);
            final bi = gradeOrder.indexOf(b);
            return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
          });

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildCompactCard(
              label: '전체',
              checked: entryChecked,
              total: total,
              color: AdminTheme.gold,
              icon: Icons.people_rounded,
              isSelected: _gradeFilter == null,
              onTap: () => setState(() => _gradeFilter = null),
            ),
            if (intermissionChecked > 0)
              _buildCompactCard(
                label: '인터미션',
                checked: intermissionChecked,
                total: entryChecked,
                color: AdminTheme.info,
                icon: Icons.replay_rounded,
                isSelected: false,
                onTap: () {},
              ),
            ...sortedGrades.map((grade) {
              final cnt = gradeCount[grade] ?? 0;
              final chk = gradeChecked[grade] ?? 0;
              return _buildCompactCard(
                label: '${grade}석',
                checked: chk,
                total: cnt,
                color: _gradeColor(grade),
                isSelected: _gradeFilter == grade,
                onTap: () => setState(() {
                  _gradeFilter = _gradeFilter == grade ? null : grade;
                }),
              );
            }),
          ],
        );
      },
    );
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'VIP':
        return const Color(0xFFFF6B6B);
      case 'R':
        return const Color(0xFF60A5FA);
      case 'S':
        return const Color(0xFF4ADE80);
      case 'A':
        return const Color(0xFFFFD700);
      default:
        return AdminTheme.textSecondary;
    }
  }

  Widget _buildCompactCard({
    required String label,
    required int checked,
    required int total,
    required Color color,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final ratio = total > 0 ? checked / total : 0.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : AdminTheme.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.6)
                : color.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 11, color: color),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: AdminTheme.label(fontSize: 9, color: color)),
                const Spacer(),
                Text('${(ratio * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 9, color: AdminTheme.textTertiary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$checked / $total',
              style: AdminTheme.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3,
                backgroundColor: AdminTheme.surface,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return Row(
      children: [
        _toggleButton('전체 명단', 0, Icons.people_rounded),
        const SizedBox(width: 8),
        _toggleButton('체크인 로그', 1, Icons.receipt_long_rounded),
      ],
    );
  }

  Widget _toggleButton(String label, int mode, IconData icon) {
    final isActive = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AdminTheme.gold.withValues(alpha: 0.15)
              : AdminTheme.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? AdminTheme.gold.withValues(alpha: 0.5)
                : AdminTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: isActive ? AdminTheme.gold : AdminTheme.textTertiary),
            const SizedBox(width: 4),
            Text(
              label,
              style: AdminTheme.sans(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AdminTheme.gold : AdminTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 전체 명단 (등급 필터 적용) ──
  Widget _buildCheckinList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mobileTickets')
          .where('eventId', isEqualTo: _selectedEventId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text('티켓이 없습니다',
                style: TextStyle(color: AdminTheme.textSecondary)),
          );
        }

        var docs = snapshot.data!.docs;

        // 등급 필터 적용
        if (_gradeFilter != null) {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['seatGrade'] as String?) == _gradeFilter;
          }).toList();
        }

        // 입장한 사람 먼저, 그 안에서 입장 시간 최신순
        final sorted = List<QueryDocumentSnapshot>.from(docs)
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aChecked = aData['entryCheckedInAt'] as Timestamp?;
            final bChecked = bData['entryCheckedInAt'] as Timestamp?;
            if (aChecked != null && bChecked == null) return -1;
            if (aChecked == null && bChecked != null) return 1;
            if (aChecked != null && bChecked != null) {
              return bChecked.compareTo(aChecked);
            }
            final aName = (aData['buyerName'] as String?) ?? '';
            final bName = (bData['buyerName'] as String?) ?? '';
            return aName.compareTo(bName);
          });

        final checkedCount =
            sorted.where((d) => (d.data() as Map)['entryCheckedInAt'] != null).length;

        final filterLabel = _gradeFilter != null ? '$_gradeFilter석' : '전체';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$filterLabel 명단',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$checkedCount / ${sorted.length}',
                    style: AdminTheme.label(
                        fontSize: 10, color: AdminTheme.success),
                  ),
                ),
                if (_gradeFilter != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _gradeFilter = null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AdminTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 10,
                              color: AdminTheme.textTertiary),
                          const SizedBox(width: 2),
                          Text('필터 해제',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AdminTheme.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // 테이블 헤더
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  SizedBox(width: 32, child: Text('', style: _headerStyle())),
                  SizedBox(width: 80, child: Text('이름', style: _headerStyle())),
                  SizedBox(width: 100, child: Text('연락처', style: _headerStyle())),
                  SizedBox(width: 44, child: Text('등급', style: _headerStyle())),
                  Expanded(child: Text('좌석', style: _headerStyle())),
                  SizedBox(width: 65, child: Text('입장시각', style: _headerStyle())),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: ListView.builder(
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final data =
                      sorted[index].data() as Map<String, dynamic>;
                  return _buildListItem(data);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  TextStyle _headerStyle() {
    return AdminTheme.label(fontSize: 9, color: AdminTheme.textTertiary);
  }

  Widget _buildListItem(Map<String, dynamic> data) {
    final name = (data['buyerName'] as String?) ?? '';
    final phone = (data['buyerPhone'] as String?) ?? '';
    final grade = (data['seatGrade'] as String?) ?? '';
    final seatInfo = (data['seatInfo'] as String?) ?? '';
    final checkedAt = data['entryCheckedInAt'] as Timestamp?;
    final isChecked = checkedAt != null;
    final timeStr = isChecked ? _timeFmt.format(checkedAt.toDate()) : '';
    final maskedPhone = phone.length >= 8
        ? '${phone.substring(0, 3)}-****-${phone.substring(phone.length - 4)}'
        : phone;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isChecked
            ? AdminTheme.success.withValues(alpha: 0.04)
            : AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Icon(
              isChecked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 14,
              color: isChecked ? AdminTheme.success : AdminTheme.textTertiary,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              maskedPhone,
              style: TextStyle(fontSize: 11, color: AdminTheme.textSecondary),
            ),
          ),
          SizedBox(
            width: 44,
            child: grade.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _gradeColor(grade).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      grade,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _gradeColor(grade),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Text(
              seatInfo,
              style: TextStyle(fontSize: 11, color: AdminTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 65,
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isChecked ? FontWeight.w500 : FontWeight.w400,
                color: isChecked ? AdminTheme.success : AdminTheme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('checkins')
          .where('eventId', isEqualTo: _selectedEventId)
          .where('result', isEqualTo: 'success')
          .orderBy('scannedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_rounded,
                    size: 48, color: AdminTheme.textTertiary),
                const SizedBox(height: 12),
                Text(
                  '아직 체크인 기록이 없습니다',
                  style: TextStyle(
                      color: AdminTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '태블릿에서 QR을 스캔하면 여기에 실시간으로 표시됩니다',
                  style: TextStyle(
                      color: AdminTheme.textTertiary, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '체크인 로그',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminTheme.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${docs.length}건',
                    style: AdminTheme.label(
                        fontSize: 10, color: AdminTheme.gold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return _buildCheckinItem(data, isLatest: index == 0);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCheckinItem(Map<String, dynamic> data,
      {bool isLatest = false}) {
    final ticketId = data['ticketId'] as String? ?? '';
    final seatInfo = data['seatInfo'] as String? ?? '정보 없음';
    final stage = data['stage'] as String? ?? 'entry';
    final scannedAt = data['scannedAt'] as Timestamp?;
    final timeStr =
        scannedAt != null ? _timeFmt.format(scannedAt.toDate()) : '--:--:--';

    final isEntry = stage == 'entry';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('mobileTickets')
          .doc(ticketId)
          .get(),
      builder: (context, ticketSnap) {
        String buyerName = '';
        String seatGrade = '';
        int? entryNumber;

        if (ticketSnap.hasData && ticketSnap.data!.exists) {
          final t = ticketSnap.data!.data() as Map<String, dynamic>;
          buyerName = (t['buyerName'] as String?) ?? '';
          seatGrade = (t['seatGrade'] as String?) ?? '';
          entryNumber = t['entryNumber'] as int?;
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isLatest
                ? AdminTheme.gold.withValues(alpha: 0.06)
                : AdminTheme.card,
            borderRadius: BorderRadius.circular(6),
            border: isLatest
                ? Border.all(color: AdminTheme.gold.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 65,
                child: Text(
                  timeStr,
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isLatest
                        ? AdminTheme.gold
                        : AdminTheme.textSecondary,
                  ),
                ),
              ),
              Container(
                width: 52,
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isEntry
                      ? AdminTheme.success.withValues(alpha: 0.15)
                      : AdminTheme.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isEntry ? '입장' : '재입장',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isEntry ? AdminTheme.success : AdminTheme.info,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: Text(
                  buyerName.isNotEmpty ? buyerName : '...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (seatGrade.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color:
                        _gradeColor(seatGrade).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${seatGrade}석',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _gradeColor(seatGrade),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  seatInfo,
                  style: TextStyle(
                    fontSize: 11,
                    color: AdminTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entryNumber != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$entryNumber',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

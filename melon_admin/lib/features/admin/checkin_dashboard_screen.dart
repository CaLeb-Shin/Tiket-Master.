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
  int _viewMode = 0; // 0=현황+로그, 1=명단
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
            const SizedBox(height: 24),
            // 공연 선택
            eventsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('오류: $e',
                  style: const TextStyle(color: AdminTheme.error)),
              data: (events) => _buildEventSelector(events),
            ),
            const SizedBox(height: 24),
            // 실시간 대시보드
            if (_selectedEventId != null) ...[
              _buildStatsRow(),
              const SizedBox(height: 16),
              _buildViewToggle(),
              const SizedBox(height: 16),
              Expanded(
                child: _viewMode == 0
                    ? _buildCheckinFeed()
                    : _buildCheckinList(),
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
    // 종료/취소 공연 제외, 최근 공연 우선 (startAt 내림차순), 상위 20개
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
          onChanged: (v) => setState(() => _selectedEventId = v),
        ),
      ),
    );
  }

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

        // 등급 순서: VIP → R → S → A → 기타
        final gradeOrder = ['VIP', 'R', 'S', 'A'];
        final sortedGrades = gradeCount.keys.toList()
          ..sort((a, b) {
            final ai = gradeOrder.indexOf(a);
            final bi = gradeOrder.indexOf(b);
            return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
          });

        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _buildStatCard(
              '전체 입장',
              '$entryChecked / $total',
              total > 0 ? entryChecked / total : 0,
              AdminTheme.gold,
              icon: Icons.people_rounded,
            ),
            if (intermissionChecked > 0)
              _buildStatCard(
                '인터미션',
                '$intermissionChecked / $entryChecked',
                entryChecked > 0 ? intermissionChecked / entryChecked : 0,
                AdminTheme.info,
                icon: Icons.replay_rounded,
              ),
            ...sortedGrades.map((grade) {
              final cnt = gradeCount[grade] ?? 0;
              final chk = gradeChecked[grade] ?? 0;
              return _buildStatCard(
                '${grade}석',
                '$chk / $cnt',
                cnt > 0 ? chk / cnt : 0,
                _gradeColor(grade),
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

  Widget _buildStatCard(
    String label,
    String value,
    double ratio,
    Color color, {
    IconData? icon,
  }) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AdminTheme.label(fontSize: 10, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AdminTheme.sans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: AdminTheme.surface,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(ratio * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              color: AdminTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Row(
      children: [
        _toggleButton('체크인 로그', 0, Icons.receipt_long_rounded),
        const SizedBox(width: 8),
        _toggleButton('전체 명단', 1, Icons.people_rounded),
      ],
    );
  }

  Widget _toggleButton(String label, int mode, IconData icon) {
    final isActive = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                size: 14,
                color: isActive ? AdminTheme.gold : AdminTheme.textTertiary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AdminTheme.gold : AdminTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 전체 명단 (티켓 기반, 입장 여부 표시) ──
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

        final docs = snapshot.data!.docs;
        // 입장한 사람 먼저, 그 안에서 입장 시간 최신순
        final sorted = List<QueryDocumentSnapshot>.from(docs)
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aChecked = aData['entryCheckedInAt'] as Timestamp?;
            final bChecked = bData['entryCheckedInAt'] as Timestamp?;
            // 입장한 사람 먼저
            if (aChecked != null && bChecked == null) return -1;
            if (aChecked == null && bChecked != null) return 1;
            // 둘 다 입장 → 최신 먼저
            if (aChecked != null && bChecked != null) {
              return bChecked.compareTo(aChecked);
            }
            // 둘 다 미입장 → 이름순
            final aName = (aData['buyerName'] as String?) ?? '';
            final bName = (bData['buyerName'] as String?) ?? '';
            return aName.compareTo(bName);
          });

        final checkedCount =
            sorted.where((d) => (d.data() as Map)['entryCheckedInAt'] != null).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '전체 명단',
                  style: AdminTheme.sans(
                    fontSize: 14,
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
              ],
            ),
            const SizedBox(height: 8),
            // 테이블 헤더
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  SizedBox(
                      width: 40,
                      child: Text('상태',
                          style: _headerStyle())),
                  SizedBox(
                      width: 80,
                      child: Text('이름',
                          style: _headerStyle())),
                  SizedBox(
                      width: 100,
                      child: Text('연락처',
                          style: _headerStyle())),
                  SizedBox(
                      width: 50,
                      child: Text('등급',
                          style: _headerStyle())),
                  Expanded(
                      child: Text('좌석',
                          style: _headerStyle())),
                  SizedBox(
                      width: 70,
                      child: Text('입장시각',
                          style: _headerStyle())),
                ],
              ),
            ),
            const SizedBox(height: 4),
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
    return AdminTheme.label(fontSize: 10, color: AdminTheme.textTertiary);
  }

  Widget _buildListItem(Map<String, dynamic> data) {
    final name = (data['buyerName'] as String?) ?? '';
    final phone = (data['buyerPhone'] as String?) ?? '';
    final grade = (data['seatGrade'] as String?) ?? '';
    final seatInfo = (data['seatInfo'] as String?) ?? '';
    final checkedAt = data['entryCheckedInAt'] as Timestamp?;
    final isChecked = checkedAt != null;
    final timeStr = isChecked ? _timeFmt.format(checkedAt.toDate()) : '';
    // 연락처 마스킹: 010-1234-5678 → 010-****-5678
    final maskedPhone = phone.length >= 8
        ? '${phone.substring(0, 3)}-****-${phone.substring(phone.length - 4)}'
        : phone;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isChecked
            ? AdminTheme.success.withValues(alpha: 0.04)
            : AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // 상태 아이콘
          SizedBox(
            width: 40,
            child: Icon(
              isChecked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 16,
              color: isChecked ? AdminTheme.success : AdminTheme.textTertiary,
            ),
          ),
          // 이름
          SizedBox(
            width: 80,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 연락처
          SizedBox(
            width: 100,
            child: Text(
              maskedPhone,
              style: TextStyle(
                fontSize: 12,
                color: AdminTheme.textSecondary,
              ),
            ),
          ),
          // 등급
          SizedBox(
            width: 50,
            child: grade.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _gradeColor(grade).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      grade,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _gradeColor(grade),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 좌석
          Expanded(
            child: Text(
              seatInfo,
              style: TextStyle(
                fontSize: 12,
                color: AdminTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 입장 시각
          SizedBox(
            width: 70,
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
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
                    fontSize: 14,
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
            const SizedBox(height: 12),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              // 시간
              SizedBox(
                width: 70,
                child: Text(
                  timeStr,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isLatest
                        ? AdminTheme.gold
                        : AdminTheme.textSecondary,
                  ),
                ),
              ),
              // 체크인 단계 뱃지
              Container(
                width: 60,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isEntry ? AdminTheme.success : AdminTheme.info,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 구매자 이름
              SizedBox(
                width: 80,
                child: Text(
                  buyerName.isNotEmpty ? buyerName : '...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // 등급 뱃지
              if (seatGrade.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        _gradeColor(seatGrade).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${seatGrade}석',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _gradeColor(seatGrade),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // 좌석 정보
              Expanded(
                child: Text(
                  seatInfo,
                  style: TextStyle(
                    fontSize: 12,
                    color: AdminTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 입장 번호
              if (entryNumber != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$entryNumber',
                    style: TextStyle(
                      fontSize: 11,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/repositories/event_repository.dart';

// =============================================================================
// 모의 티켓 생성 — 등급/좌석 선택 → Firestore 직접 생성 → 마이티켓에서 확인
// =============================================================================

const _gradeOrder = ['VIP', 'R', 'S', 'A'];
const _gradeColors = {
  'VIP': Color(0xFFC9A84C),
  'R': Color(0xFF6B4FA0),
  'S': Color(0xFF2D6A4F),
  'A': Color(0xFF3B7DD8),
};

class MockTicketScreen extends ConsumerStatefulWidget {
  const MockTicketScreen({super.key});

  @override
  ConsumerState<MockTicketScreen> createState() => _MockTicketScreenState();
}

enum _Step { selectEvent, selectSeats, done }

class _MockTicketScreenState extends ConsumerState<MockTicketScreen> {
  _Step _step = _Step.selectEvent;
  bool _loading = false;

  // 선택 상태
  Event? _selectedEvent;
  String? _selectedGrade;
  List<Seat> _availableSeats = [];
  final Set<String> _selectedSeatIds = {};
  Map<String, List<Seat>> _seatsByGrade = {};

  // 유저 선택
  List<Map<String, dynamic>> _users = [];
  String? _selectedUserId;
  bool _loadingUsers = false;

  // 결과
  final _results = <_TicketResult>[];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .get();

      final users = snapshot.docs.map((d) {
        final data = d.data();
        return {
          'uid': d.id,
          'displayName': data['displayName'] ?? '이름 없음',
          'email': data['email'] ?? '',
          'provider': data['provider'] ?? '',
          'isDemo': data['isDemo'] == true,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _users = users;
          _selectedUserId = FirebaseAuth.instance.currentUser?.uid;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingUsers = false);
  }

  void _reset() {
    setState(() {
      _step = _Step.selectEvent;
      _selectedEvent = null;
      _selectedGrade = null;
      _availableSeats = [];
      _selectedSeatIds.clear();
      _seatsByGrade = {};
    });
  }

  Future<void> _createTestUser() async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final testUserId = 'test_user_${DateTime.now().millisecondsSinceEpoch}';
      await db.collection('users').doc(testUserId).set({
        'displayName': '테스트 사용자',
        'email': 'test@melonticket.com',
        'provider': 'test',
        'isDemo': false,
        'mileage': 0,
        'mileageTier': 'bronze',
        'badges': <String>[],
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
      await _loadUsers();
      if (mounted) {
        setState(() => _selectedUserId = testUserId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('테스트 사용자가 생성되었습니다'),
            backgroundColor: AdminTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: AdminTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildMainContent()),
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: AdminTheme.surface,
                    border: Border(
                      left: BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                  ),
                  child: _buildResultPanel(),
                ),
              ],
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
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_step != _Step.selectEvent) {
                _reset();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.west,
                color: AdminTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MOCK TICKETS',
                    style:
                        AdminTheme.label(fontSize: 10, color: AdminTheme.gold)),
                const SizedBox(height: 2),
                Text(
                  _step == _Step.selectEvent
                      ? '공연을 선택하세요'
                      : _step == _Step.selectSeats
                          ? '${_selectedEvent?.title ?? ''} — 등급/좌석 선택'
                          : '티켓 생성 완료',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AdminTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: AdminTheme.gold),
            ),
        ],
      ),
    );
  }

  // ─── Main Content ───
  Widget _buildMainContent() {
    switch (_step) {
      case _Step.selectEvent:
        final eventsAsync = ref.watch(eventsStreamProvider);
        return eventsAsync.when(
          data: (events) => _buildEventList(events),
          loading: () => const Center(
              child: CircularProgressIndicator(color: AdminTheme.gold)),
          error: (e, _) => Center(
              child: Text('오류: $e',
                  style: AdminTheme.sans(color: AdminTheme.error))),
        );
      case _Step.selectSeats:
        return _buildSeatSelector();
      case _Step.done:
        return _buildDoneView();
    }
  }

  // ─── Step 1: Event List ───
  Widget _buildEventList(List<Event> events) {
    if (events.isEmpty) {
      return Center(
          child: Text('등록된 공연이 없습니다',
              style: AdminTheme.sans(color: AdminTheme.textSecondary)));
    }

    final dateFmt = DateFormat('M/d(E) HH:mm', 'ko_KR');
    final priceFmt = NumberFormat('#,###', 'ko_KR');

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final event = events[i];
        return GestureDetector(
          onTap: () => _onSelectEvent(event),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminTheme.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: event.imageUrl != null
                      ? Image.network(event.imageUrl!,
                          width: 48, height: 64, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdminTheme.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AdminTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                          '${dateFmt.format(event.startAt)}  ·  ${priceFmt.format(event.price)}원',
                          style: AdminTheme.sans(
                              fontSize: 12, color: AdminTheme.textSecondary)),
                      const SizedBox(height: 2),
                      Text('잔여 ${event.availableSeats}석',
                          style: AdminTheme.sans(
                              fontSize: 11,
                              color: event.availableSeats > 0
                                  ? AdminTheme.success
                                  : AdminTheme.error,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AdminTheme.sage, size: 22),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
      width: 48,
      height: 64,
      color: AdminTheme.cardElevated,
      child:
          const Icon(Icons.music_note_rounded, color: AdminTheme.sage, size: 22));

  // ─── Load seats ───
  Future<void> _onSelectEvent(Event event) async {
    setState(() {
      _loading = true;
      _selectedEvent = event;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('seats')
          .where('eventId', isEqualTo: event.id)
          .where('status', isEqualTo: 'available')
          .get();

      final seats = snapshot.docs.map((d) => Seat.fromFirestore(d)).toList();
      seats.sort((a, b) {
        final ga = _gradeOrder.indexOf(a.grade ?? '');
        final gb = _gradeOrder.indexOf(b.grade ?? '');
        if (ga != gb) return ga.compareTo(gb);
        return a.number.compareTo(b.number);
      });

      final byGrade = <String, List<Seat>>{};
      for (final s in seats) {
        final g = s.grade ?? '기타';
        byGrade.putIfAbsent(g, () => []).add(s);
      }

      setState(() {
        _availableSeats = seats;
        _seatsByGrade = byGrade;
        _selectedGrade = byGrade.keys.isNotEmpty ? byGrade.keys.first : null;
        _step = _Step.selectSeats;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('좌석 로드 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Step 2: Grade + Seat Selection ───
  Widget _buildSeatSelector() {
    if (_availableSeats.isEmpty) {
      return Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_seat_rounded,
              size: 40, color: AdminTheme.sage),
          const SizedBox(height: 12),
          Text('잔여 좌석이 없습니다',
              style: AdminTheme.sans(color: AdminTheme.textSecondary)),
          const SizedBox(height: 16),
          TextButton(onPressed: _reset, child: const Text('돌아가기')),
        ],
      ));
    }

    final priceFmt = NumberFormat('#,###', 'ko_KR');
    final event = _selectedEvent!;
    final priceByGrade = event.priceByGrade ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 대상 계정 선택 ──
          Row(
            children: [
              Text('대상 계정',
                  style: AdminTheme.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AdminTheme.textPrimary)),
              const Spacer(),
              GestureDetector(
                onTap: _loading ? null : _createTestUser,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: AdminTheme.gold),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('+ 테스트 계정 생성',
                      style: AdminTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.gold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingUsers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AdminTheme.gold),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AdminTheme.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminTheme.border),
              ),
              child: DropdownButton<String>(
                value: _selectedUserId,
                isExpanded: true,
                dropdownColor: AdminTheme.card,
                underline: const SizedBox.shrink(),
                hint: Text('계정을 선택하세요',
                    style: AdminTheme.sans(
                        fontSize: 13, color: AdminTheme.textTertiary)),
                items: _users.map((u) {
                  final uid = u['uid'] as String;
                  final name = u['displayName'] as String;
                  final email = u['email'] as String;
                  final provider = u['provider'] as String;
                  final isMe =
                      uid == FirebaseAuth.instance.currentUser?.uid;
                  final isDemo = u['isDemo'] == true;

                  return DropdownMenuItem(
                    value: uid,
                    child: Row(
                      children: [
                        Icon(
                          provider == 'test'
                              ? Icons.science_rounded
                              : isDemo
                                  ? Icons.person_outline_rounded
                                  : Icons.person_rounded,
                          size: 16,
                          color: isMe
                              ? AdminTheme.gold
                              : AdminTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$name${isMe ? " (나)" : ""}',
                            style: AdminTheme.sans(
                              fontSize: 13,
                              fontWeight:
                                  isMe ? FontWeight.w700 : FontWeight.w500,
                              color: isMe
                                  ? AdminTheme.gold
                                  : AdminTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(email,
                              style: AdminTheme.sans(
                                  fontSize: 10,
                                  color: AdminTheme.textTertiary)),
                        if (provider == 'test') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AdminTheme.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('TEST',
                                style: AdminTheme.sans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AdminTheme.gold)),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedUserId = v),
              ),
            ),
          const SizedBox(height: 24),

          // ── 등급 선택 탭 ──
          Text('등급 선택',
              style: AdminTheme.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AdminTheme.textPrimary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _seatsByGrade.entries.map((entry) {
              final grade = entry.key;
              final seats = entry.value;
              final isSelected = _selectedGrade == grade;
              final gradeColor =
                  _gradeColors[grade] ?? AdminTheme.textSecondary;
              final price = priceByGrade[grade] ?? event.price;

              return GestureDetector(
                onTap: () => setState(() {
                  _selectedGrade = grade;
                  _selectedSeatIds.clear();
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? gradeColor.withValues(alpha: 0.15)
                        : AdminTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isSelected
                            ? gradeColor
                            : AdminTheme.border,
                        width: isSelected ? 1.5 : 1),
                  ),
                  child: Column(
                    children: [
                      Text(grade,
                          style: AdminTheme.sans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: gradeColor)),
                      const SizedBox(height: 2),
                      Text('${seats.length}석',
                          style: AdminTheme.sans(
                              fontSize: 11, color: AdminTheme.textSecondary)),
                      Text('${priceFmt.format(price)}원',
                          style: AdminTheme.sans(
                              fontSize: 11,
                              color: AdminTheme.textTertiary)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // ── 좌석 선택 그리드 ──
          if (_selectedGrade != null) ...[
            Row(
              children: [
                Text('좌석 선택',
                    style: AdminTheme.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AdminTheme.textPrimary)),
                const Spacer(),
                Text(
                    '${_selectedSeatIds.length}석 선택됨',
                    style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.gold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('좌석을 클릭하면 선택/해제됩니다',
                style:
                    AdminTheme.sans(fontSize: 12, color: AdminTheme.textTertiary)),
            const SizedBox(height: 12),
            _buildSeatGrid(),
            const SizedBox(height: 24),

            // ── 생성 버튼 ──
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _selectedSeatIds.isNotEmpty &&
                        !_loading &&
                        _selectedUserId != null
                    ? _createMockTickets
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.gold,
                  foregroundColor: AdminTheme.onAccent,
                  disabledBackgroundColor: AdminTheme.cardElevated,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AdminTheme.onAccent))
                    : Text(
                        '${_selectedSeatIds.length}매 모의 티켓 생성',
                        style: AdminTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AdminTheme.onAccent),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeatGrid() {
    final seats = _seatsByGrade[_selectedGrade] ?? [];
    final gradeColor =
        _gradeColors[_selectedGrade] ?? AdminTheme.textSecondary;

    // 행(row)별로 그룹핑
    final byRow = <String, List<Seat>>{};
    for (final s in seats) {
      final rowKey = s.row ?? '-';
      byRow.putIfAbsent(rowKey, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: byRow.entries.map((entry) {
        final rowLabel = entry.key;
        final rowSeats = entry.value..sort((a, b) => a.number.compareTo(b.number));

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 열 라벨
              SizedBox(
                width: 36,
                child: Text(
                  rowLabel == '-' ? '' : '$rowLabel열',
                  style: AdminTheme.sans(
                      fontSize: 11, color: AdminTheme.textTertiary),
                ),
              ),
              // 좌석들
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: rowSeats.map((seat) {
                    final isSelected = _selectedSeatIds.contains(seat.id);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedSeatIds.remove(seat.id);
                          } else {
                            _selectedSeatIds.add(seat.id);
                          }
                        });
                      },
                      child: Container(
                        width: 36,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? gradeColor
                              : gradeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? gradeColor
                                : gradeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${seat.number}',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : gradeColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Create tickets in Firestore ───
  Future<void> _createMockTickets() async {
    if (_loading || _selectedSeatIds.isEmpty || _selectedEvent == null) return;
    setState(() => _loading = true);

    try {
      final db = FirebaseFirestore.instance;
      final userId = _selectedUserId ?? FirebaseAuth.instance.currentUser!.uid;
      final event = _selectedEvent!;
      final now = DateTime.now();
      final quantity = _selectedSeatIds.length;

      final priceByGrade = event.priceByGrade ?? {};
      final unitPrice = priceByGrade[_selectedGrade] ?? event.price;
      final totalAmount = unitPrice * quantity;

      final batch = db.batch();

      // 1) Order 생성
      final orderRef = db.collection('orders').doc();
      batch.set(orderRef, {
        'eventId': event.id,
        'userId': userId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalAmount': totalAmount,
        'status': 'paid',
        'createdAt': Timestamp.fromDate(now),
        'paidAt': Timestamp.fromDate(now),
      });

      // 2) SeatBlock 생성
      final seatBlockRef = db.collection('seatBlocks').doc();
      final seatIdList = _selectedSeatIds.toList();
      batch.set(seatBlockRef, {
        'eventId': event.id,
        'orderId': orderRef.id,
        'userId': userId,
        'quantity': quantity,
        'seatIds': seatIdList,
        'hidden': false,
        'assignedAt': Timestamp.fromDate(now),
      });

      // 3) Ticket 생성 + Seat status 업데이트
      final ticketIds = <String>[];
      final seatLabels = <String>[];
      for (final seatId in seatIdList) {
        // Ticket
        final ticketRef = db.collection('tickets').doc();
        ticketIds.add(ticketRef.id);
        batch.set(ticketRef, {
          'eventId': event.id,
          'orderId': orderRef.id,
          'userId': userId,
          'seatId': seatId,
          'seatBlockId': seatBlockRef.id,
          'status': 'issued',
          'qrVersion': 1,
          'issuedAt': Timestamp.fromDate(now),
        });

        // Seat → reserved
        final seatRef = db.collection('seats').doc(seatId);
        batch.update(seatRef, {
          'status': 'reserved',
          'orderId': orderRef.id,
          'reservedAt': Timestamp.fromDate(now),
        });

        // 라벨 수집
        final seat = _availableSeats.firstWhere((s) => s.id == seatId);
        seatLabels.add(seat.displayName);
      }

      // 4) Event availableSeats 감소
      final eventRef = db.collection('events').doc(event.id);
      batch.update(eventRef, {
        'availableSeats': FieldValue.increment(-quantity),
      });

      await batch.commit();

      // 선택된 유저 이름
      final userName = _users
              .where((u) => u['uid'] == userId)
              .map((u) => u['displayName'] as String)
              .firstOrNull ??
          userId;

      setState(() {
        _results.insert(
          0,
          _TicketResult(
            eventTitle: event.title,
            grade: _selectedGrade ?? '',
            seatLabels: seatLabels,
            ticketIds: ticketIds,
            orderId: orderRef.id,
            createdAt: now,
            success: true,
            userName: userName,
          ),
        );
        _step = _Step.done;
      });
    } catch (e) {
      setState(() {
        _results.insert(
          0,
          _TicketResult(
            eventTitle: _selectedEvent?.title ?? '',
            grade: _selectedGrade ?? '',
            seatLabels: [],
            ticketIds: [],
            orderId: null,
            createdAt: DateTime.now(),
            success: false,
            error: '$e',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Step 3: Done ───
  Widget _buildDoneView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 56, color: AdminTheme.success),
          const SizedBox(height: 16),
          Text('모의 티켓 생성 완료!',
              style: AdminTheme.sans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AdminTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('티켓앱 마이티켓에서 확인하세요',
              style: AdminTheme.sans(
                  fontSize: 14, color: AdminTheme.textSecondary)),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('추가 생성',
                    style: AdminTheme.sans(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminTheme.gold,
                  side: const BorderSide(color: AdminTheme.gold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/');
                  }
                },
                icon: const Icon(Icons.dashboard_rounded, size: 18),
                label: Text('대시보드',
                    style: AdminTheme.sans(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminTheme.textSecondary,
                  side: const BorderSide(color: AdminTheme.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Result Panel (right) ───
  Widget _buildResultPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_rounded,
                  size: 16, color: AdminTheme.gold),
              const SizedBox(width: 8),
              Text('생성 이력',
                  style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textPrimary)),
              const Spacer(),
              if (_results.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _results.clear()),
                  child: Text('전체 삭제',
                      style: AdminTheme.sans(
                          fontSize: 11, color: AdminTheme.textTertiary)),
                ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 36,
                          color: AdminTheme.sage.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('생성 이력이 여기에 표시됩니다',
                          textAlign: TextAlign.center,
                          style: AdminTheme.sans(
                              fontSize: 13, color: AdminTheme.textTertiary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _results.length,
                  itemBuilder: (_, i) => _ResultCard(result: _results[i]),
                ),
        ),
      ],
    );
  }
}

// ─── Data ───

class _TicketResult {
  final String eventTitle;
  final String grade;
  final List<String> seatLabels;
  final List<String> ticketIds;
  final String? orderId;
  final DateTime createdAt;
  final bool success;
  final String? error;
  final String? userName;

  const _TicketResult({
    required this.eventTitle,
    required this.grade,
    required this.seatLabels,
    required this.ticketIds,
    required this.orderId,
    required this.createdAt,
    required this.success,
    this.error,
    this.userName,
  });
}

// ─── Result Card ───

class _ResultCard extends StatelessWidget {
  final _TicketResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm:ss');
    final gradeColor = _gradeColors[result.grade] ?? AdminTheme.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.success
            ? AdminTheme.success.withValues(alpha: 0.06)
            : AdminTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.success
              ? AdminTheme.success.withValues(alpha: 0.2)
              : AdminTheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  result.success
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  size: 14,
                  color: result.success ? AdminTheme.success : AdminTheme.error),
              const SizedBox(width: 6),
              if (result.grade.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(result.grade,
                      style: AdminTheme.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: gradeColor)),
                ),
              Expanded(
                child: Text(result.eventTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary)),
              ),
              Text(timeFmt.format(result.createdAt),
                  style: AdminTheme.sans(
                      fontSize: 10, color: AdminTheme.textTertiary)),
            ],
          ),
          if (result.userName != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_rounded,
                    size: 12, color: AdminTheme.sage),
                const SizedBox(width: 6),
                Text(result.userName!,
                    style: AdminTheme.sans(
                        fontSize: 11, color: AdminTheme.textSecondary)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          if (result.success) ...[
            ...result.seatLabels.map((label) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.event_seat_rounded,
                          size: 12, color: AdminTheme.sage),
                      const SizedBox(width: 6),
                      Text(label,
                          style: AdminTheme.sans(
                              fontSize: 12, color: AdminTheme.textPrimary)),
                    ],
                  ),
                )),
          ] else
            Text(result.error ?? '알 수 없는 오류',
                style: AdminTheme.sans(fontSize: 12, color: AdminTheme.error)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/order.dart' as order_model;
import 'package:melon_core/data/models/ticket.dart';
import 'package:melon_core/data/models/app_user.dart';
import 'package:melon_core/services/firestore_service.dart';
import 'package:melon_core/data/models/seat_block.dart';

// =============================================================================
// 좌석 배정 현황 관리 (Seat Manager — Dot Map + Table View)
// =============================================================================

/// 좌석 + 부가정보 (예매자, 주문, 티켓, 배정 블록)
class _SeatInfo {
  final Seat seat;
  final order_model.Order? order;
  final AppUser? user;
  final Ticket? ticket;
  final SeatBlock? seatBlock;

  _SeatInfo({
    required this.seat,
    this.order,
    this.user,
    this.ticket,
    this.seatBlock,
  });
}

class EventSeatManagerScreen extends ConsumerStatefulWidget {
  final String eventId;

  const EventSeatManagerScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventSeatManagerScreen> createState() =>
      _EventSeatManagerScreenState();
}

class _EventSeatManagerScreenState
    extends ConsumerState<EventSeatManagerScreen> {
  bool _isLoading = true;
  List<_SeatInfo> _seatInfos = [];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isDotMapView = true; // true=dotmap, false=table
  _SeatInfo? _selectedSeat;

  // ── Summary counts ──
  int _totalSeats = 0;
  int _availableCount = 0;
  int _reservedCount = 0;
  int _usedCount = 0;
  int _blockedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      final fs = ref.read(firestoreServiceProvider);

      // 1) Load all seats for this event
      final seatSnapshot = await fs.seats
          .where('eventId', isEqualTo: widget.eventId)
          .get();
      final seats =
          seatSnapshot.docs.map((doc) => Seat.fromFirestore(doc)).toList();

      // 2) Collect unique orderIds
      final orderIds = <String>{};
      for (final seat in seats) {
        if (seat.orderId != null && seat.orderId!.isNotEmpty) {
          orderIds.add(seat.orderId!);
        }
      }

      // 3) Batch-fetch orders
      final orderMap = <String, order_model.Order>{};
      final orderIdList = orderIds.toList();
      for (var i = 0; i < orderIdList.length; i += 10) {
        final chunk = orderIdList.sublist(
            i, i + 10 > orderIdList.length ? orderIdList.length : i + 10);
        final snap =
            await fs.orders.where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in snap.docs) {
          orderMap[doc.id] = order_model.Order.fromFirestore(doc);
        }
      }

      // 4) Collect unique userIds from orders
      final userIds = <String>{};
      for (final order in orderMap.values) {
        if (order.userId.isNotEmpty) userIds.add(order.userId);
      }

      // 5) Batch-fetch users
      final userMap = <String, AppUser>{};
      final userIdList = userIds.toList();
      for (var i = 0; i < userIdList.length; i += 10) {
        final chunk = userIdList.sublist(
            i, i + 10 > userIdList.length ? userIdList.length : i + 10);
        final snap =
            await fs.users.where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in snap.docs) {
          userMap[doc.id] = AppUser.fromFirestore(doc);
        }
      }

      // 6) Fetch tickets for this event
      final ticketSnapshot = await fs.tickets
          .where('eventId', isEqualTo: widget.eventId)
          .get();
      final tickets =
          ticketSnapshot.docs.map((doc) => Ticket.fromFirestore(doc)).toList();

      // Map ticket by seatId
      final ticketBySeatId = <String, Ticket>{};
      for (final ticket in tickets) {
        if (ticket.seatId.isNotEmpty) {
          ticketBySeatId[ticket.seatId] = ticket;
        }
      }

      // 7) Fetch seat blocks for this event
      final seatBlockSnapshot = await fs.seatBlocks
          .where('eventId', isEqualTo: widget.eventId)
          .get();
      final seatBlocks = seatBlockSnapshot.docs
          .map((doc) => SeatBlock.fromFirestore(doc))
          .toList();

      // Map seatBlock by seatId (a seat can be in exactly one block)
      final seatBlockMap = <String, SeatBlock>{};
      for (final block in seatBlocks) {
        for (final seatId in block.seatIds) {
          seatBlockMap[seatId] = block;
        }
      }

      // 8) Compose _SeatInfo list
      final infos = seats.map((seat) {
        final order =
            seat.orderId != null ? orderMap[seat.orderId!] : null;
        final user = order != null ? userMap[order.userId] : null;
        final ticket = ticketBySeatId[seat.id];
        final seatBlock = seatBlockMap[seat.id];
        return _SeatInfo(
          seat: seat,
          order: order,
          user: user,
          ticket: ticket,
          seatBlock: seatBlock,
        );
      }).toList();

      // Sort: block -> floor -> row -> number
      infos.sort((a, b) {
        final blockCmp = a.seat.block.compareTo(b.seat.block);
        if (blockCmp != 0) return blockCmp;
        final floorCmp = a.seat.floor.compareTo(b.seat.floor);
        if (floorCmp != 0) return floorCmp;
        final rowA = a.seat.row ?? '';
        final rowB = b.seat.row ?? '';
        final rowCmp = rowA.compareTo(rowB);
        if (rowCmp != 0) return rowCmp;
        return a.seat.number.compareTo(b.seat.number);
      });

      // Compute summary
      int available = 0, reserved = 0, used = 0, blocked = 0;
      for (final info in infos) {
        switch (info.seat.status) {
          case SeatStatus.available:
            available++;
            break;
          case SeatStatus.reserved:
            reserved++;
            break;
          case SeatStatus.used:
            used++;
            break;
          case SeatStatus.blocked:
            blocked++;
            break;
        }
      }

      if (mounted) {
        setState(() {
          _seatInfos = infos;
          _totalSeats = infos.length;
          _availableCount = available;
          _reservedCount = reserved;
          _usedCount = used;
          _blockedCount = blocked;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 오류: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH / FILTER
  // ═══════════════════════════════════════════════════════════════════════════

  List<_SeatInfo> get _filteredSeats {
    if (_searchQuery.isEmpty) return _seatInfos;
    final q = _searchQuery.toLowerCase();
    return _seatInfos.where((info) {
      // Match seat display name
      if (info.seat.displayName.toLowerCase().contains(q)) return true;
      if (info.seat.shortName.toLowerCase().contains(q)) return true;
      // Match booker name
      if (info.user?.displayName?.toLowerCase().contains(q) == true) {
        return true;
      }
      // Match orderId
      if (info.order?.id.toLowerCase().contains(q) == true) return true;
      return false;
    }).toList();
  }

  bool _isHighlighted(_SeatInfo info) {
    if (_searchQuery.isEmpty) return false;
    final q = _searchQuery.toLowerCase();
    if (info.seat.displayName.toLowerCase().contains(q)) return true;
    if (info.seat.shortName.toLowerCase().contains(q)) return true;
    if (info.user?.displayName?.toLowerCase().contains(q) == true) return true;
    if (info.order?.id.toLowerCase().contains(q) == true) return true;
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS COLOR
  // ═══════════════════════════════════════════════════════════════════════════

  Color _statusColor(SeatStatus status) {
    switch (status) {
      case SeatStatus.available:
        return const Color(0xFF43A047);
      case SeatStatus.reserved:
        return const Color(0xFFC9A84C);
      case SeatStatus.used:
        return const Color(0xFF1E88E5);
      case SeatStatus.blocked:
        return const Color(0xFFE53935);
    }
  }

  String _statusLabel(SeatStatus status) {
    switch (status) {
      case SeatStatus.available:
        return '예매 가능';
      case SeatStatus.reserved:
        return '예약됨';
      case SeatStatus.used:
        return '입장 완료';
      case SeatStatus.blocked:
        return '차단';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: AdminTheme.gold),
              ),
            )
          else ...[
            _buildSummaryBar(),
            _buildToolbar(),
            Expanded(
              child: _isDotMapView ? _buildDotMapView() : _buildTableView(),
            ),
          ],
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
            'Seat Manager',
            style: AdminTheme.serif(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh,
                color: AdminTheme.textSecondary, size: 20),
            tooltip: '새로고침',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUMMARY BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(
          bottom: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _summaryChip('전체', _totalSeats, AdminTheme.textPrimary),
          const SizedBox(width: 16),
          _summaryChip('예매가능', _availableCount, const Color(0xFF43A047)),
          const SizedBox(width: 16),
          _summaryChip('예약됨', _reservedCount, const Color(0xFFC9A84C)),
          const SizedBox(width: 16),
          _summaryChip('입장완료', _usedCount, const Color(0xFF1E88E5)),
          const SizedBox(width: 16),
          _summaryChip('차단', _blockedCount, const Color(0xFFE53935)),
          const Spacer(),
          if (_seatInfos
              .any((i) => i.seatBlock != null && i.seatBlock!.hidden))
            SizedBox(
              height: 30,
              child: ElevatedButton.icon(
                onPressed: _revealAllSeatBlocks,
                icon: const Icon(Icons.visibility, size: 14),
                label: Text('전체 공개',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      noShadow: true,
                    )),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      AdminTheme.gold.withValues(alpha: 0.15),
                  foregroundColor: AdminTheme.gold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 12,
            color: AdminTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: AdminTheme.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOOLBAR (Search + View Toggle)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AdminTheme.sage.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: AdminTheme.sans(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '좌석번호 또는 예매자 이름 검색...',
                  hintStyle: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textTertiary,
                  ),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AdminTheme.textTertiary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close,
                              size: 16, color: AdminTheme.textTertiary),
                          padding: EdgeInsets.zero,
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // View toggle
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AdminTheme.sage.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewToggleButton(
                  icon: Icons.grid_view_rounded,
                  label: '도트맵',
                  isActive: _isDotMapView,
                  onTap: () => setState(() => _isDotMapView = true),
                ),
                Container(
                  width: 0.5,
                  height: 20,
                  color: AdminTheme.sage.withValues(alpha: 0.2),
                ),
                _viewToggleButton(
                  icon: Icons.table_rows_rounded,
                  label: '테이블',
                  isActive: !_isDotMapView,
                  onTap: () => setState(() => _isDotMapView = false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewToggleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AdminTheme.gold.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color:
                  isActive ? AdminTheme.gold : AdminTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AdminTheme.sans(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AdminTheme.gold
                    : AdminTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOT MAP VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDotMapView() {
    if (_seatInfos.isEmpty) {
      return Center(
        child: Text(
          '등록된 좌석이 없습니다',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
        ),
      );
    }

    return Row(
      children: [
        // Main dot map area
        Expanded(
          flex: 3,
          child: _buildDotMapCanvas(),
        ),
        // Detail panel (right side)
        if (_selectedSeat != null)
          SizedBox(
            width: 340,
            child: _buildDetailPanel(_selectedSeat!),
          ),
      ],
    );
  }

  Widget _buildDotMapCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Stage indicator
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              margin: const EdgeInsets.fromLTRB(40, 12, 40, 4),
              decoration: BoxDecoration(
                color: AdminTheme.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AdminTheme.gold.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Center(
                child: Text(
                  'STAGE',
                  style: AdminTheme.label(
                    fontSize: 9,
                    color: AdminTheme.gold,
                  ),
                ),
              ),
            ),
            // Dot map
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(100),
                child: Center(
                  child: _DotMapInteractive(
                    seatInfos: _seatInfos,
                    searchQuery: _searchQuery,
                    selectedSeatId: _selectedSeat?.seat.id,
                    hiddenSeatIds: _seatInfos
                        .where((i) =>
                            i.seatBlock != null && i.seatBlock!.hidden)
                        .map((i) => i.seat.id)
                        .toSet(),
                    statusColorFn: _statusColor,
                    isHighlightedFn: _isHighlighted,
                    onSeatTap: (info) =>
                        setState(() => _selectedSeat = info),
                    canvasSize: Size(
                      constraints.maxWidth - 40,
                      constraints.maxHeight - 60,
                    ),
                  ),
                ),
              ),
            ),
            // Color legend
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot('예매가능', const Color(0xFF43A047)),
                  const SizedBox(width: 16),
                  _legendDot('예약됨', const Color(0xFFC9A84C)),
                  const SizedBox(width: 16),
                  _legendDot('입장완료', const Color(0xFF1E88E5)),
                  const SizedBox(width: 16),
                  _legendDot('차단', const Color(0xFFE53935)),
                  const SizedBox(width: 16),
                  _legendDotHidden('미공개'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 10,
            color: AdminTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _legendDotHidden(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AdminTheme.sage.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Center(
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: AdminTheme.sage.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 10,
            color: AdminTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAIL PANEL (Right side on seat click)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailPanel(_SeatInfo info) {
    final seat = info.seat;
    final order = info.order;
    final user = info.user;
    final ticket = info.ticket;

    return Container(
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(
          left: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AdminTheme.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor(seat.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    seat.displayName,
                    style: AdminTheme.serif(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedSeat = null),
                  icon: const Icon(Icons.close,
                      size: 18, color: AdminTheme.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Seat info
                  _detailSection('좌석 정보'),
                  const SizedBox(height: 12),
                  _detailRow('좌석', seat.displayName),
                  _detailRow('등급', seat.grade ?? '-'),
                  _detailRow('상태', _statusLabel(seat.status)),
                  _detailRow('유형', seat.seatType),
                  if (seat.gridX != null && seat.gridY != null)
                    _detailRow(
                        '그리드', '(${seat.gridX}, ${seat.gridY})'),

                  if (order != null || user != null) ...[
                    const SizedBox(height: 24),
                    _detailSection('예매자 정보'),
                    const SizedBox(height: 12),
                    _detailRow('이름', user?.displayName ?? '-'),
                    _detailRow('전화번호', user?.phoneNumber ?? '-'),
                    _detailRow('이메일', user?.email ?? '-'),
                  ],

                  if (order != null) ...[
                    const SizedBox(height: 24),
                    _detailSection('주문 정보'),
                    const SizedBox(height: 12),
                    _detailRow('주문번호', order.id),
                    _detailRow(
                      '주문일시',
                      DateFormat('yyyy.MM.dd HH:mm').format(order.createdAt),
                    ),
                    _detailRow(
                      '금액',
                      '${NumberFormat('#,###').format(order.totalAmount)}원',
                    ),
                    _detailRow('주문상태', order.status.displayName),
                  ],

                  if (ticket != null) ...[
                    const SizedBox(height: 24),
                    _detailSection('티켓 정보'),
                    const SizedBox(height: 12),
                    _detailRow('티켓ID', ticket.id),
                    _detailRow('티켓상태', ticket.status.displayName),
                    _detailRow(
                      '입장체크인',
                      ticket.isEntryCheckedIn
                          ? DateFormat('HH:mm')
                              .format(ticket.entryCheckedInAt!)
                          : '미체크인',
                    ),
                    if (ticket.intermissionCheckedInAt != null)
                      _detailRow(
                        '인터미션',
                        DateFormat('HH:mm')
                            .format(ticket.intermissionCheckedInAt!),
                      ),
                  ],

                  // ── SeatBlock (배정) 정보 ──
                  if (info.seatBlock != null) ...[
                    const SizedBox(height: 24),
                    _detailSection('배정 정보'),
                    const SizedBox(height: 12),
                    _detailRow('블록 ID', info.seatBlock!.id),
                    _detailRow('배정 좌석 수', '${info.seatBlock!.quantity}석'),
                    _detailRow(
                      '배정일시',
                      DateFormat('yyyy.MM.dd HH:mm')
                          .format(info.seatBlock!.assignedAt),
                    ),
                    _detailRow(
                      '공개 상태',
                      info.seatBlock!.hidden ? '미공개 (숨김)' : '공개됨',
                    ),
                  ],

                  // ── 관리 액션 버튼 ──
                  const SizedBox(height: 32),
                  _detailSection('관리'),
                  const SizedBox(height: 12),
                  if (seat.status == SeatStatus.available)
                    _actionButton(
                      '차단',
                      Icons.block,
                      AdminTheme.error,
                      () => _blockSeat(seat.id),
                    ),
                  if (seat.status == SeatStatus.blocked)
                    _actionButton(
                      '차단 해제',
                      Icons.check_circle_outline,
                      AdminTheme.success,
                      () => _unblockSeat(seat.id),
                    ),
                  if (info.seatBlock != null && info.seatBlock!.hidden)
                    _actionButton(
                      '좌석 공개',
                      Icons.visibility,
                      AdminTheme.gold,
                      () => _revealSeatBlock(info.seatBlock!.id),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title) {
    return Row(
      children: [
        Text(
          title,
          style: AdminTheme.serif(
            fontSize: 13,
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
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: AdminTheme.sans(
                fontSize: 11,
                color: AdminTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AdminTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTON + SEAT MANAGEMENT ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 14),
          label: Text(
            label,
            style: AdminTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              noShadow: true,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ),
    );
  }

  Future<void> _blockSeat(String seatId) async {
    try {
      final fs = ref.read(firestoreServiceProvider);
      await fs.seats.doc(seatId).update({'status': 'blocked'});
      _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('좌석이 차단되었습니다',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  Future<void> _unblockSeat(String seatId) async {
    try {
      final fs = ref.read(firestoreServiceProvider);
      await fs.seats.doc(seatId).update({'status': 'available'});
      _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('차단이 해제되었습니다',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  Future<void> _revealSeatBlock(String seatBlockId) async {
    try {
      final fs = ref.read(firestoreServiceProvider);
      await fs.seatBlocks.doc(seatBlockId).update({'hidden': false});
      _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('좌석이 공개되었습니다',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  Future<void> _revealAllSeatBlocks() async {
    try {
      final fs = ref.read(firestoreServiceProvider);
      final hiddenBlocks = _seatInfos
          .where((i) => i.seatBlock != null && i.seatBlock!.hidden)
          .map((i) => i.seatBlock!.id)
          .toSet()
          .toList();

      if (hiddenBlocks.isEmpty) return;

      var batch = fs.batch();
      var pending = 0;
      for (final blockId in hiddenBlocks) {
        batch.update(fs.seatBlocks.doc(blockId), {'hidden': false});
        pending++;
        if (pending == 500) {
          await batch.commit();
          batch = fs.batch();
          pending = 0;
        }
      }
      if (pending > 0) await batch.commit();

      _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${hiddenBlocks.length}개 블록이 공개되었습니다',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e',
                style: AdminTheme.sans(
                    fontSize: 13, color: Colors.white, noShadow: true)),
            backgroundColor: AdminTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTableView() {
    final filtered = _filteredSeats;

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? '검색 결과가 없습니다' : '등록된 좌석이 없습니다',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Table header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: const BoxDecoration(
                  color: AdminTheme.surface,
                  border: Border(
                    bottom: BorderSide(color: AdminTheme.border, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    _tableHeaderCell('좌석', flex: 3),
                    _tableHeaderCell('등급', flex: 1),
                    _tableHeaderCell('상태', flex: 2),
                    _tableHeaderCell('예매자', flex: 2),
                    _tableHeaderCell('전화번호', flex: 2),
                    _tableHeaderCell('주문번호', flex: 3),
                  ],
                ),
              ),
              // Table rows
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final info = filtered[index];
                    final isSelected =
                        _selectedSeat?.seat.id == info.seat.id;
                    final highlighted = _isHighlighted(info);

                    return InkWell(
                      onTap: () => setState(() => _selectedSeat = info),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AdminTheme.gold.withValues(alpha: 0.08)
                              : highlighted
                                  ? AdminTheme.gold.withValues(alpha: 0.04)
                                  : Colors.transparent,
                          border: const Border(
                            bottom: BorderSide(
                              color: AdminTheme.borderLight,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _tableCellWidget(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _statusColor(info.seat.status),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      info.seat.displayName,
                                      style: AdminTheme.sans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              flex: 3,
                            ),
                            _tableCell(info.seat.grade ?? '-', flex: 1),
                            _tableStatusCell(info.seat.status, flex: 2),
                            _tableCell(
                              info.user?.displayName ?? '-',
                              flex: 2,
                            ),
                            _tableCell(
                              info.user?.phoneNumber ?? '-',
                              flex: 2,
                            ),
                            _tableCell(
                              info.order?.id ?? '-',
                              flex: 3,
                              mono: true,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Detail panel
        if (_selectedSeat != null)
          SizedBox(
            width: 340,
            child: _buildDetailPanel(_selectedSeat!),
          ),
      ],
    );
  }

  Widget _tableHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AdminTheme.label(
          fontSize: 9,
          color: AdminTheme.sage,
        ),
      ),
    );
  }

  Widget _tableCell(String text, {int flex = 1, bool mono = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: mono
            ? AdminTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AdminTheme.textSecondary,
                letterSpacing: -0.3,
              )
            : AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.textPrimary,
              ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _tableCellWidget(Widget child, {int flex = 1}) {
    return Expanded(flex: flex, child: child);
  }

  Widget _tableStatusCell(SeatStatus status, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              _statusLabel(status),
              style: AdminTheme.sans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _statusColor(status),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CUSTOM PAINTER — Dot Map
// =============================================================================

class _SeatDotMapPainter extends CustomPainter {
  final List<_SeatInfo> seatInfos;
  final String searchQuery;
  final String? selectedSeatId;
  final Set<String> hiddenSeatIds;
  final Color Function(SeatStatus) statusColorFn;
  final bool Function(_SeatInfo) isHighlightedFn;

  _SeatDotMapPainter({
    required this.seatInfos,
    required this.searchQuery,
    this.selectedSeatId,
    required this.hiddenSeatIds,
    required this.statusColorFn,
    required this.isHighlightedFn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (seatInfos.isEmpty) return;

    // ── Determine grid bounds ──
    // If seats have gridX/gridY, use them. Otherwise, auto-arrange.
    final hasGrid = seatInfos.any(
        (info) => info.seat.gridX != null && info.seat.gridY != null);

    if (hasGrid) {
      _paintWithGrid(canvas, size);
    } else {
      _paintAutoArrange(canvas, size);
    }
  }

  void _paintWithGrid(Canvas canvas, Size size) {
    int minX = 999999, maxX = -999999;
    int minY = 999999, maxY = -999999;

    for (final info in seatInfos) {
      final x = info.seat.gridX ?? 0;
      final y = info.seat.gridY ?? 0;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    final rangeX = (maxX - minX).clamp(1, 999999);
    final rangeY = (maxY - minY).clamp(1, 999999);

    const padding = 20.0;
    final drawW = size.width - padding * 2;
    final drawH = size.height - padding * 2;

    final cellW = drawW / (rangeX + 1);
    final cellH = drawH / (rangeY + 1);
    final dotRadius = (cellW < cellH ? cellW : cellH) * 0.35;

    for (final info in seatInfos) {
      final gx = info.seat.gridX ?? 0;
      final gy = info.seat.gridY ?? 0;

      final cx = padding + (gx - minX) * cellW + cellW / 2;
      final cy = padding + (gy - minY) * cellH + cellH / 2;

      _drawSeatDot(canvas, cx, cy, dotRadius, info);
    }
  }

  void _paintAutoArrange(Canvas canvas, Size size) {
    // Group seats by block+floor+row, arrange in grid
    final groups = <String, List<_SeatInfo>>{};
    for (final info in seatInfos) {
      final key =
          '${info.seat.block}|${info.seat.floor}|${info.seat.row ?? ''}';
      groups.putIfAbsent(key, () => []).add(info);
    }

    // Sort each group by seat number
    for (final group in groups.values) {
      group.sort((a, b) => a.seat.number.compareTo(b.seat.number));
    }

    // Sorted group keys
    final sortedKeys = groups.keys.toList()..sort();

    final maxSeatsInRow =
        groups.values.fold<int>(0, (max, g) => g.length > max ? g.length : max);
    final totalRows = sortedKeys.length;

    if (totalRows == 0 || maxSeatsInRow == 0) return;

    const padding = 24.0;
    final drawW = size.width - padding * 2;
    final drawH = size.height - padding * 2;

    final cellW = drawW / maxSeatsInRow;
    final cellH = drawH / totalRows;
    final dotRadius = ((cellW < cellH ? cellW : cellH) * 0.35).clamp(2.0, 8.0);

    for (var rowIdx = 0; rowIdx < sortedKeys.length; rowIdx++) {
      final key = sortedKeys[rowIdx];
      final group = groups[key]!;
      // Center seats in row
      final startX = padding + (drawW - group.length * cellW) / 2;

      for (var colIdx = 0; colIdx < group.length; colIdx++) {
        final info = group[colIdx];
        final cx = startX + colIdx * cellW + cellW / 2;
        final cy = padding + rowIdx * cellH + cellH / 2;

        _drawSeatDot(canvas, cx, cy, dotRadius, info);
      }
    }
  }

  void _drawSeatDot(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    _SeatInfo info,
  ) {
    final color = statusColorFn(info.seat.status);
    final isSelected = info.seat.id == selectedSeatId;
    final isHidden = hiddenSeatIds.contains(info.seat.id);
    final isHighlighted =
        searchQuery.isNotEmpty && isHighlightedFn(info);

    // Dim non-matching seats if search is active
    final alpha =
        searchQuery.isNotEmpty && !isHighlighted ? 0.15 : 1.0;

    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), radius, paint);

    // Hidden seat indicator: dashed ring + small inner dot
    if (isHidden) {
      // Outer dashed ring (simulated with semi-transparent stroke)
      final hiddenRingPaint = Paint()
        ..color = const Color(0x99888894) // sage with alpha
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(Offset(cx, cy), radius + 1.5, hiddenRingPaint);

      // Small inner dark dot to indicate "locked/hidden"
      final innerDotPaint = Paint()
        ..color = const Color(0xCC1E1E24) // dark background color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), radius * 0.35, innerDotPaint);
    }

    // Selection ring
    if (isSelected) {
      final ringPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(cx, cy), radius + 2, ringPaint);
    }

    // Search highlight ring
    if (isHighlighted && !isSelected) {
      final highlightPaint = Paint()
        ..color = const Color(0xFFFFCF99)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, cy), radius + 1.5, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SeatDotMapPainter oldDelegate) {
    return oldDelegate.seatInfos != seatInfos ||
        oldDelegate.searchQuery != searchQuery ||
        oldDelegate.selectedSeatId != selectedSeatId ||
        oldDelegate.hiddenSeatIds != hiddenSeatIds;
  }

  @override
  bool? hitTest(Offset position) => true;
}

// =============================================================================
// GESTURE DETECTOR wrapper for dot map to handle seat clicks
// =============================================================================

/// Wrap the dot map in a GestureDetector-enabled widget for seat taps.
/// This is used in _buildDotMapCanvas via a StatefulWidget overlay.
class _DotMapInteractive extends StatelessWidget {
  final List<_SeatInfo> seatInfos;
  final String searchQuery;
  final String? selectedSeatId;
  final Set<String> hiddenSeatIds;
  final Color Function(SeatStatus) statusColorFn;
  final bool Function(_SeatInfo) isHighlightedFn;
  final void Function(_SeatInfo) onSeatTap;
  final Size canvasSize;

  const _DotMapInteractive({
    required this.seatInfos,
    required this.searchQuery,
    this.selectedSeatId,
    required this.hiddenSeatIds,
    required this.statusColorFn,
    required this.isHighlightedFn,
    required this.onSeatTap,
    required this.canvasSize,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final tapped = _hitTestSeat(details.localPosition);
        if (tapped != null) {
          onSeatTap(tapped);
        }
      },
      child: CustomPaint(
        size: canvasSize,
        painter: _SeatDotMapPainter(
          seatInfos: seatInfos,
          searchQuery: searchQuery,
          selectedSeatId: selectedSeatId,
          hiddenSeatIds: hiddenSeatIds,
          statusColorFn: statusColorFn,
          isHighlightedFn: isHighlightedFn,
        ),
      ),
    );
  }

  _SeatInfo? _hitTestSeat(Offset position) {
    final hasGrid = seatInfos
        .any((info) => info.seat.gridX != null && info.seat.gridY != null);

    if (hasGrid) {
      return _hitTestGrid(position);
    } else {
      return _hitTestAutoArrange(position);
    }
  }

  _SeatInfo? _hitTestGrid(Offset position) {
    int minX = 999999, maxX = -999999;
    int minY = 999999, maxY = -999999;

    for (final info in seatInfos) {
      final x = info.seat.gridX ?? 0;
      final y = info.seat.gridY ?? 0;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    final rangeX = (maxX - minX).clamp(1, 999999);
    final rangeY = (maxY - minY).clamp(1, 999999);

    const padding = 20.0;
    final drawW = canvasSize.width - padding * 2;
    final drawH = canvasSize.height - padding * 2;

    final cellW = drawW / (rangeX + 1);
    final cellH = drawH / (rangeY + 1);
    final hitRadius = (cellW < cellH ? cellW : cellH) * 0.5;

    for (final info in seatInfos) {
      final gx = info.seat.gridX ?? 0;
      final gy = info.seat.gridY ?? 0;

      final cx = padding + (gx - minX) * cellW + cellW / 2;
      final cy = padding + (gy - minY) * cellH + cellH / 2;

      if ((position - Offset(cx, cy)).distance <= hitRadius) {
        return info;
      }
    }
    return null;
  }

  _SeatInfo? _hitTestAutoArrange(Offset position) {
    final groups = <String, List<_SeatInfo>>{};
    for (final info in seatInfos) {
      final key =
          '${info.seat.block}|${info.seat.floor}|${info.seat.row ?? ''}';
      groups.putIfAbsent(key, () => []).add(info);
    }
    for (final group in groups.values) {
      group.sort((a, b) => a.seat.number.compareTo(b.seat.number));
    }
    final sortedKeys = groups.keys.toList()..sort();

    final maxSeatsInRow =
        groups.values.fold<int>(0, (max, g) => g.length > max ? g.length : max);
    final totalRows = sortedKeys.length;

    if (totalRows == 0 || maxSeatsInRow == 0) return null;

    const padding = 24.0;
    final drawW = canvasSize.width - padding * 2;
    final drawH = canvasSize.height - padding * 2;

    final cellW = drawW / maxSeatsInRow;
    final cellH = drawH / totalRows;
    final hitRadius = ((cellW < cellH ? cellW : cellH) * 0.5).clamp(4.0, 12.0);

    for (var rowIdx = 0; rowIdx < sortedKeys.length; rowIdx++) {
      final key = sortedKeys[rowIdx];
      final group = groups[key]!;
      final startX = padding + (drawW - group.length * cellW) / 2;

      for (var colIdx = 0; colIdx < group.length; colIdx++) {
        final info = group[colIdx];
        final cx = startX + colIdx * cellW + cellW / 2;
        final cy = padding + rowIdx * cellH + cellH / 2;

        if ((position - Offset(cx, cy)).distance <= hitRadius) {
          return info;
        }
      }
    }
    return null;
  }
}

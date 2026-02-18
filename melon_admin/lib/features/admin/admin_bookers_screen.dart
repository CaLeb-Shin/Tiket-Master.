import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/app_user.dart';
import 'package:melon_core/data/models/order.dart' as app;
import 'package:melon_core/data/models/ticket.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/order_repository.dart';
import 'package:melon_core/data/repositories/ticket_repository.dart';
import 'package:melon_core/services/firestore_service.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' if (dart.library.io) 'admin_bookers_stub.dart' as html;

// =============================================================================
// 예매자 목록 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

class AdminBookersScreen extends ConsumerStatefulWidget {
  final String eventId;
  const AdminBookersScreen({super.key, required this.eventId});

  @override
  ConsumerState<AdminBookersScreen> createState() => _AdminBookersScreenState();
}

class _AdminBookersScreenState extends ConsumerState<AdminBookersScreen> {
  // 캐시: userId → AppUser
  final Map<String, AppUser?> _userCache = {};
  // 캐시: orderId → List<Ticket>
  final Map<String, List<Ticket>> _ticketCache = {};

  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));
    final ordersAsync = ref.watch(
      StreamProvider<List<app.Order>>((ref) {
        return ref
            .watch(orderRepositoryProvider)
            .getOrdersByEvent(widget.eventId);
      }),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildAppBar(context, eventAsync),
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                final paidOrders =
                    orders.where((o) => o.status == app.OrderStatus.paid).toList();
                if (paidOrders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 36,
                            color: AppTheme.sage.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          '예매자가 없습니다',
                          style: AppTheme.sans(
                            fontSize: 14,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // 요약
                final totalTickets =
                    paidOrders.fold<int>(0, (s, o) => s + o.quantity);
                final totalRevenue =
                    paidOrders.fold<int>(0, (s, o) => s + o.totalAmount);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 요약 바
                    _SummaryBar(
                      orderCount: paidOrders.length,
                      ticketCount: totalTickets,
                      totalRevenue: totalRevenue,
                      isExporting: _isExporting,
                      onExport: () => _exportToExcel(paidOrders),
                    ),
                    // 목록
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: paidOrders.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 0.5,
                          color: AppTheme.sage.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (_, i) => _BookerCard(
                          order: paidOrders[i],
                          index: i + 1,
                          userCache: _userCache,
                          ticketCache: _ticketCache,
                          onUserLoaded: (uid, user) {
                            _userCache[uid] = user;
                          },
                          onTicketsLoaded: (orderId, tickets) {
                            _ticketCache[orderId] = tickets;
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
              error: (e, _) => Center(
                child: Text('오류: $e',
                    style: AppTheme.sans(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Editorial App Bar ──

  Widget _buildAppBar(BuildContext context, AsyncValue eventAsync) {
    final title = eventAsync.whenOrNull<String>(
          data: (event) => event?.title ?? '공연',
        ) ??
        '공연';

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
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.west,
                color: AppTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bookers',
                  style: AppTheme.serif(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Text(
                  title,
                  style: AppTheme.sans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Excel Export (business logic preserved) ──

  Future<void> _exportToExcel(List<app.Order> orders) async {
    setState(() => _isExporting = true);

    try {
      final firestore = ref.read(firestoreServiceProvider);
      final ticketRepo = ref.read(ticketRepositoryProvider);

      // 모든 유저 로드
      final userIds = orders.map((o) => o.userId).toSet();
      final userMap = <String, AppUser?>{};
      for (final uid in userIds) {
        if (_userCache.containsKey(uid)) {
          userMap[uid] = _userCache[uid];
        } else {
          final doc = await firestore.instance.collection('users').doc(uid).get();
          if (doc.exists) {
            userMap[uid] = AppUser.fromFirestore(doc);
          }
        }
      }

      // 모든 티켓 로드
      final ticketMap = <String, List<Ticket>>{};
      for (final order in orders) {
        if (_ticketCache.containsKey(order.id)) {
          ticketMap[order.id] = _ticketCache[order.id]!;
        } else {
          ticketMap[order.id] = await ticketRepo.getTicketsByOrder(order.id);
        }
      }

      // 좌석 정보 로드
      final allSeatIds = ticketMap.values
          .expand((tickets) => tickets.map((t) => t.seatId))
          .toSet();
      final seatInfoMap = <String, String>{};
      for (final seatId in allSeatIds) {
        final doc = await firestore.instance.collection('seats').doc(seatId).get();
        if (doc.exists) {
          final data = doc.data()!;
          final block = data['block'] ?? '';
          final floor = data['floor'] ?? '';
          final row = data['row'] ?? '';
          final number = data['number'] ?? '';
          final grade = data['grade'] ?? '';
          seatInfoMap[seatId] = '$grade $block구역 $floor층 $row열 $number번';
        }
      }

      // 엑셀 생성
      final excel = xl.Excel.createExcel();
      final sheet = excel['예매자 목록'];
      excel.delete('Sheet1');

      final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

      // 헤더
      sheet.appendRow([
        xl.TextCellValue('No'),
        xl.TextCellValue('주문번호'),
        xl.TextCellValue('예매자명'),
        xl.TextCellValue('이메일'),
        xl.TextCellValue('전화번호'),
        xl.TextCellValue('수량'),
        xl.TextCellValue('단가(원)'),
        xl.TextCellValue('총금액(원)'),
        xl.TextCellValue('결제일시'),
        xl.TextCellValue('좌석정보'),
        xl.TextCellValue('상태'),
      ]);

      // 데이터
      for (var i = 0; i < orders.length; i++) {
        final order = orders[i];
        final user = userMap[order.userId];
        final tickets = ticketMap[order.id] ?? [];
        final seatInfo = tickets
            .map((t) => seatInfoMap[t.seatId] ?? t.seatId)
            .join(', ');

        sheet.appendRow([
          xl.IntCellValue(i + 1),
          xl.TextCellValue(order.id),
          xl.TextCellValue(user?.displayName ?? '-'),
          xl.TextCellValue(user?.email ?? '-'),
          xl.TextCellValue(user?.phoneNumber ?? '-'),
          xl.IntCellValue(order.quantity),
          xl.IntCellValue(order.unitPrice),
          xl.IntCellValue(order.totalAmount),
          xl.TextCellValue(
              order.paidAt != null ? dateFormat.format(order.paidAt!) : '-'),
          xl.TextCellValue(seatInfo.isNotEmpty ? seatInfo : '-'),
          xl.TextCellValue(order.status.displayName),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('엑셀 인코딩 실패');

      if (kIsWeb) {
        _downloadFileWeb(bytes, '예매자목록.xlsx');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppTheme.onAccent),
                const SizedBox(width: 8),
                Text(
                  '엑셀 파일이 다운로드되었습니다 (${orders.length}건)',
                  style: AppTheme.sans(
                    fontSize: 13,
                    color: AppTheme.onAccent,
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.gold,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('내보내기 실패: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _downloadFileWeb(List<int> bytes, String fileName) {
    if (!kIsWeb) return;
    final base64 = base64Encode(bytes);
    html.AnchorElement(
      href:
          'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64',
    )
      ..setAttribute('download', fileName)
      ..click();
  }
}

// ─── Summary Bar (editorial) ───

class _SummaryBar extends StatelessWidget {
  final int orderCount;
  final int ticketCount;
  final int totalRevenue;
  final bool isExporting;
  final VoidCallback onExport;

  const _SummaryBar({
    required this.orderCount,
    required this.ticketCount,
    required this.totalRevenue,
    required this.isExporting,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final priceFormat = NumberFormat('#,###');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _SummaryChip(label: 'ORDERS', value: '$orderCount'),
          const SizedBox(width: 16),
          _SummaryChip(label: 'TICKETS', value: '$ticketCount'),
          const SizedBox(width: 16),
          _SummaryChip(
              label: 'REVENUE', value: priceFormat.format(totalRevenue)),
          const Spacer(),
          GestureDetector(
            onTap: isExporting ? null : onExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.sage.withValues(alpha: 0.2),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isExporting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppTheme.gold),
                    )
                  else
                    const Icon(Icons.download_rounded,
                        size: 14, color: AppTheme.gold),
                  const SizedBox(width: 8),
                  Text(
                    'EXPORT',
                    style: AppTheme.label(
                      fontSize: 9,
                      color: AppTheme.gold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.label(
            fontSize: 8,
            color: AppTheme.sage,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.serif(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Booker Card (editorial minimal) ───

class _BookerCard extends ConsumerStatefulWidget {
  final app.Order order;
  final int index;
  final Map<String, AppUser?> userCache;
  final Map<String, List<Ticket>> ticketCache;
  final void Function(String uid, AppUser? user) onUserLoaded;
  final void Function(String orderId, List<Ticket> tickets) onTicketsLoaded;

  const _BookerCard({
    required this.order,
    required this.index,
    required this.userCache,
    required this.ticketCache,
    required this.onUserLoaded,
    required this.onTicketsLoaded,
  });

  @override
  ConsumerState<_BookerCard> createState() => _BookerCardState();
}

class _BookerCardState extends ConsumerState<_BookerCard> {
  AppUser? _user;
  List<Ticket>? _tickets;
  bool _loadingUser = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // 유저 로드
    if (widget.userCache.containsKey(widget.order.userId)) {
      _user = widget.userCache[widget.order.userId];
    } else {
      setState(() => _loadingUser = true);
      try {
        final doc = await ref
            .read(firestoreServiceProvider)
            .instance
            .collection('users')
            .doc(widget.order.userId)
            .get();
        if (doc.exists) {
          _user = AppUser.fromFirestore(doc);
          widget.onUserLoaded(widget.order.userId, _user);
        }
      } catch (_) {}
      if (mounted) setState(() => _loadingUser = false);
    }

    // 티켓 로드
    if (widget.ticketCache.containsKey(widget.order.id)) {
      _tickets = widget.ticketCache[widget.order.id];
    } else {
      try {
        _tickets = await ref
            .read(ticketRepositoryProvider)
            .getTicketsByOrder(widget.order.id);
        widget.onTicketsLoaded(widget.order.id, _tickets!);
      } catch (_) {}
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final priceFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('MM.dd HH:mm');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 번호 + 이름 + 날짜
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Index number
              Text(
                '${widget.index}'.padLeft(2, '0'),
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.sage,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loadingUser)
                      Container(
                        height: 14,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.sage.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    else
                      Text(
                        _user?.displayName ?? '사용자',
                        style: AppTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    if (_user?.email != null)
                      Text(
                        _user!.email,
                        style: AppTheme.sans(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                order.paidAt != null ? dateFormat.format(order.paidAt!) : '-',
                style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 하단: 수량·금액·좌석
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoTag(
                  icon: Icons.confirmation_number_rounded,
                  text: '${order.quantity}매',
                ),
                _InfoTag(
                  icon: Icons.payments_rounded,
                  text: '${priceFormat.format(order.totalAmount)}원',
                ),
                if (_user?.phoneNumber != null && _user!.phoneNumber!.isNotEmpty)
                  _InfoTag(
                    icon: Icons.phone_rounded,
                    text: _user!.phoneNumber!,
                  ),
                if (_tickets != null && _tickets!.isNotEmpty)
                  ..._tickets!.map((t) => _InfoTag(
                        icon: Icons.event_seat_rounded,
                        text: t.seatId.length > 20
                            ? '${t.seatId.substring(0, 20)}...'
                            : t.seatId,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppTheme.sage.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.sage),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

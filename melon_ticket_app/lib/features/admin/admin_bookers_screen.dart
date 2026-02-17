import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../data/models/app_user.dart';
import '../../data/models/order.dart' as app;
import '../../data/models/ticket.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../services/firestore_service.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' if (dart.library.io) 'admin_bookers_stub.dart' as html;

/// 공연별 예매자 목록 + 엑셀 내보내기
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
                            size: 48,
                            color: AppTheme.textTertiary.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          '예매자가 없습니다',
                          style: GoogleFonts.notoSans(
                            fontSize: 15,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: paidOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                    style: GoogleFonts.notoSans(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textPrimary, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '예매자 목록',
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.notoSans(
                    fontSize: 12,
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
          seatInfoMap[seatId] = '$grade ${block}구역 ${floor}층 ${row}열 $number번';
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
                    size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text('엑셀 파일이 다운로드되었습니다 (${orders.length}건)'),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

// ─── 요약 바 ───
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _SummaryChip(label: '주문', value: '$orderCount건'),
          const SizedBox(width: 10),
          _SummaryChip(label: '티켓', value: '$ticketCount매'),
          const SizedBox(width: 10),
          _SummaryChip(
              label: '매출', value: '${priceFormat.format(totalRevenue)}원'),
          const Spacer(),
          GestureDetector(
            onTap: isExporting ? null : onExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.gold.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isExporting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.gold),
                    )
                  else
                    const Icon(Icons.download_rounded,
                        size: 16, color: AppTheme.gold),
                  const SizedBox(width: 6),
                  Text(
                    '엑셀 다운로드',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.goldSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: GoogleFonts.notoSans(
                fontSize: 11, color: AppTheme.textTertiary),
          ),
          Text(
            value,
            style: GoogleFonts.notoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 예매자 카드 ───
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 번호 + 이름 + 날짜
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    '${widget.index}',
                    style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loadingUser)
                      Container(
                        height: 14,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )
                    else
                      Text(
                        _user?.displayName ?? '사용자',
                        style: GoogleFonts.notoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    if (_user?.email != null)
                      Text(
                        _user!.email,
                        style: GoogleFonts.notoSans(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                order.paidAt != null ? dateFormat.format(order.paidAt!) : '-',
                style: GoogleFonts.notoSans(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 하단: 수량·금액·좌석
          Wrap(
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
                          ? '${t.seatId.substring(0, 20)}…'
                          : t.seatId,
                    )),
            ],
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
        color: AppTheme.goldSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.notoSans(
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

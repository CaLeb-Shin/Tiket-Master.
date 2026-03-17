import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/repositories/naver_order_repository.dart';
import 'package:melon_core/data/repositories/mobile_ticket_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/naver_order.dart';
import 'package:melon_core/data/models/mobile_ticket.dart';
import 'package:melon_core/infrastructure/firebase/functions_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// =============================================================================
// 네이버 주문 관리 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

const _ticketBaseUrl = 'https://melonticket-web-20260216.vercel.app/m/';

// SMS 발송 상태 스트림 (orderId 기준)
final _smsStatusProvider = StreamProvider.family<String?, String>((
  ref,
  orderId,
) {
  return FirebaseFirestore.instance
      .collection('smsTasks')
      .where('naverOrderId', isEqualTo: orderId)
      .limit(1)
      .snapshots()
      .map(
        (snap) => snap.docs.isEmpty
            ? null
            : snap.docs.first.data()['status'] as String?,
      );
});

final _smsTasksByEventProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) {
      return FirebaseFirestore.instance
          .collection('smsTasks')
          .where('eventId', isEqualTo: eventId)
          .snapshots()
          .map((snap) {
            return snap.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return data;
            }).toList();
          });
    });

const _gradeOrder = ['VIP', 'R', 'S', 'A'];

class NaverOrderScreen extends ConsumerStatefulWidget {
  final String eventId;
  const NaverOrderScreen({super.key, required this.eventId});

  @override
  ConsumerState<NaverOrderScreen> createState() => _NaverOrderScreenState();
}

enum _Filter { all, confirmed, cancelled }

class _NaverOrderScreenState extends ConsumerState<NaverOrderScreen> {
  _Filter _filter = _Filter.all;
  String _searchQuery = '';
  String? _expandedOrderId;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(naverOrdersStreamProvider(widget.eventId));
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          // ── Editorial App Bar ──
          Container(
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
                      child: eventAsync.when(
                        data: (event) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Naver Orders',
                              style: AdminTheme.serif(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (event != null)
                              Text(
                                event.title,
                                style: AdminTheme.sans(
                                  fontSize: 11,
                                  color: AdminTheme.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        loading: () => Text(
                          'Naver Orders',
                          style: AdminTheme.serif(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        error: (_, __) => Text(
                          'Naver Orders',
                          style: AdminTheme.serif(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                      // 좌석 공개
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          onPressed: () => _revealSeatsNow(),
                          icon: const Icon(Icons.visibility_rounded, size: 14),
                          label: Text(
                            '좌석 공개',
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
                      // 테스트 주문
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          onPressed: () => _showTestOrderDialog(),
                          icon: const Icon(Icons.science_rounded, size: 14),
                          label: Text(
                            '테스트',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminTheme.sage,
                            side: BorderSide(
                              color: AdminTheme.sage.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      // 주문 입력
                      SizedBox(
                        height: 32,
                        child: ElevatedButton.icon(
                          onPressed: () => _showCreateOrderDialog(),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(
                            '주문 입력',
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
          ),

          // ── Content ──
          Expanded(
            child: ordersAsync.when(
              data: (orders) => _buildContent(orders),
              loading: () => const Center(
                child: CircularProgressIndicator(color: AdminTheme.gold),
              ),
              error: (e, _) => Center(
                child: Text(
                  '오류: $e',
                  style: AdminTheme.sans(color: AdminTheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<NaverOrder> orders) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 36,
              color: AdminTheme.sage.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '네이버 주문이 없습니다',
              style: AdminTheme.sans(
                fontSize: 14,
                color: AdminTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\'주문 입력\' 버튼으로 첫 주문을 추가하세요',
              style: AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    final confirmed = orders.where(
      (o) => o.status == NaverOrderStatus.confirmed,
    );
    final cancelled = orders.where(
      (o) => o.status == NaverOrderStatus.cancelled,
    );
    final totalTickets = confirmed.fold<int>(
      0,
      (sum, o) => sum + o.ticketIds.length,
    );

    // Filter
    List<NaverOrder> filtered;
    switch (_filter) {
      case _Filter.all:
        filtered = orders;
      case _Filter.confirmed:
        filtered = confirmed.toList();
      case _Filter.cancelled:
        filtered = cancelled.toList();
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (o) =>
                o.buyerName.toLowerCase().contains(q) ||
                o.buyerPhone.contains(q) ||
                o.naverOrderId.toLowerCase().contains(q),
          )
          .toList();
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
                label: 'CONFIRMED',
                value: '${confirmed.length}',
                color: AdminTheme.success,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'CANCELLED',
                value: '${cancelled.length}',
                color: AdminTheme.error,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'TICKETS',
                value: '$totalTickets',
                color: AdminTheme.gold,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'TOTAL',
                value: '${orders.length}',
                color: AdminTheme.textPrimary,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _OperationsOverview(eventId: widget.eventId),

        const SizedBox(height: 28),

        // ── Filter + Search ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              // Filter tabs
              ..._Filter.values.map((f) {
                final selected = f == _filter;
                final label = switch (f) {
                  _Filter.all => 'ALL',
                  _Filter.confirmed => 'CONFIRMED',
                  _Filter.cancelled => 'CANCELLED',
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
                        color: selected ? AdminTheme.gold : Colors.transparent,
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
              const Spacer(),
              // Search
              SizedBox(
                width: 240,
                height: 36,
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '이름 / 전화번호 / 주문번호',
                    hintStyle: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.textTertiary,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 16,
                      color: AdminTheme.textTertiary,
                    ),
                    filled: true,
                    fillColor: AdminTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: AdminTheme.border,
                        width: 0.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: AdminTheme.border,
                        width: 0.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                        color: AdminTheme.gold.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
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
                'Orders',
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

        // ── Order List ──
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
              final order = filtered[i];
              final isExpanded = _expandedOrderId == order.id;
              return _NaverOrderRow(
                order: order,
                isExpanded: isExpanded,
                onToggleExpand: () {
                  setState(() {
                    _expandedOrderId = isExpanded ? null : order.id;
                  });
                },
                onCancel: () => _cancelOrder(order),
              );
            },
          ),
      ],
      ),
    );
  }

  // ─── Create Order Dialog ───

  void _showCreateOrderDialog() {
    final naverOrderIdCtrl = TextEditingController();
    final buyerNameCtrl = TextEditingController();
    final buyerPhoneCtrl = TextEditingController();
    final productNameCtrl = TextEditingController();
    final memoCtrl = TextEditingController();
    final companionCtrl = TextEditingController();
    String selectedGrade = 'VIP';
    int quantity = 1;
    DateTime orderDate = DateTime.now();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dateFormat = DateFormat('yyyy-MM-dd');

          return Dialog(
            backgroundColor: AdminTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '네이버 주문 입력',
                      style: AdminTheme.serif(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 네이버 주문번호
                    _DialogField(
                      label: '네이버 주문번호',
                      child: _buildTextField(naverOrderIdCtrl, '주문번호 입력'),
                    ),
                    const SizedBox(height: 14),

                    // 구매자 정보
                    Row(
                      children: [
                        Expanded(
                          child: _DialogField(
                            label: '구매자명',
                            child: _buildTextField(buyerNameCtrl, '이름'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogField(
                            label: '연락처',
                            child: _buildTextField(
                              buyerPhoneCtrl,
                              '010-0000-0000',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 상품명
                    _DialogField(
                      label: '상품명',
                      child: _buildTextField(productNameCtrl, '공연명 + 등급'),
                    ),
                    const SizedBox(height: 14),

                    // 등급 + 수량
                    Row(
                      children: [
                        Expanded(
                          child: _DialogField(
                            label: '좌석 등급',
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AdminTheme.card,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AdminTheme.border,
                                  width: 0.5,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedGrade,
                                  isExpanded: true,
                                  dropdownColor: AdminTheme.card,
                                  style: AdminTheme.sans(
                                    fontSize: 13,
                                    color: AdminTheme.textPrimary,
                                  ),
                                  items: _gradeOrder
                                      .map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(g),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setDialogState(() => selectedGrade = v);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogField(
                            label: '수량',
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: AdminTheme.card,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AdminTheme.border,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: quantity > 1
                                        ? () => setDialogState(() => quantity--)
                                        : null,
                                    icon: const Icon(Icons.remove, size: 16),
                                    color: AdminTheme.textSecondary,
                                  ),
                                  Expanded(
                                    child: Text(
                                      '$quantity',
                                      textAlign: TextAlign.center,
                                      style: AdminTheme.sans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AdminTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        setDialogState(() => quantity++),
                                    icon: const Icon(Icons.add, size: 16),
                                    color: AdminTheme.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 주문일 + 메모
                    Row(
                      children: [
                        Expanded(
                          child: _DialogField(
                            label: '주문일',
                            child: GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: orderDate,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() => orderDate = picked);
                                }
                              },
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AdminTheme.card,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AdminTheme.border,
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today_rounded,
                                      size: 14,
                                      color: AdminTheme.textTertiary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateFormat.format(orderDate),
                                      style: AdminTheme.sans(
                                        fontSize: 13,
                                        color: AdminTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogField(
                            label: '메모 (선택)',
                            child: _buildTextField(memoCtrl, '메모'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 함께 볼 친구 (연석 요청)
                    _DialogField(
                      label: '함께 볼 친구 (선택)',
                      child: _buildTextField(companionCtrl, '이름 또는 전화번호 뒷4자리'),
                    ),
                    const SizedBox(height: 28),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: isLoading
                                  ? null
                                  : () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AdminTheme.textPrimary,
                                side: const BorderSide(
                                  color: AdminTheme.border,
                                  width: 0.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                '취소',
                                style: AdminTheme.sans(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: isLoading
                                  ? null
                                  : () async {
                                      if (naverOrderIdCtrl.text
                                              .trim()
                                              .isEmpty ||
                                          buyerNameCtrl.text.trim().isEmpty ||
                                          buyerPhoneCtrl.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          const SnackBar(
                                            content: Text('필수 필드를 입력해주세요'),
                                          ),
                                        );
                                        return;
                                      }
                                      setDialogState(() => isLoading = true);
                                      try {
                                        final result = await ref
                                            .read(functionsServiceProvider)
                                            .createNaverOrder(
                                              eventId: widget.eventId,
                                              naverOrderId: naverOrderIdCtrl
                                                  .text
                                                  .trim(),
                                              buyerName: buyerNameCtrl.text
                                                  .trim(),
                                              buyerPhone: buyerPhoneCtrl.text
                                                  .trim(),
                                              productName:
                                                  productNameCtrl.text
                                                      .trim()
                                                      .isEmpty
                                                  ? '$selectedGrade석'
                                                  : productNameCtrl.text.trim(),
                                              seatGrade: selectedGrade,
                                              quantity: quantity,
                                              orderDate: dateFormat.format(
                                                orderDate,
                                              ),
                                              memo: memoCtrl.text.trim().isEmpty
                                                  ? null
                                                  : memoCtrl.text.trim(),
                                              companion: companionCtrl.text.trim().isEmpty
                                                  ? null
                                                  : companionCtrl.text.trim(),
                                            );
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          _showTicketUrlsDialog(result);
                                        }
                                      } catch (e) {
                                        setDialogState(() => isLoading = false);
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(
                                            ctx,
                                          ).showSnackBar(
                                            SnackBar(content: Text('오류: $e')),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AdminTheme.gold,
                                foregroundColor: AdminTheme.onAccent,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AdminTheme.onAccent,
                                      ),
                                    )
                                  : Text(
                                      '주문 생성',
                                      style: AdminTheme.sans(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Ticket URLs Dialog (after creation) ───

  void _showTicketUrlsDialog(Map<String, dynamic> result) {
    final ticketUrls = List<String>.from(result['ticketUrls'] ?? []);
    if (ticketUrls.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AdminTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AdminTheme.success,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  '주문 생성 완료',
                  style: AdminTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${ticketUrls.length}장의 티켓이 발급되었습니다',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                ...ticketUrls.asMap().entries.map((entry) {
                  final url = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('티켓 ${entry.key + 1} URL 복사됨'),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AdminTheme.card,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AdminTheme.border,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AdminTheme.gold.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '${entry.key + 1}',
                                  style: AdminTheme.sans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AdminTheme.gold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                url,
                                style: AdminTheme.sans(
                                  fontSize: 11,
                                  color: AdminTheme.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: AdminTheme.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () {
                      final allUrls = ticketUrls.join('\n');
                      Clipboard.setData(ClipboardData(text: allUrls));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('전체 URL 복사됨')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(
                      '전체 URL 복사',
                      style: AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    '닫기',
                    style: AdminTheme.sans(
                      color: AdminTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 테스트 주문 일괄 생성 ───

  void _showTestOrderDialog() {
    String selectedGrade = 'R';
    int quantity = 10;
    int ticketsPerOrder = 1;
    bool isCreating = false;
    final results = <String>[];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AdminTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.science_rounded,
                        color: AdminTheme.sage,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '테스트 주문 생성',
                        style: AdminTheme.serif(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '가상 주문을 일괄 생성합니다 (좌석 자동 배정)',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 등급 선택
                  Text('등급', style: AdminTheme.label(fontSize: 10)),
                  const SizedBox(height: 6),
                  Row(
                    children: _gradeOrder.map((g) {
                      final selected = g == selectedGrade;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '${g}석',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AdminTheme.onAccent
                                  : AdminTheme.textSecondary,
                            ),
                          ),
                          selected: selected,
                          selectedColor: AdminTheme.gold,
                          backgroundColor: AdminTheme.card,
                          side: BorderSide(
                            color: selected
                                ? AdminTheme.gold
                                : AdminTheme.border,
                            width: 0.5,
                          ),
                          onSelected: (_) =>
                              setDialogState(() => selectedGrade = g),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 수량
                  Text('주문 수', style: AdminTheme.label(fontSize: 10)),
                  const SizedBox(height: 6),
                  Row(
                    children: [3, 5, 10].map((n) {
                      final selected = n == quantity;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '$n명',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AdminTheme.onAccent
                                  : AdminTheme.textSecondary,
                            ),
                          ),
                          selected: selected,
                          selectedColor: AdminTheme.gold,
                          backgroundColor: AdminTheme.card,
                          side: BorderSide(
                            color: selected
                                ? AdminTheme.gold
                                : AdminTheme.border,
                            width: 0.5,
                          ),
                          onSelected: (_) => setDialogState(() => quantity = n),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 주문당 매수 (그룹티켓 테스트용)
                  Text('주문당 매수', style: AdminTheme.label(fontSize: 10)),
                  const SizedBox(height: 6),
                  Row(
                    children: [1, 2, 3, 5].map((n) {
                      final selected = n == ticketsPerOrder;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '$n매',
                            style: AdminTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AdminTheme.onAccent
                                  : AdminTheme.textSecondary,
                            ),
                          ),
                          selected: selected,
                          selectedColor: AdminTheme.gold,
                          backgroundColor: AdminTheme.card,
                          side: BorderSide(
                            color: selected
                                ? AdminTheme.gold
                                : AdminTheme.border,
                            width: 0.5,
                          ),
                          onSelected: (_) =>
                              setDialogState(() => ticketsPerOrder = n),
                        ),
                      );
                    }).toList(),
                  ),
                  if (ticketsPerOrder > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '→ 그룹티켓 테스트 (주문당 ${ticketsPerOrder}매 → 스와이프)',
                        style: AdminTheme.sans(
                          fontSize: 11,
                          color: AdminTheme.sage,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // 결과 표시
                  if (results.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminTheme.card,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AdminTheme.border,
                          width: 0.5,
                        ),
                      ),
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Text(
                          results.join('\n'),
                          style: AdminTheme.sans(
                            fontSize: 11,
                            color: AdminTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 버튼
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AdminTheme.textPrimary,
                              side: const BorderSide(
                                color: AdminTheme.border,
                                width: 0.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: Text(
                              '닫기',
                              style: AdminTheme.sans(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: isCreating
                                ? null
                                : () async {
                                    setDialogState(() {
                                      isCreating = true;
                                      results.clear();
                                    });

                                    for (int i = 1; i <= quantity; i++) {
                                      try {
                                        final res = await ref
                                            .read(functionsServiceProvider)
                                            .createNaverOrder(
                                              eventId: widget.eventId,
                                              naverOrderId:
                                                  'TEST-${DateTime.now().millisecondsSinceEpoch}-$i',
                                              buyerName: '테스트관객$i',
                                              buyerPhone:
                                                  '010-0000-${i.toString().padLeft(4, '0')}',
                                              productName: '테스트 주문',
                                              seatGrade: selectedGrade,
                                              quantity: ticketsPerOrder,
                                              orderDate: DateTime.now()
                                                  .toIso8601String(),
                                            );
                                        final tickets =
                                            (res['tickets'] as List?) ?? [];
                                        final url = tickets.isNotEmpty
                                            ? tickets[0]['url'] ?? ''
                                            : '';
                                        setDialogState(
                                          () => results.add(
                                            '✅ 테스트관객$i — $selectedGrade석 $url',
                                          ),
                                        );
                                      } catch (e) {
                                        setDialogState(
                                          () => results.add('❌ 테스트관객$i — $e'),
                                        );
                                      }
                                    }

                                    setDialogState(() => isCreating = false);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminTheme.sage,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: isCreating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    '$quantity건 생성',
                                    style: AdminTheme.sans(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── 좌석 즉시 공개 ───

  Future<void> _revealSeatsNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AdminTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  color: AdminTheme.info,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  '좌석 즉시 공개',
                  style: AdminTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '모든 티켓의 좌석과 QR 공개 시점을 지금으로 앞당깁니다.\n'
                  '(revealAt을 현재 시각으로 설정)',
                  textAlign: TextAlign.center,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminTheme.textPrimary,
                            side: const BorderSide(
                              color: AdminTheme.border,
                              width: 0.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            '취소',
                            style: AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminTheme.info,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            '공개 확정',
                            style: AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(functionsServiceProvider)
          .revealSeatsNow(eventId: widget.eventId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('좌석이 공개되었습니다')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('공개 실패: $e')));
      }
    }
  }

  // ─── Cancel Order ───

  Future<void> _cancelOrder(NaverOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AdminTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AdminTheme.error,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  '주문 취소',
                  style: AdminTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${order.buyerName} (${order.naverOrderId})\n'
                  '${order.seatGrade}석 ${order.quantity}매를 취소합니다.\n'
                  '좌석이 해제되고 입장번호가 재배정됩니다.',
                  textAlign: TextAlign.center,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminTheme.textPrimary,
                            side: const BorderSide(
                              color: AdminTheme.border,
                              width: 0.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            '아니오',
                            style: AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminTheme.error.withValues(
                              alpha: 0.15,
                            ),
                            foregroundColor: AdminTheme.error,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            '취소 확정',
                            style: AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(functionsServiceProvider)
          .cancelNaverOrder(orderId: order.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('주문이 취소되었습니다')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('취소 실패: $e')));
      }
    }
  }

  Widget _buildTextField(TextEditingController ctrl, String hint) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: ctrl,
        style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AdminTheme.sans(
            fontSize: 12,
            color: AdminTheme.textTertiary,
          ),
          filled: true,
          fillColor: AdminTheme.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: AdminTheme.gold.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Dialog Field Label ───

class _DialogField extends StatelessWidget {
  final String label;
  final Widget child;
  const _DialogField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AdminTheme.label(fontSize: 9, color: AdminTheme.sage),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ─── Summary Card ───

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

// ─── 운영 개요 ───

class _OperationsOverview extends ConsumerWidget {
  final String eventId;

  const _OperationsOverview({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(eventId));
    final ticketsAsync = ref.watch(mobileTicketsStreamProvider(eventId));
    final smsTasksAsync = ref.watch(_smsTasksByEventProvider(eventId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: eventAsync.when(
        loading: () => const _OperationsOverviewLoading(),
        error: (error, _) => _OperationsOverviewError(message: '$error'),
        data: (event) => ticketsAsync.when(
          loading: () => const _OperationsOverviewLoading(),
          error: (error, _) => _OperationsOverviewError(message: '$error'),
          data: (tickets) => smsTasksAsync.when(
            loading: () => const _OperationsOverviewLoading(),
            error: (error, _) => _OperationsOverviewError(message: '$error'),
            data: (smsTasks) => _OperationsOverviewContent(
              event: event,
              tickets: tickets,
              smsTasks: smsTasks,
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationsOverviewLoading extends StatelessWidget {
  const _OperationsOverviewLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AdminTheme.gold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationsOverviewError extends StatelessWidget {
  final String message;

  const _OperationsOverviewError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AdminTheme.error.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Text(
        '운영 개요를 불러오지 못했습니다: $message',
        style: AdminTheme.sans(fontSize: 12, color: AdminTheme.error),
      ),
    );
  }
}

class _OperationsOverviewContent extends StatelessWidget {
  final Event? event;
  final List<MobileTicket> tickets;
  final List<Map<String, dynamic>> smsTasks;

  const _OperationsOverviewContent({
    required this.event,
    required this.tickets,
    required this.smsTasks,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final revealAt = event?.revealAt;
    final isRevealed = revealAt != null && !now.isBefore(revealAt);
    final revealedText = revealAt == null
        ? '공개 시각 없음'
        : DateFormat('MM.dd (E) HH:mm', 'ko_KR').format(revealAt);
    final revealDetail = revealAt == null
        ? '공연 정보에서 revealAt 설정을 확인하세요'
        : isRevealed
        ? '현재 즉시 QR과 좌석이 노출됩니다'
        : '${_formatDuration(revealAt.difference(now))} 뒤 자동 공개';

    final availableCount = tickets
        .where(
          (ticket) =>
              ticket.status == MobileTicketStatus.active && !ticket.isCheckedIn,
        )
        .length;
    final checkedInCount = tickets
        .where(
          (ticket) =>
              ticket.status == MobileTicketStatus.active && ticket.isCheckedIn,
        )
        .length;
    final usedCount = tickets
        .where((ticket) => ticket.status == MobileTicketStatus.used)
        .length;
    final cancelledCount = tickets
        .where((ticket) => ticket.status == MobileTicketStatus.cancelled)
        .length;
    final deliveredCount = tickets
        .where((ticket) => (ticket.recipientName ?? '').trim().isNotEmpty)
        .length;
    final deliveryDetail = tickets.isEmpty
        ? '발급된 티켓 없음'
        : '미전달 ${tickets.length - deliveredCount}매';

    final pendingSms = smsTasks
        .where((task) => (task['status'] as String?) == 'pending')
        .length;
    final sentSms = smsTasks
        .where((task) => (task['status'] as String?) == 'sent')
        .length;
    final failedSms = smsTasks
        .where((task) => (task['status'] as String?) == 'failed')
        .length;
    final smsDetail = smsTasks.isEmpty
        ? '문자 작업 없음'
        : '실패 $failedSms건, 대기 $pendingSms건';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AdminTheme.sage.withValues(alpha: 0.12),
          width: 0.5,
        ),
        boxShadow: AdminShadows.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('OPERATIONS', style: AdminTheme.label(fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 0.5,
                  color: AdminTheme.sage.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _OpsMetricCard(
                label: '공개 상태',
                value: isRevealed ? '공개됨' : '공개 전',
                detail: '$revealedText · $revealDetail',
                color: isRevealed ? AdminTheme.success : AdminTheme.gold,
              ),
              _OpsMetricCard(
                label: '티켓 상태',
                value:
                    '사용 가능 $availableCount · 입장 $checkedInCount · 완료 $usedCount · 취소 $cancelledCount',
                detail: tickets.isEmpty
                    ? '아직 티켓이 없습니다'
                    : '총 ${tickets.length}매 발급',
                color: AdminTheme.info,
              ),
              _OpsMetricCard(
                label: '전달 현황',
                value: '전달 $deliveredCount / ${tickets.length}',
                detail: deliveryDetail,
                color: deliveredCount == tickets.length && tickets.isNotEmpty
                    ? AdminTheme.success
                    : AdminTheme.sage,
              ),
              _OpsMetricCard(
                label: '문자 현황',
                value: '발송 $sentSms · 대기 $pendingSms · 실패 $failedSms',
                detail: smsDetail,
                color: failedSms > 0
                    ? AdminTheme.error
                    : pendingSms > 0
                    ? AdminTheme.gold
                    : AdminTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AdminTheme.sage.withValues(alpha: 0.14),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '운영 메모',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '상단 좌석 공개 버튼은 revealAt을 즉시 앞당깁니다. 주문 확장에서 좌석 재배정을 할 수 있고, 전달 상태는 받는 사람 이름 입력 여부로 추적합니다. SMS 실패 건은 주문 상세와 progress 기록에서 함께 확인하세요.',
                  style: AdminTheme.sans(
                    fontSize: 11,
                    color: AdminTheme.textSecondary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpsMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final Color color;

  const _OpsMetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminTheme.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.16), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AdminTheme.label(fontSize: 9, color: color)),
            const SizedBox(height: 8),
            Text(
              value,
              style: AdminTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: AdminTheme.sans(
                fontSize: 10,
                color: AdminTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  if (duration.isNegative) {
    return '0분';
  }

  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  if (hours <= 0) {
    return '$minutes분';
  }
  if (minutes == 0) {
    return '$hours시간';
  }
  return '$hours시간 ${minutes}분';
}

class _ExpandedTicketSummary extends ConsumerWidget {
  final List<MobileTicket> tickets;
  final String orderId;

  const _ExpandedTicketSummary({required this.tickets, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smsAsync = ref.watch(_smsStatusProvider(orderId));
    final deliveredCount = tickets
        .where((ticket) => (ticket.recipientName ?? '').trim().isNotEmpty)
        .length;
    final checkedInCount = tickets
        .where(
          (ticket) =>
              ticket.status == MobileTicketStatus.active && ticket.isCheckedIn,
        )
        .length;
    final completedCount = tickets
        .where((ticket) => ticket.status == MobileTicketStatus.used)
        .length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SummaryChip(
          label: '전달 $deliveredCount/${tickets.length}',
          color: deliveredCount == tickets.length && tickets.isNotEmpty
              ? AdminTheme.success
              : AdminTheme.sage,
        ),
        if (checkedInCount > 0)
          _SummaryChip(label: '입장 $checkedInCount', color: AdminTheme.info),
        if (completedCount > 0)
          _SummaryChip(label: '완료 $completedCount', color: AdminTheme.gold),
        smsAsync.when(
          data: (status) {
            if (status == null) {
              return const SizedBox.shrink();
            }
            return _SummaryChip(
              label: switch (status) {
                'sent' => '문자 발송',
                'pending' => '문자 대기',
                'failed' => '문자 실패',
                _ => '문자 $status',
              },
              color: switch (status) {
                'sent' => AdminTheme.success,
                'pending' => AdminTheme.gold,
                'failed' => AdminTheme.error,
                _ => AdminTheme.textTertiary,
              },
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Text(label, style: AdminTheme.label(fontSize: 8, color: color)),
    );
  }
}

// ─── Naver Order Row (expandable with tickets) ───

class _NaverOrderRow extends ConsumerWidget {
  final NaverOrder order;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCancel;

  const _NaverOrderRow({
    required this.order,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MM.dd HH:mm');
    final ticketsAsync = ref.watch(mobileTicketsByOrderProvider(order.id));

    Color statusColor;
    String statusLabel;
    switch (order.status) {
      case NaverOrderStatus.confirmed:
        statusColor = AdminTheme.success;
        statusLabel = 'CONFIRMED';
      case NaverOrderStatus.cancelled:
        statusColor = AdminTheme.error;
        statusLabel = 'CANCELLED';
      case NaverOrderStatus.refunded:
        statusColor = AdminTheme.textTertiary;
        statusLabel = 'REFUNDED';
    }

    Color gradeColor;
    switch (order.seatGrade) {
      case 'VIP':
        gradeColor = AdminTheme.gold;
      case 'R':
        gradeColor = AdminTheme.info;
      case 'S':
        gradeColor = AdminTheme.success;
      default:
        gradeColor = AdminTheme.textSecondary;
    }

    return Column(
      children: [
        // Main row
        GestureDetector(
          onTap: onToggleExpand,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 2,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 14),

                // Order info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            order.buyerName,
                            style: AdminTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AdminTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Grade badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: gradeColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: gradeColor.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              order.seatGrade,
                              style: AdminTheme.label(
                                fontSize: 8,
                                color: gradeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${order.quantity}매',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              color: AdminTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${order.naverOrderId}  ·  ${dateFormat.format(order.createdAt)}',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              color: AdminTheme.textTertiary,
                            ),
                          ),
                          if (order.status == NaverOrderStatus.cancelled && order.cancelledAt != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AdminTheme.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                '취소 ${dateFormat.format(order.cancelledAt!)}',
                                style: AdminTheme.label(
                                  fontSize: 8,
                                  color: AdminTheme.error,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          ticketsAsync.when(
                            data: (tickets) {
                              final deliveredCount = tickets
                                  .where(
                                    (ticket) => (ticket.recipientName ?? '')
                                        .trim()
                                        .isNotEmpty,
                                  )
                                  .length;
                              if (tickets.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AdminTheme.sage.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(
                                    color: AdminTheme.sage.withValues(
                                      alpha: 0.18,
                                    ),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  '전달 $deliveredCount/${tickets.length}',
                                  style: AdminTheme.label(
                                    fontSize: 8,
                                    color: AdminTheme.sage,
                                  ),
                                ),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (order.userId?.isNotEmpty == true
                                          ? AdminTheme.info
                                          : AdminTheme.textTertiary)
                                      .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color:
                                    (order.userId?.isNotEmpty == true
                                            ? AdminTheme.info
                                            : AdminTheme.textTertiary)
                                        .withValues(alpha: 0.18),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              order.userId?.isNotEmpty == true
                                  ? '앱 연결됨'
                                  : '앱 미연결',
                              style: AdminTheme.label(
                                fontSize: 8,
                                color: order.userId?.isNotEmpty == true
                                    ? AdminTheme.info
                                    : AdminTheme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status + actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status label
                    // SMS status badge
                    _SmsBadge(orderId: order.id),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: AdminTheme.label(
                          fontSize: 9,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (order.status == NaverOrderStatus.confirmed) ...[
                      const SizedBox(width: 8),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onCancel,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AdminTheme.error.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: AdminTheme.error.withValues(alpha: 0.15),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              '취소',
                              style: AdminTheme.label(
                                fontSize: 9,
                                color: AdminTheme.error,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AdminTheme.textTertiary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Expanded tickets section
        if (isExpanded)
          _ExpandedTickets(orderId: order.id, orderStatus: order.status),
      ],
    );
  }
}

// ─── Expanded Tickets Section ───

class _ExpandedTickets extends ConsumerWidget {
  final String orderId;
  final NaverOrderStatus orderStatus;
  const _ExpandedTickets({required this.orderId, required this.orderStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(mobileTicketsByOrderProvider(orderId));

    return ticketsAsync.when(
      data: (tickets) {
        if (tickets.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12),
            child: Text(
              '티켓 없음',
              style: AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.textTertiary,
              ),
            ),
          );
        }

        // Sort by entryNumber
        tickets.sort((a, b) => a.entryNumber.compareTo(b.entryNumber));

        return Container(
          margin: const EdgeInsets.only(left: 16, bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AdminTheme.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'TICKETS',
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: AdminTheme.sage,
                    ),
                  ),
                  const Spacer(),
                  _ExpandedTicketSummary(tickets: tickets, orderId: orderId),
                ],
              ),
              const SizedBox(height: 8),
              ...tickets.map((ticket) => _TicketRow(ticket: ticket)),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AdminTheme.gold,
            ),
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '오류: $e',
          style: AdminTheme.sans(fontSize: 11, color: AdminTheme.error),
        ),
      ),
    );
  }
}

// ─── Single Ticket Row ───

class _TicketRow extends StatelessWidget {
  final MobileTicket ticket;
  const _TicketRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch ((ticket.status, ticket.isCheckedIn)) {
      (MobileTicketStatus.cancelled, _) => '취소됨',
      (MobileTicketStatus.used, _) => '사용 완료',
      (_, true) => '입장 완료',
      _ => '사용 가능',
    };
    final statusColor = switch ((ticket.status, ticket.isCheckedIn)) {
      (MobileTicketStatus.cancelled, _) => AdminTheme.error,
      (MobileTicketStatus.used, _) => AdminTheme.info,
      (_, true) => AdminTheme.success,
      _ => AdminTheme.success,
    };

    final url = '$_ticketBaseUrl${ticket.accessToken}';
    final recipientName = ticket.recipientName?.trim();
    final hasRecipient = recipientName != null && recipientName.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Entry number
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '${ticket.entryNumber}',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.gold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Seat info or grade
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.seatInfo ??
                      '${ticket.seatGrade}석 #${ticket.entryNumber}',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRecipient ? '받는 사람 $recipientName' : '받는 사람 미지정',
                  style: AdminTheme.sans(
                    fontSize: 10,
                    color: hasRecipient
                        ? AdminTheme.sage
                        : AdminTheme.textTertiary,
                  ),
                ),
                if (ticket.isCheckedIn)
                  Text(
                    '입장 완료 ${DateFormat('HH:mm').format(ticket.entryCheckedInAt!)}',
                    style: AdminTheme.sans(
                      fontSize: 10,
                      color: AdminTheme.info,
                    ),
                  ),
              ],
            ),
          ),

          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Text(
              statusLabel,
              style: AdminTheme.label(fontSize: 8, color: statusColor),
            ),
          ),
          if (hasRecipient) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AdminTheme.sage.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AdminTheme.sage.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Text(
                '전달됨',
                style: AdminTheme.label(fontSize: 8, color: AdminTheme.sage),
              ),
            ),
          ],
          const SizedBox(width: 6),

          // Reassign seat
          if (ticket.status == MobileTicketStatus.active)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showReassignDialog(context, ticket),
                child: Tooltip(
                  message: '좌석 재배정',
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    size: 14,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 6),

          // Copy URL
          if (ticket.status == MobileTicketStatus.active)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('티켓 #${ticket.entryNumber} URL 복사됨'),
                    ),
                  );
                },
                child: const Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 좌석 재배정 다이얼로그 ───

void _showReassignDialog(BuildContext context, MobileTicket ticket) {
  final seatIdCtrl = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.swap_horiz_rounded,
                    color: AdminTheme.gold,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '좌석 재배정',
                    style: AdminTheme.serif(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '현재: ${ticket.seatInfo ?? '미배정'}\n'
                '티켓 #${ticket.entryNumber} (${ticket.buyerName})',
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: AdminTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text('새 좌석 ID', style: AdminTheme.label(fontSize: 10)),
              const SizedBox(height: 6),
              SizedBox(
                height: 44,
                child: TextField(
                  controller: seatIdCtrl,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Firestore seat document ID',
                    hintStyle: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.textTertiary,
                    ),
                    filled: true,
                    fillColor: AdminTheme.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: AdminTheme.border,
                        width: 0.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: AdminTheme.border,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminTheme.textPrimary,
                          side: const BorderSide(
                            color: AdminTheme.border,
                            width: 0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text(
                          '취소',
                          style: AdminTheme.sans(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Consumer(
                      builder: (ctx, ref, _) => SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () async {
                            final newSeatId = seatIdCtrl.text.trim();
                            if (newSeatId.isEmpty) return;
                            try {
                              await ref
                                  .read(functionsServiceProvider)
                                  .reassignTicketSeat(
                                    ticketId: ticket.id,
                                    newSeatId: newSeatId,
                                  );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('좌석이 재배정되었습니다')),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('재배정 실패: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminTheme.gold,
                            foregroundColor: AdminTheme.onAccent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            '재배정',
                            style: AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─── SMS 발송 상태 배지 ───

class _SmsBadge extends ConsumerWidget {
  final String orderId;
  const _SmsBadge({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smsAsync = ref.watch(_smsStatusProvider(orderId));

    return smsAsync.when(
      data: (status) {
        if (status == null) return const SizedBox.shrink();

        IconData icon;
        Color color;
        String tooltip;

        switch (status) {
          case 'sent':
            icon = Icons.sms_rounded;
            color = AdminTheme.success;
            tooltip = 'SMS 발송 완료';
          case 'pending':
            icon = Icons.schedule_send_rounded;
            color = AdminTheme.gold;
            tooltip = 'SMS 발송 대기';
          case 'failed':
            icon = Icons.sms_failed_rounded;
            color = AdminTheme.error;
            tooltip = 'SMS 발송 실패';
          default:
            icon = Icons.sms_rounded;
            color = AdminTheme.textTertiary;
            tooltip = 'SMS $status';
        }

        return Tooltip(
          message: tooltip,
          child: Icon(icon, size: 14, color: color),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:melon_core/data/models/discount_policy.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

enum PaymentMethod { naverPay, tossPay, kakaoPay }

const _navy = Color(0xFF0D3E67);
const _lineBlue = Color(0xFF2F6FB2);
const _surface = Color(0xFFF3F5F8);
const _softBlue = Color(0xFFE7F0FA);
const _cardBorder = Color(0xFFD7DFE8);
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _textMuted = Color(0xFF94A3B8);
const _danger = Color(0xFFB42318);
const _success = Color(0xFF027A48);

extension on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.naverPay:
        return 'Npay';
      case PaymentMethod.tossPay:
        return '토스페이';
      case PaymentMethod.kakaoPay:
        return '카카오페이';
    }
  }

  Color get color {
    switch (this) {
      case PaymentMethod.naverPay:
        return const Color(0xFF03C75A);
      case PaymentMethod.tossPay:
        return const Color(0xFF0064FF);
      case PaymentMethod.kakaoPay:
        return const Color(0xFFFEE500);
    }
  }

  Color get textColor {
    switch (this) {
      case PaymentMethod.kakaoPay:
        return const Color(0xFF1F2937);
      case PaymentMethod.naverPay:
      case PaymentMethod.tossPay:
        return Colors.white;
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentMethod.naverPay:
        return Icons.account_balance_wallet_rounded;
      case PaymentMethod.tossPay:
        return Icons.bolt_rounded;
      case PaymentMethod.kakaoPay:
        return Icons.chat_bubble_rounded;
    }
  }
}

class CheckoutScreen extends ConsumerStatefulWidget {
  final String eventId;
  final List<String> selectedSeatIds;
  final int quantity;

  const CheckoutScreen({
    super.key,
    required this.eventId,
    this.selectedSeatIds = const [],
    this.quantity = 1,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _quantity = 1;
  bool _isProcessing = false;
  PaymentMethod? _selectedPayment;
  bool _agreedToTerms = false;
  DiscountPolicy? _selectedDiscount;

  @override
  void initState() {
    super.initState();
    _quantity = widget.quantity > 0 ? widget.quantity : 1;
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));
    final authState = ref.watch(authStateProvider);

    if (authState.value == null) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: Text(
            '결제하기',
            style: GoogleFonts.notoSans(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: _AuthRequiredState(
          onLogin: () => context.push('/login'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(
          '결제하기',
          style: GoogleFonts.notoSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: eventAsync.when(
        data: (event) {
          if (event == null) {
            return const _CenteredMessage(
              icon: Icons.event_busy_rounded,
              title: '공연 정보를 불러올 수 없습니다',
              subtitle: '잠시 후 다시 시도해 주세요.',
            );
          }

          final availableSeats = event.availableSeats;
          if (availableSeats <= 0) {
            return _CenteredMessage(
              icon: Icons.do_not_disturb_on_rounded,
              title: '예매 가능한 좌석이 없습니다',
              subtitle: '다른 회차 또는 다른 공연을 선택해 주세요.',
              actionLabel: '홈으로 이동',
              onAction: () => context.go('/'),
            );
          }

          final maxQty = event.maxTicketsPerOrder.clamp(1, availableSeats);
          if (_quantity > maxQty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _quantity = maxQty);
            });
          }

          final quantity = _quantity.clamp(1, maxQty);
          final priceFormat = NumberFormat('#,###', 'ko_KR');
          final policies = event.discountPolicies ?? [];

          // 수량 할인: 조건 충족하는 최대 할인 자동 적용
          DiscountPolicy? autoBulkDiscount;
          for (final p in policies.where((p) => p.type == 'bulk')) {
            if (quantity >= p.minQuantity) {
              if (autoBulkDiscount == null ||
                  p.discountRate > autoBulkDiscount.discountRate) {
                autoBulkDiscount = p;
              }
            }
          }
          // 적용 할인 결정: 수량 할인 vs 대상 할인 (더 큰 할인 적용)
          final activeDiscount = _selectedDiscount ?? autoBulkDiscount;
          final unitPrice = activeDiscount != null
              ? activeDiscount.discountedPrice(event.price)
              : event.price;
          final totalPrice = unitPrice * quantity;
          final originalTotal = event.price * quantity;
          final savedAmount = originalTotal - totalPrice;

          final canPay =
              _selectedPayment != null && _agreedToTerms && !_isProcessing;

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 170),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _StepIndicator(),
                    const SizedBox(height: 12),
                    _EventSummaryCard(
                      title: event.title,
                      venue: event.venueName,
                      dateText:
                          DateFormat('yyyy년 M월 d일 (E) HH:mm', 'ko_KR').format(
                        event.startAt,
                      ),
                      priceText: '${priceFormat.format(event.price)}원 / 1매',
                      selectedSeatCount: widget.selectedSeatIds.length,
                    ),
                    const SizedBox(height: 14),
                    const _SectionTitle('수량 선택'),
                    const SizedBox(height: 8),
                    _QuantityCard(
                      quantity: quantity,
                      maxQty: maxQty,
                      onMinus: quantity > 1
                          ? () => setState(() {
                                _quantity--;
                                // 수량 변경 시 대상 할인만 유지, 수량할인은 자동 재계산
                                if (_selectedDiscount?.type == 'bulk') {
                                  _selectedDiscount = null;
                                }
                              })
                          : null,
                      onPlus: quantity < maxQty
                          ? () => setState(() {
                                _quantity++;
                                if (_selectedDiscount?.type == 'bulk') {
                                  _selectedDiscount = null;
                                }
                              })
                          : null,
                    ),
                    if (quantity >= 2) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFFAF3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFB7E4C7)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.groups_rounded,
                              size: 16,
                              color: _success,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$quantity장 연속 좌석 우선 배정',
                                style: GoogleFonts.notoSans(
                                  color: _success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── 할인 정책 선택 ──
                    if (policies.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const _SectionTitle('할인 선택'),
                      const SizedBox(height: 8),
                      _DiscountSelector(
                        policies: policies,
                        quantity: quantity,
                        basePrice: event.price,
                        autoBulkDiscount: autoBulkDiscount,
                        selectedDiscount: _selectedDiscount,
                        onSelect: (p) => setState(() => _selectedDiscount = p),
                        onClear: () =>
                            setState(() => _selectedDiscount = null),
                        priceFormat: priceFormat,
                      ),
                    ],

                    const SizedBox(height: 14),
                    const _SectionTitle('간편결제 선택'),
                    const SizedBox(height: 8),
                    _PaymentGrid(
                      selectedMethod: _selectedPayment,
                      onSelected: (method) {
                        setState(() => _selectedPayment = method);
                      },
                    ),
                    const SizedBox(height: 14),
                    _AmountCard(
                      quantity: quantity,
                      unitPrice: unitPrice,
                      totalPrice: totalPrice,
                      priceFormat: priceFormat,
                      originalUnitPrice:
                          activeDiscount != null ? event.price : null,
                      savedAmount: savedAmount > 0 ? savedAmount : null,
                      discountName: activeDiscount?.name,
                    ),
                    const SizedBox(height: 14),
                    _TermsCard(
                      agreed: _agreedToTerms,
                      onToggle: () {
                        setState(() => _agreedToTerms = !_agreedToTerms);
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomPayBar(
                  totalPrice: totalPrice,
                  canPay: canPay,
                  isProcessing: _isProcessing,
                  onPay: canPay ? () => _processPayment(maxQty: maxQty) : null,
                  priceFormat: priceFormat,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: _lineBlue),
        ),
        error: (error, _) => _CenteredMessage(
          icon: Icons.error_outline_rounded,
          title: '결제 정보를 불러오지 못했습니다',
          subtitle: '$error',
          isError: true,
        ),
      ),
    );
  }

  Future<void> _processPayment({required int maxQty}) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final functionsService = ref.read(functionsServiceProvider);
      final quantity = _quantity.clamp(1, maxQty);
      final preferredSeatIds =
          widget.selectedSeatIds.take(quantity).toList(growable: false);

      final orderResult = await functionsService.createOrder(
        eventId: widget.eventId,
        quantity: quantity,
        preferredSeatIds: preferredSeatIds,
        discountPolicyName: _selectedDiscount?.name,
      );
      final orderId = orderResult['orderId'] as String;

      final confirmResult = await functionsService.confirmPaymentAndAssignSeats(
        orderId: orderId,
      );

      if (confirmResult['success'] != true) {
        throw Exception(confirmResult['error'] ?? '결제 처리에 실패했습니다');
      }

      if (!mounted) return;
      context.go('/booking-complete/$orderId');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '결제 실패: $error',
            style: GoogleFonts.notoSans(fontSize: 13),
          ),
          backgroundColor: _danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: const Row(
        children: [
          _StepNode(label: '좌석선택', index: 1, isComplete: true),
          Expanded(child: Divider(color: _lineBlue, height: 1)),
          _StepNode(label: '결제', index: 2, isActive: true),
          Expanded(child: Divider(color: _cardBorder, height: 1)),
          _StepNode(label: '완료', index: 3),
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  final String label;
  final int index;
  final bool isActive;
  final bool isComplete;

  const _StepNode({
    required this.label,
    required this.index,
    this.isActive = false,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = isActive || isComplete;

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _lineBlue : const Color(0xFFE5EAF0),
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    '$index',
                    style: GoogleFonts.robotoMono(
                      color: active ? Colors.white : _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.notoSans(
            color: active ? _lineBlue : _textMuted,
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _EventSummaryCard extends StatelessWidget {
  final String title;
  final String? venue;
  final String dateText;
  final String priceText;
  final int selectedSeatCount;

  const _EventSummaryCard({
    required this.title,
    required this.venue,
    required this.dateText,
    required this.priceText,
    required this.selectedSeatCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSans(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          _InfoLine(label: '공연일시', value: dateText),
          _InfoLine(
            label: '공연장',
            value: (venue != null && venue!.isNotEmpty) ? venue! : '공연장 정보 없음',
          ),
          _InfoLine(label: '기준금액', value: priceText),
          if (selectedSeatCount > 0)
            _InfoLine(label: '선호좌석', value: '$selectedSeatCount개 전달됨'),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: GoogleFonts.notoSans(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSans(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.notoSans(
        color: _textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _QuantityCard extends StatelessWidget {
  final int quantity;
  final int maxQty;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _QuantityCard({
    required this.quantity,
    required this.maxQty,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          _QuantityButton(icon: Icons.remove_rounded, onTap: onMinus),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$quantity',
                  style: GoogleFonts.robotoMono(
                    color: _textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '최대 $maxQty매',
                  style: GoogleFonts.notoSans(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _QuantityButton(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? _lineBlue : const Color(0xFFE5EAF0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.white : _textMuted,
        ),
      ),
    );
  }
}

class _PaymentGrid extends StatelessWidget {
  final PaymentMethod? selectedMethod;
  final ValueChanged<PaymentMethod> onSelected;

  const _PaymentGrid({
    required this.selectedMethod,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const methods = [
      PaymentMethod.naverPay,
      PaymentMethod.tossPay,
      PaymentMethod.kakaoPay,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: methods
          .map(
            (method) => _PaymentChip(
              method: method,
              isSelected: selectedMethod == method,
              onTap: () => onSelected(method),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 44) / 2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _lineBlue : _cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: method.color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(method.icon, size: 17, color: method.textColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                method.label,
                style: GoogleFonts.notoSans(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? _lineBlue : _textMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final int quantity;
  final int unitPrice;
  final int totalPrice;
  final NumberFormat priceFormat;
  final int? originalUnitPrice;
  final int? savedAmount;
  final String? discountName;

  const _AmountCard({
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.priceFormat,
    this.originalUnitPrice,
    this.savedAmount,
    this.discountName,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = originalUnitPrice != null && savedAmount != null && savedAmount! > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          if (hasDiscount) ...[
            _AmountRow(
              label: '정가',
              value: '${priceFormat.format(originalUnitPrice!)}원 x $quantity',
              valueColor: _textMuted,
              strikethrough: true,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: discountName ?? '할인 적용',
              value: '-${priceFormat.format(savedAmount!)}원',
              valueColor: _danger,
            ),
            const SizedBox(height: 4),
          ],
          _AmountRow(
            label: '티켓 금액',
            value: '${priceFormat.format(unitPrice)}원 x $quantity',
          ),
          const SizedBox(height: 6),
          const _AmountRow(label: '수수료', value: '0원', valueColor: _success),
          const Divider(color: _cardBorder, height: 18),
          _AmountRow(
            label: '총 결제 금액',
            value: '${priceFormat.format(totalPrice)}원',
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;
  final bool strikethrough;

  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
    this.strikethrough = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.notoSans(
            color: emphasize ? _textPrimary : _textSecondary,
            fontSize: emphasize ? 15 : 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.notoSans(
            color: valueColor ?? (emphasize ? _lineBlue : _textPrimary),
            fontSize: emphasize ? 24 : 14,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: emphasize ? -0.3 : 0,
            decoration: strikethrough ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }
}

// ─── 할인 선택기 ───
class _DiscountSelector extends StatelessWidget {
  final List<DiscountPolicy> policies;
  final int quantity;
  final int basePrice;
  final DiscountPolicy? autoBulkDiscount;
  final DiscountPolicy? selectedDiscount;
  final ValueChanged<DiscountPolicy?> onSelect;
  final VoidCallback onClear;
  final NumberFormat priceFormat;

  const _DiscountSelector({
    required this.policies,
    required this.quantity,
    required this.basePrice,
    required this.autoBulkDiscount,
    required this.selectedDiscount,
    required this.onSelect,
    required this.onClear,
    required this.priceFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 할인 없음 옵션
          _DiscountOption(
            name: '일반 (할인 없음)',
            price: '${priceFormat.format(basePrice)}원',
            isSelected: selectedDiscount == null && autoBulkDiscount == null,
            onTap: onClear,
          ),

          // 수량 할인 (자동)
          if (autoBulkDiscount != null)
            _DiscountOption(
              name: autoBulkDiscount!.name,
              price:
                  '${priceFormat.format(autoBulkDiscount!.discountedPrice(basePrice))}원',
              discountRate:
                  '${(autoBulkDiscount!.discountRate * 100).toInt()}%',
              description: autoBulkDiscount!.description,
              isSelected: selectedDiscount == null ||
                  selectedDiscount?.name == autoBulkDiscount!.name,
              isAuto: true,
              onTap: onClear,
            ),

          // 대상 할인
          ...policies.where((p) => p.type == 'special').map((p) {
            return _DiscountOption(
              name: p.name,
              price: '${priceFormat.format(p.discountedPrice(basePrice))}원',
              discountRate: '${(p.discountRate * 100).toInt()}%',
              description: p.description,
              isSelected: selectedDiscount?.name == p.name,
              onTap: () => onSelect(p),
            );
          }),
        ],
      ),
    );
  }
}

class _DiscountOption extends StatelessWidget {
  final String name;
  final String price;
  final String? discountRate;
  final String? description;
  final bool isSelected;
  final bool isAuto;
  final VoidCallback onTap;

  const _DiscountOption({
    required this.name,
    required this.price,
    this.discountRate,
    this.description,
    required this.isSelected,
    this.isAuto = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _softBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _lineBlue.withValues(alpha: 0.4) : _cardBorder,
          ),
        ),
        child: Row(
          children: [
            // 라디오 인디케이터
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? _lineBlue : _textMuted,
                  width: isSelected ? 5 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 내용
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (discountRate != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            discountRate!,
                            style: GoogleFonts.notoSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _danger,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.notoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      if (isAuto)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '자동적용',
                            style: GoogleFonts.notoSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description!,
                        style: GoogleFonts.notoSans(
                          fontSize: 11,
                          color: _textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              price,
              style: GoogleFonts.notoSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsCard extends StatelessWidget {
  final bool agreed;
  final VoidCallback onToggle;

  const _TermsCard({required this.agreed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: agreed ? _lineBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: agreed ? _lineBlue : _cardBorder,
                      width: 1.4,
                    ),
                  ),
                  child: agreed
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '구매 조건 및 취소/환불 규정에 동의합니다',
                    style: GoogleFonts.notoSans(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDE3EA)),
            ),
            child: Text(
              '취소/환불 기준: 공연 24시간 전까지 100%, 공연 3시간 전까지 70%, 이후 환불 불가',
              style: GoogleFonts.notoSans(
                color: _textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPayBar extends StatelessWidget {
  final int totalPrice;
  final bool canPay;
  final bool isProcessing;
  final VoidCallback? onPay;
  final NumberFormat priceFormat;

  const _BottomPayBar({
    required this.totalPrice,
    required this.canPay,
    required this.isProcessing,
    required this.onPay,
    required this.priceFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        MediaQuery.of(context).padding.bottom == 0
            ? 12
            : MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: _softBlue,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: PressableScale(
        child: SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: canPay ? onPay : null,
            style: FilledButton.styleFrom(
              backgroundColor: canPay ? _lineBlue : const Color(0xFFBFCAD6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isProcessing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    '${priceFormat.format(totalPrice)}원 결제/발권',
                    style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AuthRequiredState extends StatelessWidget {
  final VoidCallback onLogin;

  const _AuthRequiredState({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: _lineBlue,
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '로그인 후 결제를 진행할 수 있습니다',
              style: GoogleFonts.notoSans(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 170,
              child: FilledButton(
                onPressed: onLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: _lineBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  '로그인',
                  style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? _danger : _textSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.notoSans(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.notoSans(
                color: color,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: _lineBlue),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.notoSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/discount_policy.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

enum PaymentMethod { naverPay, tossPay, kakaoPay }

// ─── Editorial Theme Colors ───
const _navy = Color(0xFF3B0D11);
const _lineBlue = Color(0xFF3B0D11);
const _surface = Color(0xFFFAF8F5);
const _softBlue = Color(0xFFF5EEED);
const _cardBorder = Color(0x40748386);
const _textPrimary = Color(0xFF3B0D11);
const _textSecondary = Color(0xFF748386);
const _textMuted = Color(0x99748386);
const _danger = Color(0xFFC42A4D);
const _success = Color(0xFF2D6A4F);

// ─── Brand Logo SVGs ───
const _naverLogoSvg =
    '<svg viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M13.56 10.07L6.28 0H0v20h6.44V9.93L13.72 20H20V0h-6.44v10.07z" fill="white"/>'
    '</svg>';

const _kakaoLogoSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 3C6.48 3 2 6.36 2 10.5c0 2.69 1.82 5.04 4.55 6.35l-.97 3.54c-.08.28.18.52.41.35l3.66-2.45c.77.12 1.57.17 2.38.17 5.52 0 10-3.33 10-7.46S17.52 3 12 3z" fill="#191600"/>'
    '</svg>';

// ─── Premium text shadows (from AppTheme) ───
const _premiumShadow = AppTheme.textShadow;
const _premiumShadowStrong = AppTheme.textShadowStrong;

extension on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.naverPay:
        return '네이버페이';
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

  Widget get logoMark {
    switch (this) {
      case PaymentMethod.naverPay:
        return SvgPicture.string(_naverLogoSvg, width: 18, height: 18);
      case PaymentMethod.tossPay:
        return Text(
          'toss',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1,
            shadows: const [
              Shadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2),
            ],
          ),
        );
      case PaymentMethod.kakaoPay:
        return SvgPicture.string(_kakaoLogoSvg, width: 20, height: 20);
    }
  }
}

class CheckoutScreen extends ConsumerStatefulWidget {
  final String eventId;
  final List<String> selectedSeatIds;
  final List<String> selectedSeatLabels;
  final List<String> selectedSeatGrades;
  final int quantity;

  const CheckoutScreen({
    super.key,
    required this.eventId,
    this.selectedSeatIds = const [],
    this.selectedSeatLabels = const [],
    this.selectedSeatGrades = const [],
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
    // 좌석이 선택된 경우 좌석 수 사용, 아니면 전달된 수량 사용
    _quantity = widget.selectedSeatIds.isNotEmpty
        ? widget.selectedSeatIds.length
        : (widget.quantity > 0 ? widget.quantity : 1);
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));
    final authState = ref.watch(authStateProvider);

    Widget backButton() => IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 24, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        );

    if (authState.value == null) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          leading: backButton(),
          title: Text(
            '결제하기',
            style: AppTheme.nanum(
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
        leading: backButton(),
        title: Text(
          '결제하기',
          style: AppTheme.nanum(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 4),
            ],
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
          // 좌석이 명시적으로 선택된 경우 좌석 수를 우선 사용
          final quantity = widget.selectedSeatIds.isNotEmpty
              ? widget.selectedSeatIds.length
              : _quantity.clamp(1, maxQty);
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
                      seatCount: widget.selectedSeatIds.length,
                      quantity: quantity,
                    ),
                    const SizedBox(height: 14),
                    _SectionTitle(
                      widget.selectedSeatIds.isNotEmpty
                          ? '선택 좌석 (${widget.selectedSeatIds.length}석)'
                          : '수량 선택',
                    ),
                    const SizedBox(height: 8),
                    if (widget.selectedSeatIds.isNotEmpty)
                      _SelectedSeatsCard(
                        seatLabels: widget.selectedSeatLabels,
                        seatGrades: widget.selectedSeatGrades,
                        seatCount: widget.selectedSeatIds.length,
                        onChangeSeat: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/events/${widget.eventId}');
                          }
                        },
                      )
                    else
                      _QuantityCard(
                        quantity: quantity,
                        maxQty: maxQty,
                        onMinus: quantity > 1
                            ? () => setState(() {
                                  _quantity--;
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

      // 추천 코드 추출 (URL의 ref 쿼리 파라미터)
      String? referralCode;
      if (kIsWeb) {
        referralCode = Uri.base.queryParameters['ref'];
      }

      final orderResult = await functionsService.createOrder(
        eventId: widget.eventId,
        quantity: quantity,
        preferredSeatIds: preferredSeatIds,
        discountPolicyName: _selectedDiscount?.name,
        referralCode: referralCode,
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
            style: AppTheme.nanum(fontSize: 13),
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
            color: active ? _lineBlue : const Color(0xFFE8E2DF),
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
          style: AppTheme.nanum(
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
  final int seatCount;
  final int quantity;

  const _EventSummaryCard({
    required this.title,
    required this.venue,
    required this.dateText,
    required this.priceText,
    required this.seatCount,
    required this.quantity,
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
            style: AppTheme.nanum(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.2,
              shadows: _premiumShadowStrong,
            ),
          ),
          const SizedBox(height: 8),
          _InfoLine(label: '공연일시', value: dateText),
          _InfoLine(
            label: '공연장',
            value: (venue != null && venue!.isNotEmpty) ? venue! : '공연장 정보 없음',
          ),
          _InfoLine(label: '기준금액', value: priceText),
          _InfoLine(label: '매수', value: '$quantity매'),
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
              style: AppTheme.nanum(
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
              style: AppTheme.nanum(
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
      style: AppTheme.nanum(
        color: _textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        shadows: _premiumShadow,
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
                    shadows: _premiumShadowStrong,
                  ),
                ),
                Text(
                  '최대 $maxQty매',
                  style: AppTheme.nanum(
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
          color: enabled ? _lineBlue : const Color(0xFFE8E2DF),
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

class _SelectedSeatsCard extends StatelessWidget {
  final List<String> seatLabels;
  final List<String> seatGrades;
  final int seatCount;
  final VoidCallback onChangeSeat;

  const _SelectedSeatsCard({
    required this.seatLabels,
    required this.seatGrades,
    required this.seatCount,
    required this.onChangeSeat,
  });

  static const _gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFF6B4FA0),
    'S': Color(0xFF2D6A4F),
    'A': Color(0xFF3B7DD8),
  };

  @override
  Widget build(BuildContext context) {
    final labels = seatLabels.isNotEmpty
        ? seatLabels
        : List.generate(seatCount, (i) => '좌석 ${i + 1}');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...labels.asMap().entries.map((entry) {
            final i = entry.key;
            final label = entry.value;
            final grade = i < seatGrades.length ? seatGrades[i] : '';
            final gradeColor = _gradeColors[grade] ?? _textSecondary;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (grade.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: gradeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: gradeColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        grade,
                        style: AppTheme.nanum(
                          color: gradeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _softBlue,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _lineBlue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.event_seat_rounded,
                        size: 14,
                        color: _lineBlue,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTheme.nanum(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        shadows: _premiumShadow,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              onPressed: onChangeSeat,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: Text(
                '좌석 변경',
                style: AppTheme.nanum(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _lineBlue,
                side: BorderSide(
                  color: _lineBlue.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
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
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _lineBlue.withValues(alpha: 0.12),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x08000000),
                    offset: Offset(0, 1),
                    blurRadius: 4,
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(method.color, Colors.white, 0.15)!,
                    method.color,
                    Color.lerp(method.color, Colors.black, 0.08)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: method.color.withValues(alpha: 0.4),
                    offset: const Offset(0, 2),
                    blurRadius: 6,
                  ),
                  BoxShadow(
                    color: method.color.withValues(alpha: 0.15),
                    offset: const Offset(0, 4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Center(child: method.logoMark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                method.label,
                style: AppTheme.nanum(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  shadows: _premiumShadow,
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
          style: AppTheme.nanum(
            color: emphasize ? _textPrimary : _textSecondary,
            fontSize: emphasize ? 15 : 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            shadows: emphasize ? _premiumShadow : null,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTheme.nanum(
            color: valueColor ?? (emphasize ? _lineBlue : _textPrimary),
            fontSize: emphasize ? 24 : 14,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: emphasize ? -0.3 : 0,
            decoration: strikethrough ? TextDecoration.lineThrough : null,
            shadows: emphasize ? _premiumShadowStrong : null,
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
                            style: AppTheme.nanum(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _danger,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          name,
                          style: AppTheme.nanum(
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
                            style: AppTheme.nanum(
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
                        style: AppTheme.nanum(
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
              style: AppTheme.nanum(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                shadows: _premiumShadow,
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
                    style: AppTheme.nanum(
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
              color: const Color(0xFFF5F0EE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD9D0CC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '취소/환불 수수료 규정',
                  style: AppTheme.nanum(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• 예매 후 7일 이내: 무료취소\n'
                  '• 예매 후 8일 ~ 관람일 10일 전: 공연권 4,000원 / 입장권 2,000원 (최대 10%)\n'
                  '• 관람일 9일 전 ~ 7일 전: 티켓금액의 10%\n'
                  '• 관람일 6일 전 ~ 3일 전: 티켓금액의 20%\n'
                  '• 관람일 2일 전 ~ 1일 전: 티켓금액의 30%\n'
                  '• 관람 당일: 취소/환불 불가',
                  style: AppTheme.nanum(
                    color: _textSecondary,
                    fontSize: 11,
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
              backgroundColor: canPay ? _lineBlue : const Color(0xFFB8ADAA),
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
                    style: AppTheme.nanum(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(color: Color(0x30000000), offset: Offset(0, 1), blurRadius: 3),
                      ],
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
              style: AppTheme.nanum(
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
                  style: AppTheme.nanum(fontWeight: FontWeight.w700),
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
              style: AppTheme.nanum(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTheme.nanum(
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
                  style: AppTheme.nanum(
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

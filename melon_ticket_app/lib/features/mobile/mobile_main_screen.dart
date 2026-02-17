import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/models/event.dart';
import '../tickets/my_tickets_screen.dart';

class MobileMainScreen extends ConsumerStatefulWidget {
  final String? focusEventId;
  final int initialIndex;

  const MobileMainScreen({
    super.key,
    this.focusEventId,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<MobileMainScreen> createState() => _MobileMainScreenState();
}

class _MobileMainScreenState extends ConsumerState<MobileMainScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoggedIn = authState.value != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _QuickBookingTab(
            focusEventId: widget.focusEventId,
            onOpenDiscover: () => setState(() => _currentIndex = 1),
          ),
          const _HomeTab(),
          isLoggedIn
              ? const MyTicketsScreen()
              : _LoginRequiredTab(onLogin: () => context.push('/login')),
          _ProfileTab(isLoggedIn: isLoggedIn),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.flash_on_rounded,
                  label: '바로예매',
                  isSelected: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.view_carousel_rounded,
                  label: '다른공연',
                  isSelected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.confirmation_number_rounded,
                  label: '내티켓',
                  isSelected: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: '마이',
                  isSelected: _currentIndex == 3,
                  onTap: () => setState(() => _currentIndex = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Nav Item ───
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 74,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.gold : AppTheme.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppTheme.gold : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Booking Tab ───
class _QuickBookingTab extends ConsumerWidget {
  final String? focusEventId;
  final VoidCallback onOpenDiscover;

  const _QuickBookingTab({
    required this.focusEventId,
    required this.onOpenDiscover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedFocusId = focusEventId?.trim();
    if (normalizedFocusId != null && normalizedFocusId.isNotEmpty) {
      final focusedEventAsync =
          ref.watch(eventStreamProvider(normalizedFocusId));
      return focusedEventAsync.when(
        data: (event) => _buildQuickBookingContent(
          context,
          event,
          fromLink: true,
        ),
        loading: () => _buildQuickBookingScaffold(
          context,
          child: const Center(
            child: CircularProgressIndicator(color: AppTheme.gold),
          ),
        ),
        error: (_, __) => _buildQuickBookingContent(
          context,
          null,
          fromLink: true,
        ),
      );
    }

    final eventsAsync = ref.watch(eventsStreamProvider);
    return eventsAsync.when(
      data: (events) => _buildQuickBookingContent(
        context,
        _selectPrimaryEvent(events),
        fromLink: false,
      ),
      loading: () => _buildQuickBookingScaffold(
        context,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
      ),
      error: (_, __) =>
          _buildQuickBookingContent(context, null, fromLink: false),
    );
  }

  Event? _selectPrimaryEvent(List<Event> events) {
    if (events.isEmpty) return null;

    final sorted = [...events]..sort((a, b) => a.startAt.compareTo(b.startAt));
    for (final event in sorted) {
      if (event.isOnSale && event.availableSeats > 0) {
        return event;
      }
    }
    return sorted.first;
  }

  Widget _buildQuickBookingScaffold(
    BuildContext context, {
    required Widget child,
  }) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppTheme.surface,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.goldGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.flash_on_rounded,
                      color: AppTheme.onAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '바로 예매',
                        style: GoogleFonts.notoSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '링크 유입 시 바로 좌석선택으로 연결됩니다',
                        style: GoogleFonts.notoSans(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickBookingContent(
    BuildContext context,
    Event? event, {
    required bool fromLink,
  }) {
    if (event == null) {
      return _buildQuickBookingScaffold(
        context,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event_busy_rounded,
                  color: AppTheme.textTertiary,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  fromLink ? '링크 공연을 찾을 수 없습니다' : '현재 예매 가능한 공연이 없습니다',
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '다른 공연 탭에서 등록된 공연을 확인하세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: onOpenDiscover,
                  child: const Text('다른 공연 보기'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildQuickBookingScaffold(
      context,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border, width: 0.6),
            ),
            child: Row(
              children: [
                Icon(
                  fromLink ? Icons.link_rounded : Icons.star_rounded,
                  size: 16,
                  color: AppTheme.gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fromLink ? '링크로 접속한 공연' : '현재 우선 예매 공연',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _QuickBookingEventCard(event: event),
          const SizedBox(height: 12),
          _buildEventDetailCarousel(event),
          const SizedBox(height: 14),
          _buildBookingButton(context, event, fromLink: fromLink),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.push('/event/${event.id}'),
            child: const Text('공연 상세 보기'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onOpenDiscover,
            child: const Text('다른 공연 탭으로 이동'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingButton(
    BuildContext context,
    Event event, {
    required bool fromLink,
  }) {
    final now = DateTime.now();
    final isSoldOut =
        event.status == EventStatus.soldOut || event.availableSeats <= 0;
    final saleEnded = now.isAfter(event.saleEndAt);

    String label;
    VoidCallback? onPressed;

    if (event.isOnSale && !isSoldOut) {
      label = '실제로 보면서 예매!';
      onPressed =
          () => _openAIQuickConditions(context, event, fromLink: fromLink);
    } else if (isSoldOut) {
      label = '매진된 공연입니다';
    } else if (saleEnded) {
      label = '예매가 종료된 공연입니다';
    } else {
      label = '예매 오픈 일정 확인하기';
      onPressed = () => context.push('/event/${event.id}');
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.notoSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildEventDetailCarousel(Event event) {
    final dateText = DateFormat('M/d (E) HH:mm', 'ko_KR').format(event.startAt);
    final saleText = DateFormat('M/d HH:mm', 'ko_KR').format(event.saleStartAt);
    final priceText = NumberFormat('#,###', 'ko_KR').format(event.price);
    final cards = <_QuickInfoCard>[
      _QuickInfoCard(
        title: '공연 일정',
        value: dateText,
        hint:
            event.venueName?.isNotEmpty == true ? event.venueName! : '장소 정보 없음',
        icon: Icons.schedule_rounded,
      ),
      _QuickInfoCard(
        title: '가격 / 잔여',
        value: '$priceText원',
        hint: '잔여 ${event.availableSeats}석',
        icon: Icons.confirmation_number_rounded,
      ),
      const _QuickInfoCard(
        title: 'AI 배치 포인트',
        value: '예산 + 악기 기준',
        hint: '좌석 3개 자동 추천',
        icon: Icons.auto_awesome_rounded,
      ),
      _QuickInfoCard(
        title: '시야 확인',
        value: '360° 프리뷰',
        hint: event.isOnSale ? '바로 체험 가능' : '오픈 $saleText',
        icon: Icons.threesixty_rounded,
      ),
    ];

    return SizedBox(
      height: 114,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final card = cards[index];
          return Container(
            width: 170,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(card.icon, size: 16, color: AppTheme.gold),
                const SizedBox(height: 8),
                Text(
                  card.title,
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  card.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  card.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAIQuickConditions(
    BuildContext context,
    Event event, {
    required bool fromLink,
  }) async {
    int quantity = 2;
    final maxQty = event.maxTicketsPerOrder.clamp(1, 4);
    if (quantity > maxQty) quantity = maxQty;
    int maxBudget = 0;
    String instrument = '상관없음';

    budgetOptionsForQty(int qty) {
      final base = event.price * qty;
      return <int>[0, base, (base * 1.4).round(), base * 2];
    }

    String budgetLabel(int value, int qty) {
      if (value <= 0) return '예산 상관없음';
      final fmt = NumberFormat('#,###', 'ko_KR');
      final base = event.price * qty;
      if (value <= base) return '가성비 (${fmt.format(value)}원)';
      if (value <= (base * 1.4).round()) return '표준 (${fmt.format(value)}원)';
      return '프리미엄 (${fmt.format(value)}원)';
    }

    final result = await showModalBottomSheet<_AIQuickCondition>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final budgetOptions = budgetOptionsForQty(quantity);
            if (!budgetOptions.contains(maxBudget)) {
              maxBudget = budgetOptions.first;
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      fromLink ? '링크 공연 AI 예매 조건' : 'AI 예매 조건',
                      style: GoogleFonts.notoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '세 가지만 고르면 바로 자동 배치됩니다.',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '인원',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(maxQty, (i) => i + 1).map((n) {
                        final selected = n == quantity;
                        return ChoiceChip(
                          label: Text('$n명'),
                          selected: selected,
                          onSelected: (_) => setSheetState(() => quantity = n),
                          labelStyle: GoogleFonts.notoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppTheme.onAccent
                                : AppTheme.textSecondary,
                          ),
                          selectedColor: AppTheme.gold,
                          backgroundColor: AppTheme.surface,
                          side: BorderSide(
                            color: selected ? AppTheme.gold : AppTheme.border,
                            width: 0.7,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '총 예산',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: budgetOptions.map((value) {
                        final selected = value == maxBudget;
                        return ChoiceChip(
                          label: Text(budgetLabel(value, quantity)),
                          selected: selected,
                          onSelected: (_) =>
                              setSheetState(() => maxBudget = value),
                          labelStyle: GoogleFonts.notoSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppTheme.onAccent
                                : AppTheme.textSecondary,
                          ),
                          selectedColor: AppTheme.gold,
                          backgroundColor: AppTheme.surface,
                          side: BorderSide(
                            color: selected ? AppTheme.gold : AppTheme.border,
                            width: 0.7,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '보고 싶은 악기',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const ['상관없음', '보컬', '피아노', '기타', '드럼', '관악']
                          .map((inst) {
                        final selected = inst == instrument;
                        return ChoiceChip(
                          label: Text(inst),
                          selected: selected,
                          onSelected: (_) =>
                              setSheetState(() => instrument = inst),
                          labelStyle: GoogleFonts.notoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppTheme.onAccent
                                : AppTheme.textSecondary,
                          ),
                          selectedColor: AppTheme.gold,
                          backgroundColor: AppTheme.surface,
                          side: BorderSide(
                            color: selected ? AppTheme.gold : AppTheme.border,
                            width: 0.7,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(
                          _AIQuickCondition(
                            quantity: quantity,
                            maxBudget: maxBudget,
                            instrument: instrument,
                          ),
                        ),
                        child: Text(
                          'AI 배치 + 360 시야 보기',
                          style: GoogleFonts.notoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !context.mounted) return;

    final query = <String, String>{
      'ai': '1',
      'qty': '${result.quantity}',
      'inst': result.instrument,
    };
    if (result.maxBudget > 0) {
      query['budget'] = '${result.maxBudget}';
    }

    context.push(
        Uri(path: '/seats/${event.id}', queryParameters: query).toString());
  }
}

class _QuickInfoCard {
  final String title;
  final String value;
  final String hint;
  final IconData icon;

  const _QuickInfoCard({
    required this.title,
    required this.value,
    required this.hint,
    required this.icon,
  });
}

class _AIQuickCondition {
  final int quantity;
  final int maxBudget;
  final String instrument;

  const _AIQuickCondition({
    required this.quantity,
    required this.maxBudget,
    required this.instrument,
  });
}

class _QuickBookingEventCard extends StatelessWidget {
  final Event event;

  const _QuickBookingEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR').format(event.startAt);
    final saleOpenText =
        DateFormat('M/d HH:mm', 'ko_KR').format(event.saleStartAt);
    final priceText = NumberFormat('#,###', 'ko_KR').format(event.price);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 96,
              height: 132,
              child: event.imageUrl != null && event.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: event.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppTheme.cardElevated,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.gold,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _PosterPlaceholder(),
                    )
                  : _PosterPlaceholder(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.category?.isNotEmpty == true)
                  Text(
                    event.category!,
                    style: GoogleFonts.notoSans(
                      color: AppTheme.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                _metaLine(Icons.schedule_rounded, dateText),
                if (event.venueName?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  _metaLine(Icons.location_on_rounded, event.venueName!),
                ],
                const SizedBox(height: 3),
                _metaLine(
                  Icons.confirmation_number_rounded,
                  '잔여 ${event.availableSeats}석',
                ),
                const SizedBox(height: 10),
                Text(
                  '$priceText원',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.isOnSale ? '지금 바로 예매 가능' : '오픈: $saleOpenText',
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: event.isOnSale
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppTheme.textTertiary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSans(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Home Tab ───
class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return CustomScrollView(
      slivers: [
        // ── 앱바 ──
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.surface,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 20,
              right: 20,
              bottom: 14,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE76282), Color(0xFF8A1632)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.goldLight.withOpacity(0.45),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.gold.withOpacity(0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.onAccent.withOpacity(0.45),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          'M',
                          style: GoogleFonts.poppins(
                            color: AppTheme.onAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '다른 공연',
                      style: GoogleFonts.notoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      '전체 라인업 보기',
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── 세그먼트 메뉴 ──
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: const SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryChip(label: '전체', isSelected: true),
                  SizedBox(width: 8),
                  _CategoryChip(label: '콘서트'),
                  SizedBox(width: 8),
                  _CategoryChip(label: '뮤지컬'),
                  SizedBox(width: 8),
                  _CategoryChip(label: '연극'),
                  SizedBox(width: 8),
                  _CategoryChip(label: '클래식'),
                ],
              ),
            ),
          ),
        ),

        // ── 구분선 ──
        SliverToBoxAdapter(
          child: Container(height: 0.5, color: AppTheme.border),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4A1223),
                    AppTheme.cardElevated,
                    Color(0xFF2A1320),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.gold.withOpacity(0.35),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(
                    top: -30,
                    right: -20,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.gold.withOpacity(0.1),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -42,
                    left: -24,
                    child: Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.goldDark.withOpacity(0.18),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF7F1932),
                                    Color(0xFFC42A4D)
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppTheme.goldLight.withOpacity(0.4),
                                  width: 0.7,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 12,
                                    color: AppTheme.onAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '추천 PICK',
                                    style: GoogleFonts.notoSans(
                                      color: AppTheme.onAccent,
                                      fontSize: 10,
                                      letterSpacing: 0.2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '모바일 예매 추천',
                              style: GoogleFonts.notoSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.goldLight,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'AI 좌석 추천'),
                              TextSpan(
                                text: ' · ',
                                style: GoogleFonts.notoSans(
                                  color: AppTheme.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextSpan(
                                text: '360° 시야',
                                style: GoogleFonts.notoSans(
                                  color: AppTheme.goldLight,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              TextSpan(
                                text: ' · 모바일티켓',
                                style: GoogleFonts.notoSans(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          style: GoogleFonts.notoSans(
                            fontSize: 17,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '좌석 선택 화면에서 구역별 시야를 확인하고\n취소/환불 정책까지 한 번에 확인하세요.',
                          style: GoogleFonts.notoSans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: OutlinedButton(
              onPressed: () => context.push('/demo-flow'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.gold.withOpacity(0.55)),
                foregroundColor: AppTheme.gold,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '공연등록부터 스캔까지 데모 실행',
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        // ── 공연 목록 ──
        eventsAsync.when(
          data: (events) {
            if (events.isEmpty) {
              return SliverToBoxAdapter(child: _EmptyState());
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final event = events[index];
                  return _EventCard(event: event);
                },
                childCount: events.length,
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ERROR',
                        style: GoogleFonts.robotoMono(
                          color: AppTheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '공연 정보를 불러올 수 없습니다',
                      style:
                          GoogleFonts.notoSans(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 하단 여백
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ─── Category Chip ───
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  const _CategoryChip({required this.label, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.gold : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.gold : AppTheme.border,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSans(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? const Color(0xFFFDF3F6) : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ─── Event Card (NOL 인터파크 스타일 수평 카드) ───
class _EventCard extends StatelessWidget {
  final Event event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
    final priceFormat = NumberFormat('#,###');

    return GestureDetector(
      onTap: () => context.push('/event/${event.id}'),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 포스터 썸네일 ──
            Container(
              width: 100,
              height: 140,
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: event.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppTheme.card,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _PosterPlaceholder(),
                    )
                  else
                    _PosterPlaceholder(),
                  // 상태 뱃지
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _StatusBadge(event: event),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // ── 정보 ──
            Expanded(
              child: SizedBox(
                height: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 카테고리
                    if (event.category != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          event.category!,
                          style: GoogleFonts.notoSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),

                    // 제목
                    Text(
                      event.title,
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // 날짜
                    Text(
                      dateFormat.format(event.startAt),
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),

                    // 장소
                    if (event.venueName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.venueName!,
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const Spacer(),

                    // 가격
                    Text(
                      '${priceFormat.format(event.price)}원',
                      style: GoogleFonts.notoSans(
                        fontSize: 16,
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
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.cardElevated,
      child: Center(
        child: Text(
          'POSTER',
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            letterSpacing: 1.0,
            color: AppTheme.gold.withOpacity(0.45),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Event event;
  const _StatusBadge({required this.event});

  @override
  Widget build(BuildContext context) {
    String label;
    Color bgColor;
    Color fgColor;

    if (event.isOnSale) {
      label = '예매중';
      bgColor = AppTheme.success;
      fgColor = Colors.white;
    } else if (event.status == EventStatus.soldOut ||
        event.availableSeats == 0) {
      label = '매진';
      bgColor = AppTheme.error;
      fgColor = Colors.white;
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      label = '예매예정';
      bgColor = AppTheme.gold;
      fgColor = const Color(0xFFFDF3F6);
    } else {
      label = '종료';
      bgColor = AppTheme.textTertiary;
      fgColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.goldSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'EMPTY',
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                color: AppTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '등록된 공연이 없습니다',
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Login Required Tab ───
class _LoginRequiredTab extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoginRequiredTab({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Text(
                      'LOGIN',
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        color: AppTheme.gold.withOpacity(0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '로그인이 필요합니다',
                  style: GoogleFonts.notoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '티켓을 확인하려면 로그인해주세요',
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 200,
                  child: ElevatedButton(
                    onPressed: onLogin,
                    child: const Text('로그인'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Profile Tab ───
class _ProfileTab extends ConsumerWidget {
  final bool isLoggedIn;
  const _ProfileTab({required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final profileName =
        currentUser.value?.displayName ?? currentUser.value?.email ?? '사용자';
    final profileInitial = profileName.trim().isNotEmpty
        ? profileName.trim().substring(0, 1).toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 8),
            Text(
              '마이페이지',
              style: GoogleFonts.notoSans(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),

            // 사용자 정보 카드
            if (isLoggedIn)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppTheme.goldGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          profileInitial,
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFFDF3F6),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profileName,
                            style: GoogleFonts.notoSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (currentUser.value?.isAdmin == true)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.goldSubtle,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '관리자',
                                style: GoogleFonts.notoSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            if (!isLoggedIn)
              _MenuItem(
                icon: Icons.login_rounded,
                title: '로그인',
                subtitle: '계정에 로그인하세요',
                onTap: () => context.push('/login'),
              ),

            const SizedBox(height: 16),

            // 스태프/관리자 메뉴
            if (currentUser.value?.isStaff == true) ...[
              _MenuItem(
                icon: Icons.qr_code_scanner_rounded,
                title: '입장 스캐너',
                subtitle: '티켓 QR 스캔',
                onTap: () => context.push('/staff/scanner'),
              ),
              const SizedBox(height: 8),
            ],

            if (currentUser.value?.isAdmin == true) ...[
              _MenuItem(
                icon: Icons.add_circle_outline_rounded,
                title: '공연 등록',
                subtitle: '새 공연을 등록합니다',
                onTap: () => context.push('/admin/events/create'),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.location_city_rounded,
                title: '공연장 관리',
                subtitle: '좌석배치도 · 3D 시야 업로드',
                onTap: () => context.push('/admin/venues'),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.admin_panel_settings_rounded,
                title: '관리자 대시보드',
                subtitle: '공연 및 좌석 관리',
                onTap: () => context.push('/admin'),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 16),

            if (isLoggedIn)
              _MenuItem(
                icon: Icons.logout_rounded,
                title: '로그아웃',
                subtitle: '계정에서 로그아웃',
                onTap: () => ref.read(authServiceProvider).signOut(),
                isDestructive: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppTheme.error.withOpacity(0.15)
                    : AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isDestructive ? AppTheme.error : AppTheme.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color:
                          isDestructive ? AppTheme.error : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

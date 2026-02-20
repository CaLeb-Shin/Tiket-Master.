import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/widgets/premium_effects.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/models/event.dart';
import '../tickets/my_tickets_screen.dart';
import '../widgets/app_download_banner.dart';

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
      body: Column(
        children: [
          const AppDownloadBanner(),
          Expanded(
            child: IndexedStack(
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
          ),
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
                  icon: Icons.bolt_outlined,
                  activeIcon: Icons.bolt_rounded,
                  label: 'BOOKING',
                  isSelected: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  label: 'DISCOVER',
                  isSelected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.confirmation_number_outlined,
                  activeIcon: Icons.confirmation_number_rounded,
                  label: 'TICKETS',
                  isSelected: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'PROFILE',
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

// ─── Bottom Nav Item (Editorial) ───
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
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
              isSelected ? activeIcon : icon,
              color: isSelected ? AppTheme.gold : AppTheme.sage,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.label(
                fontSize: 9,
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
            // ── Editorial Header ──
            Container(
              width: double.infinity,
              color: AppTheme.surface,
              padding: const EdgeInsets.fromLTRB(24, 18, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PREMIUM SELECTION',
                          style: AppTheme.label(
                            fontSize: 10,
                            color: AppTheme.sage,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '바로 예매',
                          style: AppTheme.serif(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.search_rounded,
                      color: AppTheme.textPrimary,
                      size: 24,
                    ),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(
                          color: AppTheme.border,
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 0.5, color: AppTheme.border),
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
                  Icons.event_busy_outlined,
                  color: AppTheme.sage,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  fromLink ? '링크 공연을 찾을 수 없습니다' : '현재 예매 가능한 공연이 없습니다',
                  style: AppTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '다른 공연 탭에서 등록된 공연을 확인하세요.',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
        children: [
          // ── Priority badge ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  fromLink ? Icons.link_rounded : Icons.star_outline_rounded,
                  size: 14,
                  color: AppTheme.gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fromLink ? '링크로 접속한 공연' : '현재 우선 예매 공연',
                    style: AppTheme.label(
                      fontSize: 10,
                      color: AppTheme.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Event Card ──
          _QuickBookingEventCard(event: event),
          const SizedBox(height: 20),

          // ── 2x2 Grid info cards ──
          _buildEventDetailGrid(event),
          const SizedBox(height: 20),

          // ── CTA Button ──
          _buildBookingButton(context, event, fromLink: fromLink),
          const SizedBox(height: 10),

          // ── Outlined secondary button ──
          OutlinedButton(
            onPressed: () => context.push('/event/${event.id}'),
            child: const Text('공연 상세 보기'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onOpenDiscover,
            child: const Text('다른 공연 둘러보기'),
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

    return ShimmerButton(
      text: label.toUpperCase(),
      onPressed: onPressed,
      height: 52,
      borderRadius: 4,
    );
  }

  Widget _buildEventDetailGrid(Event event) {
    final dateText =
        DateFormat('M/d (E) HH:mm', 'ko_KR').format(event.startAt);
    final saleText =
        DateFormat('M/d HH:mm', 'ko_KR').format(event.saleStartAt);
    final priceText = NumberFormat('#,###', 'ko_KR').format(event.price);

    final cards = <_QuickInfoCard>[
      _QuickInfoCard(
        title: 'SCHEDULE',
        value: dateText,
        hint: event.venueName?.isNotEmpty == true
            ? event.venueName!
            : '장소 정보 없음',
        icon: Icons.schedule_outlined,
      ),
      _QuickInfoCard(
        title: 'PRICE',
        value: '$priceText원',
        hint: event.showRemainingSeats ? '잔여 ${event.availableSeats}석' : '~부터',
        icon: Icons.confirmation_number_outlined,
      ),
      _QuickInfoCard(
        title: 'CURATION',
        value: '예산 + 악기 기준',
        hint: '좌석 3개 자동 추천',
        icon: Icons.auto_awesome_outlined,
      ),
      _QuickInfoCard(
        title: 'PREVIEW',
        value: '360° 프리뷰',
        hint: event.isOnSale ? '바로 체험 가능' : '오픈 $saleText',
        icon: Icons.threesixty_outlined,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          // Top row
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _buildGridCell(cards[0])),
                Container(width: 0.5, color: AppTheme.border),
                Expanded(child: _buildGridCell(cards[1])),
              ],
            ),
          ),
          Container(height: 0.5, color: AppTheme.border),
          // Bottom row
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _buildGridCell(cards[2])),
                Container(width: 0.5, color: AppTheme.border),
                Expanded(child: _buildGridCell(cards[3])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell(_QuickInfoCard card) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(card.icon, size: 20, color: AppTheme.sage),
          const SizedBox(height: 10),
          Text(
            card.title,
            style: AppTheme.label(
              fontSize: 9,
              color: AppTheme.sage,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            card.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.sans(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAIQuickConditions(
    BuildContext context,
    Event event, {
    required bool fromLink,
  }) async {
    int quantity = 2;
    const guestOptions = [1, 2, 3, 4, 5];
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

    final result = await showSlideUpSheet<_AIQuickCondition>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final budgetOptions = budgetOptionsForQty(quantity);
            if (!budgetOptions.contains(maxBudget)) {
              maxBudget = budgetOptions.first;
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONDITIONS',
                    style: AppTheme.label(
                      fontSize: 10,
                      color: AppTheme.sage,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fromLink ? '링크 공연 AI 예매 조건' : 'AI 예매 조건',
                    style: AppTheme.serif(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '세 가지만 고르면 바로 자동 배치됩니다.',
                    style: AppTheme.sans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── 인원 ──
                  Text(
                    'GUESTS',
                    style: AppTheme.label(
                      fontSize: 9,
                      color: AppTheme.sage,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: guestOptions.map((n) {
                      final selected = n == quantity;
                      final label = n >= 5 ? '5명+' : '$n명';
                      return ChoiceChip(
                        label: Text(label),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setSheetState(() => quantity = n),
                        labelStyle: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppTheme.onAccent
                              : AppTheme.textSecondary,
                        ),
                        selectedColor: AppTheme.gold,
                        backgroundColor: AppTheme.surface,
                        side: BorderSide(
                          color:
                              selected ? AppTheme.gold : AppTheme.border,
                          width: 0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  // ── 총 예산 ──
                  Text(
                    'BUDGET',
                    style: AppTheme.label(
                      fontSize: 9,
                      color: AppTheme.sage,
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
                        showCheckmark: false,
                        onSelected: (_) =>
                            setSheetState(() => maxBudget = value),
                        labelStyle: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppTheme.onAccent
                              : AppTheme.textSecondary,
                        ),
                        selectedColor: AppTheme.gold,
                        backgroundColor: AppTheme.surface,
                        side: BorderSide(
                          color:
                              selected ? AppTheme.gold : AppTheme.border,
                          width: 0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  // ── 보고 싶은 악기 ──
                  Text(
                    '보고 싶은 악기',
                    style: AppTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.sage,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      '상관없음',
                      '현악',
                      '목관',
                      '금관',
                      '관악',
                      '하프',
                      '그랜드피아노',
                      '밴드'
                    ].map((inst) {
                      final selected = inst == instrument;
                      return ChoiceChip(
                        label: Text(inst),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setSheetState(() => instrument = inst),
                        labelStyle: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppTheme.onAccent
                              : AppTheme.textSecondary,
                        ),
                        selectedColor: AppTheme.gold,
                        backgroundColor: AppTheme.surface,
                        side: BorderSide(
                          color:
                              selected ? AppTheme.gold : AppTheme.border,
                          width: 0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // ── Submit button ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
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
                        style: AppTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onAccent,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
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

// ─── Quick Booking Event Card (Editorial) ───
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Poster with Priority badge ──
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 96,
              height: 132,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: event.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppTheme.cardElevated,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.gold,
                            strokeWidth: 1.5,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _PosterPlaceholder(),
                    )
                  else
                    _PosterPlaceholder(),
                  // Priority badge
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      color: AppTheme.gold,
                      child: Text(
                        'PRIORITY',
                        style: AppTheme.label(
                          fontSize: 8,
                          color: AppTheme.onAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),

          // ── Info ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.category?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      event.category!.toUpperCase(),
                      style: AppTheme.label(
                        fontSize: 9,
                        color: AppTheme.sage,
                      ),
                    ),
                  ),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                _metaLine(Icons.schedule_outlined, dateText),
                if (event.venueName?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  _metaLine(Icons.location_on_outlined, event.venueName!),
                ],
                if (event.showRemainingSeats) ...[
                  const SizedBox(height: 3),
                  _metaLine(
                    Icons.confirmation_number_outlined,
                    '잔여 ${event.availableSeats}석',
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '$priceText원',
                  style: AppTheme.serif(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.isOnSale ? '지금 바로 예매 가능' : '오픈: $saleOpenText',
                  style: AppTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: event.isOnSale
                        ? AppTheme.success
                        : AppTheme.textSecondary,
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
        Icon(icon, size: 13, color: AppTheme.sage),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.sans(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Home Tab (Editorial) ───
class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return CustomScrollView(
      slivers: [
        // ── AppBar (Editorial) ──
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.surface,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              right: 24,
              bottom: 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MELON TICKET',
                        style: AppTheme.label(
                          fontSize: 9,
                          color: AppTheme.sage,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '다른 공연',
                        style: AppTheme.serif(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Editorial badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    'M',
                    style: AppTheme.serif(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onAccent,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Category chips (editorial minimal) ──
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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

        // ── Divider ──
        SliverToBoxAdapter(
          child: Container(height: 0.5, color: AppTheme.border),
        ),

        // ── Editorial promo (simplified) ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.gold,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          'EDITORIAL',
                          style: AppTheme.label(
                            fontSize: 8,
                            color: AppTheme.onAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '모바일 예매 추천',
                        style: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'AI 좌석 추천 + 360° 시야',
                    style: AppTheme.serif(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '좌석 선택 화면에서 구역별 시야를 확인하고\n취소/환불 정책까지 한 번에 확인하세요.',
                    style: AppTheme.sans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Demo button ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: OutlinedButton(
              onPressed: () => context.push('/demo-flow'),
              child: Text(
                '공연등록부터 스캔까지 데모 실행',
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.gold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),

        // ── Section label ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              'ALL EVENTS',
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.sage,
              ),
            ),
          ),
        ),

        // ── Event list ──
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
                        color: AppTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'ERROR',
                        style: AppTheme.label(
                          fontSize: 10,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '공연 정보를 불러올 수 없습니다',
                      style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
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

// ─── Category Chip (Editorial) ───
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  const _CategoryChip({required this.label, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: isSelected ? Colors.transparent : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: isSelected ? AppTheme.gold : AppTheme.border,
          width: isSelected ? 1 : 0.5,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.sans(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ─── Event Card (Editorial horizontal layout) ───
class _EventCard extends StatelessWidget {
  final Event event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
    final priceFormat = NumberFormat('#,###');

    return PressableScale(
      onTap: () => context.push('/event/${event.id}'),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Poster thumbnail ──
            Container(
              width: 100,
              height: 140,
              decoration: BoxDecoration(
                color: AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(2),
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
                        color: AppTheme.cardElevated,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _PosterPlaceholder(),
                    )
                  else
                    _PosterPlaceholder(),
                  // Status badge
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _StatusBadge(event: event),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // ── Info ──
            Expanded(
              child: SizedBox(
                height: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category
                    if (event.category != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          event.category!.toUpperCase(),
                          style: AppTheme.label(
                            fontSize: 9,
                            color: AppTheme.sage,
                          ),
                        ),
                      ),

                    // Title (serif)
                    Text(
                      event.title,
                      style: AppTheme.serif(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Date
                    Text(
                      dateFormat.format(event.startAt),
                      style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),

                    // Venue
                    if (event.venueName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.venueName!,
                        style: AppTheme.sans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const Spacer(),

                    // Price
                    Text(
                      '${priceFormat.format(event.price)}원',
                      style: AppTheme.serif(
                        fontSize: 17,
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
          style: AppTheme.label(
            fontSize: 10,
            color: AppTheme.sage,
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
      label = 'ON SALE';
      bgColor = AppTheme.success;
      fgColor = Colors.white;
    } else if (event.status == EventStatus.soldOut ||
        event.availableSeats == 0) {
      label = 'SOLD OUT';
      bgColor = AppTheme.error;
      fgColor = Colors.white;
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      label = 'UPCOMING';
      bgColor = AppTheme.gold;
      fgColor = AppTheme.onAccent;
    } else {
      label = 'CLOSED';
      bgColor = AppTheme.sage;
      fgColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: bgColor,
      child: Text(
        label,
        style: AppTheme.label(
          fontSize: 8,
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
              color: AppTheme.cardElevated,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'EMPTY',
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.sage,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '등록된 공연이 없습니다',
            style: AppTheme.serif(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Login Required Tab (Editorial) ───
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
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.border, width: 0.5),
                  ),
                  child: Center(
                    child: Text(
                      'LOGIN',
                      style: AppTheme.label(
                        fontSize: 11,
                        color: AppTheme.gold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '로그인이 필요합니다',
                  style: AppTheme.serif(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '티켓을 확인하려면 로그인해주세요',
                  style: AppTheme.sans(
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

// ─── Profile Tab (Editorial) ───
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
              'PROFILE',
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.sage,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '마이페이지',
              style: AppTheme.serif(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),

            // User info card
            if (isLoggedIn)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.gold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          profileInitial,
                          style: AppTheme.serif(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onAccent,
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
                            style: AppTheme.sans(
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
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                'ADMIN',
                                style: AppTheme.label(
                                  fontSize: 9,
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
                icon: Icons.login_outlined,
                title: '로그인',
                subtitle: '계정에 로그인하세요',
                onTap: () => context.push('/login'),
              ),

            const SizedBox(height: 16),

            // Order history
            if (isLoggedIn) ...[
              _MenuItem(
                icon: Icons.receipt_long_outlined,
                title: '주문 내역',
                subtitle: '결제 및 환불 내역 확인',
                onTap: () => context.push('/orders'),
              ),
              const SizedBox(height: 8),
            ],

            // Staff/admin menus
            if (currentUser.value?.isStaff == true) ...[
              _MenuItem(
                icon: Icons.qr_code_scanner_outlined,
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
                onTap: () => launchUrl(
                  Uri.parse('https://melon-ticket-admin.web.app/events/create'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.location_city_outlined,
                title: '공연장 관리',
                subtitle: '좌석배치도 / 3D 시야 업로드',
                onTap: () => launchUrl(
                  Uri.parse('https://melon-ticket-admin.web.app/venues'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.admin_panel_settings_outlined,
                title: '관리자 대시보드',
                subtitle: '공연 및 좌석 관리',
                onTap: () => launchUrl(
                  Uri.parse('https://melon-ticket-admin.web.app'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 16),

            if (isLoggedIn)
              _MenuItem(
                icon: Icons.logout_outlined,
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
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppTheme.error.withValues(alpha: 0.08)
                    : AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                icon,
                color: isDestructive ? AppTheme.error : AppTheme.sage,
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
                    style: AppTheme.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDestructive
                          ? AppTheme.error
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.sans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.sage.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

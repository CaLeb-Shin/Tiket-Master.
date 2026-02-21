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
import 'package:melon_core/data/models/mileage.dart';
import 'package:melon_core/data/models/mileage_history.dart';
import 'package:melon_core/data/repositories/mileage_repository.dart';
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

// ─── Quick Booking Tab (Poster-Centric) ───
class _QuickBookingTab extends ConsumerStatefulWidget {
  final String? focusEventId;
  final VoidCallback onOpenDiscover;

  const _QuickBookingTab({
    required this.focusEventId,
    required this.onOpenDiscover,
  });

  @override
  ConsumerState<_QuickBookingTab> createState() => _QuickBookingTabState();
}

class _QuickBookingTabState extends ConsumerState<_QuickBookingTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  bool _hasAnimated = false;
  bool _detailsExpanded = true;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _triggerSlideUp() {
    if (!_hasAnimated) {
      _hasAnimated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _slideCtrl.forward();
      });
    }
  }

  Event? _selectPrimaryEvent(List<Event> events) {
    if (events.isEmpty) return null;
    final sorted = [...events]..sort((a, b) => a.startAt.compareTo(b.startAt));
    for (final event in sorted) {
      if (event.isOnSale && event.availableSeats > 0) return event;
    }
    return sorted.first;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedFocusId = widget.focusEventId?.trim();
    if (normalizedFocusId != null && normalizedFocusId.isNotEmpty) {
      final focusedAsync = ref.watch(eventStreamProvider(normalizedFocusId));
      return focusedAsync.when(
        data: (event) => _buildContent(event, fromLink: true),
        loading: () => _buildLoading(),
        error: (_, __) => _buildContent(null, fromLink: true),
      );
    }
    final eventsAsync = ref.watch(eventsStreamProvider);
    return eventsAsync.when(
      data: (events) =>
          _buildContent(_selectPrimaryEvent(events), fromLink: false),
      loading: () => _buildLoading(),
      error: (_, __) => _buildContent(null, fromLink: false),
    );
  }

  Widget _buildLoading() {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: CircularProgressIndicator(color: AppTheme.gold),
      ),
    );
  }

  Widget _buildContent(Event? event, {required bool fromLink}) {
    if (event == null) return _buildEmpty(fromLink: fromLink);
    _triggerSlideUp();

    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final dateText =
        DateFormat('M/d (E) HH:mm', 'ko_KR').format(event.startAt);

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Scrollable content ──
          SingleChildScrollView(
            child: Column(
              children: [
                // ═══ Hero Poster ═══
                Container(
                  width: double.infinity,
                  color: const Color(0xFF1A1A1A),
                  child: Stack(
                    children: [
                      // Poster image (전체 표시)
                      if (event.imageUrl != null &&
                          event.imageUrl!.isNotEmpty)
                        Center(
                          child: CachedNetworkImage(
                            imageUrl: event.imageUrl!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            placeholder: (_, __) => AspectRatio(
                              aspectRatio: 3 / 4,
                              child: Container(
                                color: const Color(0xFF1A1A1A),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: AppTheme.gold,
                                    strokeWidth: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => AspectRatio(
                              aspectRatio: 3 / 4,
                              child: Container(color: const Color(0xFF1A1A1A)),
                            ),
                          ),
                        )
                      else
                        AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Container(
                            color: const Color(0xFF1A1A1A),
                            child: Center(
                              child: Text(
                                event.title.isNotEmpty
                                    ? event.title[0].toUpperCase()
                                    : 'M',
                                style: AppTheme.serif(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Top gradient (status bar)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: safeTop + 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.4),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),

                      // Bottom gradient
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35),
                                Colors.black.withValues(alpha: 0.75),
                              ],
                              stops: const [0.0, 0.35, 0.65, 1.0],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),

                      // PRIORITY badge (top-left)
                      Positioned(
                        top: safeTop + 12,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.gold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                fromLink
                                    ? Icons.link_rounded
                                    : Icons.star_rounded,
                                size: 10,
                                color: AppTheme.onAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                fromLink ? 'LINKED' : 'PRIORITY',
                                style: AppTheme.label(
                                  fontSize: 8,
                                  color: AppTheme.onAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Title + date overlay (bottom)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 28,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Category tag
                            if (event.category?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    event.category!,
                                    style: AppTheme.sans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.85),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            // Title
                            Text(
                              event.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.serif(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.2,
                                letterSpacing: -0.3,
                                shadows: AppTheme.textShadowStrong,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Date
                            Text(
                              dateText,
                              style: AppTheme.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Sold out overlay
                      if (event.status == EventStatus.soldOut ||
                          event.availableSeats <= 0)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.6)),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  'SOLD OUT',
                                  style: AppTheme.label(
                                    fontSize: 16,
                                    color:
                                        Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ═══ Content Area (white) ═══
                SlideTransition(
                  position: _slideAnim,
                  child: Container(
                    width: double.infinity,
                    color: AppTheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 3-column info row (DATE | PRICE | VENUE) ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _InfoColumn(
                                    label: 'DATE',
                                    value: DateFormat('M/d (E) HH:mm', 'ko_KR')
                                        .format(event.startAt),
                                  ),
                                ),
                                Container(
                                    width: 0.5,
                                    color: AppTheme.border),
                                Expanded(
                                  child: _buildPriceColumn(event),
                                ),
                                Container(
                                    width: 0.5,
                                    color: AppTheme.border),
                                Expanded(
                                  child: _InfoColumn(
                                    label: 'VENUE',
                                    value: event.venueName ?? '장소 미정',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        Container(
                            height: 0.5,
                            color: AppTheme.border),

                        // ── 할인 정보 ──
                        _buildDiscountInfo(event),

                        // ── Expandable details ──
                        _buildExpandableDetails(event),

                        // ── 공연 상세 보기 full-width button ──
                        PressableScale(
                          onTap: () =>
                              context.push('/event/${event.id}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16),
                            decoration: const BoxDecoration(
                              color: AppTheme.cardElevated,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '공연 상세 보기',
                                        style: AppTheme.sans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '할인 정보 · 출연진 · 유의사항',
                                        style: AppTheme.sans(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppTheme.gold.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 12,
                                      color: AppTheme.gold),
                                ),
                              ],
                            ),
                          ),
                        ),

                        Container(
                            height: 0.5,
                            color: AppTheme.border),

                        // ── Discover link ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                          child: Center(
                            child: TextButton(
                              onPressed: widget.onOpenDiscover,
                              child: Text(
                                '다른 공연 둘러보기',
                                style: AppTheme.sans(
                                  fontSize: 13,
                                  color: AppTheme.sage,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ── 문의 배너 (optional) ──
                        if (event.inquiryInfo != null && event.inquiryInfo!.isNotEmpty)
                          _buildContactBanner(event.inquiryInfo!),

                        // Bottom padding for CTA
                        SizedBox(height: 80 + safeBottom),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ═══ Fixed Bottom CTA ═══
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  top: BorderSide(color: AppTheme.border, width: 0.5),
                ),
              ),
              padding:
                  EdgeInsets.fromLTRB(20, 10, 20, safeBottom + 10),
              child: _buildCTA(event, fromLink: fromLink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCTA(Event event, {required bool fromLink}) {
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
      text: label,
      onPressed: onPressed,
      height: 54,
      borderRadius: 10,
    );
  }

  Widget _buildExpandableDetails(Event event) {
    final dateText =
        DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR').format(event.startAt);

    return Column(
      children: [
        // Tap target
        GestureDetector(
          onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppTheme.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '상세 정보',
                  style: AppTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _detailsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: AppTheme.sage,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable content
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _detailsExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pamphlet carousel
                    if (event.pamphletUrls != null &&
                        event.pamphletUrls!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SizedBox(
                          height: 200,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: event.pamphletUrls!.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final url = event.pamphletUrls![index];
                              return PressableScale(
                                onTap: () => _showFullImage(
                                    context, event.pamphletUrls!, index),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    width: 140,
                                    height: 200,
                                    placeholder: (_, __) => Container(
                                      width: 140,
                                      color: AppTheme.cardElevated,
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      width: 140,
                                      color: AppTheme.cardElevated,
                                      child: const Icon(
                                          Icons.broken_image_rounded,
                                          color: AppTheme.sage),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // Detail rows
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Column(
                        children: [
                          _detailRow('일시', dateText),
                          if (event.venueName?.isNotEmpty == true)
                            _detailRow('장소', event.venueName!),
                          if (event.runningTime != null)
                            _detailRow(
                                '러닝타임', '${event.runningTime}분'),
                          if (event.ageLimit?.isNotEmpty == true)
                            _detailRow('관람등급', event.ageLimit!),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: AppTheme.sans(
                fontSize: 12,
                color: AppTheme.sage,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountInfo(Event event) {
    final policies = event.discountPolicies;
    final legacyDiscount = event.discount;

    final hasPolicies = policies != null && policies.isNotEmpty;
    final hasLegacy =
        legacyDiscount != null && legacyDiscount.isNotEmpty;

    if (!hasPolicies && !hasLegacy) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.gold.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppTheme.gold.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Icon(Icons.local_offer_rounded,
                    size: 11, color: AppTheme.gold.withValues(alpha: 0.7)),
                const SizedBox(width: 5),
                Text(
                  'DISCOUNT',
                  style: AppTheme.label(
                    fontSize: 9,
                    color: AppTheme.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (hasPolicies)
              ...policies.map((p) {
                final pct = (p.discountRate * 100).round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          '$pct%',
                          style: AppTheme.sans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.name,
                          style: AppTheme.sans(
                            fontSize: 11,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (!hasPolicies && hasLegacy)
              Text(
                legacyDiscount,
                style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const _gradeOrder = ['VIP', 'R', 'S', 'A'];

  List<MapEntry<String, int>> _sortedGrades(Map<String, int> grades) {
    return grades.entries.toList()
      ..sort((a, b) {
        final ai = _gradeOrder.indexOf(a.key);
        final bi = _gradeOrder.indexOf(b.key);
        final aIdx = ai == -1 ? _gradeOrder.length : ai;
        final bIdx = bi == -1 ? _gradeOrder.length : bi;
        return aIdx.compareTo(bIdx);
      });
  }

  Widget _buildPriceColumn(Event event) {
    final fmt = NumberFormat('#,###', 'ko_KR');
    final grades = event.priceByGrade;
    final hasGrades = grades != null && grades.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'PRICE',
            style: AppTheme.label(
              fontSize: 9,
              color: AppTheme.sage,
            ),
          ),
          const SizedBox(height: 6),
          if (hasGrades)
            ..._sortedGrades(grades).map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _gradeColor(entry.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${entry.key} ${fmt.format(entry.value)}',
                      style: AppTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              );
            })
          else
            Text(
              '${fmt.format(event.price)}원',
              textAlign: TextAlign.center,
              style: AppTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  Color _gradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'VIP':
        return AppTheme.gold;
      case 'R':
        return const Color(0xFF2D6A4F);
      case 'S':
        return const Color(0xFF3A6B9F);
      case 'A':
        return const Color(0xFFC08B5C);
      default:
        return AppTheme.sage;
    }
  }

  Widget _buildContactBanner(String description) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: AppTheme.gold.withValues(alpha: 0.05),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppTheme.gold.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTheme.sans(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, List<String> urls, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      builder: (ctx) => _FullScreenGallery(
        urls: urls,
        initialIndex: initialIndex,
      ),
    );
  }

  Widget _buildEmpty({required bool fromLink}) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy_outlined,
                  color: AppTheme.sage, size: 44),
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
                onPressed: widget.onOpenDiscover,
                child: const Text('다른 공연 보기'),
              ),
            ],
          ),
        ),
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
    String position = '가운데';
    String instrument = '상관없음';

    budgetOptionsForQty(int qty) {
      final base = event.price * qty;
      return <int>[0, base, (base * 1.4).round(), base * 2];
    }

    // 기본값: "완벽한 공연" (표준가, index 2)
    int maxBudget = budgetOptionsForQty(quantity)[2];

    String budgetStyleName(int value, int qty) {
      if (value <= 0) return 'AI 추천';
      final base = event.price * qty;
      if (value <= base) return '가볍게 즐기기';
      if (value <= (base * 1.4).round()) return '완벽한 공연';
      return '아티스트와 눈맞춤';
    }

    String budgetSubtext(int value, int qty) {
      if (value <= 0) return '최적 배치';
      final fmt = NumberFormat('#,###', 'ko_KR');
      return '~${fmt.format(value)}원';
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
                      shadows: AppTheme.textShadowStrong,
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

                  // ── 예매 인원 ──
                  Text(
                    '예매 인원',
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

                  // ── 관람 스타일 ──
                  Text(
                    '관람 스타일',
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
                    children: budgetOptions.map((value) {
                      final selected = value == maxBudget;
                      final name = budgetStyleName(value, quantity);
                      final sub = budgetSubtext(value, quantity);
                      return ChoiceChip(
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name),
                            Text(
                              sub,
                              style: AppTheme.sans(
                                fontSize: 9,
                                color: selected
                                    ? AppTheme.onAccent
                                        .withValues(alpha: 0.7)
                                    : AppTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
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

                  // ── 선호 좌석 ──
                  Text(
                    '선호 좌석',
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
                      '가운데',
                      '앞쪽',
                      '통로',
                      '상관없음',
                    ].map((pos) {
                      final selected = pos == position;
                      return ChoiceChip(
                        label: Text(pos),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setSheetState(() => position = pos),
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
                          position: position,
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
      'pos': result.position,
      'inst': result.instrument,
    };
    if (result.maxBudget > 0) {
      query['budget'] = '${result.maxBudget}';
    }

    context.push(
        Uri(path: '/seats/${event.id}', queryParameters: query).toString());
  }
}

// ─── Info Column (3-col layout) ───
class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;

  const _InfoColumn({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTheme.label(
              fontSize: 9,
              color: AppTheme.sage,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Full Screen Gallery (PageView swipe) ───
class _FullScreenGallery extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _FullScreenGallery({
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late PageController _pageCtrl;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Swipeable pages
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 3.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.urls[index],
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 1.5,
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white38,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Page indicator
          Positioned(
            top: safeTop + 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentPage + 1} / ${widget.urls.length}',
                  style: AppTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: safeTop + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AIQuickCondition {
  final int quantity;
  final int maxBudget;
  final String position;
  final String instrument;

  const _AIQuickCondition({
    required this.quantity,
    required this.maxBudget,
    required this.position,
    required this.instrument,
  });
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
                          shadows: AppTheme.textShadowStrong,
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
                      shadows: AppTheme.textShadowStrong,
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
                        shadows: AppTheme.textShadow,
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
                        shadows: AppTheme.textShadow,
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
                    shadows: AppTheme.textShadowStrong,
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
                shadows: AppTheme.textShadowStrong,
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

            // Mileage section
            if (isLoggedIn && currentUser.value != null) ...[
              _MileageCard(
                mileage: currentUser.value!.mileage,
                userId: currentUser.value!.id,
                onTapMore: () => context.push('/mileage'),
              ),
              const SizedBox(height: 16),
            ],

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

// ─── Mileage Card (Profile Tab) ─────────────────────────────────
class _MileageCard extends ConsumerWidget {
  final Mileage mileage;
  final String userId;
  final VoidCallback onTapMore;

  const _MileageCard({
    required this.mileage,
    required this.userId,
    required this.onTapMore,
  });

  Color _tierColor(MileageTier tier) {
    switch (tier) {
      case MileageTier.bronze:
        return const Color(0xFFCD7F32);
      case MileageTier.silver:
        return const Color(0xFFC0C0C0);
      case MileageTier.gold:
        return const Color(0xFFC9A84C);
      case MileageTier.platinum:
        return const Color(0xFFE5E4E2);
    }
  }

  IconData _tierIcon(MileageTier tier) {
    switch (tier) {
      case MileageTier.bronze:
        return Icons.circle;
      case MileageTier.silver:
        return Icons.hexagon_outlined;
      case MileageTier.gold:
        return Icons.star_rounded;
      case MileageTier.platinum:
        return Icons.diamond_rounded;
    }
  }

  void _showMileageGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.goldGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.star_rounded,
                        size: 18, color: Color(0xFFFDF3F6)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '마일리지 안내',
                    style: AppTheme.serif(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.border, height: 0.5),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 좌석 업그레이드
                  _guideItem(
                    icon: Icons.event_seat_rounded,
                    title: '좌석 업그레이드',
                    desc: '마일리지를 적립하면 등급이 올라가고,\n높은 등급일수록 좌석 업그레이드 혜택을\n받을 수 있습니다.',
                  ),
                  const SizedBox(height: 20),

                  // 공유 적립
                  _guideItem(
                    icon: Icons.card_giftcard_rounded,
                    title: '공연 공유 적립',
                    desc: '내가 공유한 공연 링크를 통해 다른 사람이\n예매를 완료하면, 추천 마일리지가\n적립됩니다.',
                  ),
                  const SizedBox(height: 20),

                  // 등급 안내
                  _guideItem(
                    icon: Icons.star_outline_rounded,
                    title: '등급 안내',
                    desc: null,
                  ),
                  const SizedBox(height: 10),

                  // Tier table
                  ...MileageTier.values.map((tier) {
                    final color = _tierColor(tier);
                    final isCurrent = tier == mileage.tier;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? color.withValues(alpha: 0.1)
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: isCurrent
                            ? Border.all(
                                color: color.withValues(alpha: 0.4), width: 1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(_tierIcon(tier), size: 16, color: color),
                          const SizedBox(width: 10),
                          Text(
                            tier.displayName,
                            style: AppTheme.sans(
                              fontSize: 13,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                              color: isCurrent ? color : AppTheme.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            tier == MileageTier.bronze
                                ? '0P~'
                                : '${NumberFormat('#,###').format(tier.minPoints)}P~',
                            style: AppTheme.sans(
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '현재',
                                style: AppTheme.sans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Close button
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 12, 24, MediaQuery.of(context).padding.bottom + 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.cardElevated,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    '확인',
                    style: AppTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideItem({
    required IconData icon,
    required String title,
    String? desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: AppTheme.gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (desc != null) ...[
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: AppTheme.sans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tierColor = _tierColor(mileage.tier);
    final nextTier = mileage.tier.next;
    final progress = nextTier != null
        ? (mileage.totalEarned - mileage.tier.minPoints) /
            (nextTier.minPoints - mileage.tier.minPoints)
        : 1.0;
    final remaining =
        nextTier != null ? nextTier.minPoints - mileage.totalEarned : 0;
    final formatter = NumberFormat('#,###');

    final historyAsync = ref.watch(
      mileageHistoryStreamProvider((userId: userId, limit: 10)),
    );

    return GestureDetector(
      onTap: () => _showMileageGuide(context),
      child: Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: balance + tier
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showMileageGuide(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_tierIcon(mileage.tier),
                            size: 12, color: tierColor),
                        const SizedBox(width: 3),
                        Text(
                          mileage.tier.displayName,
                          style: AppTheme.label(
                            fontSize: 9,
                            color: tierColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.help_outline_rounded,
                            size: 12, color: tierColor.withValues(alpha: 0.6)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${formatter.format(mileage.balance)}P',
                  style: AppTheme.serif(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    shadows: AppTheme.textShadowStrong,
                  ),
                ),
              ],
            ),
          ),

          // Progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                if (nextTier != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppTheme.cardElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '다음 등급까지 ${formatter.format(remaining)}P',
                        style: AppTheme.sans(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        nextTier.displayName,
                        style: AppTheme.sans(
                          fontSize: 11,
                          color: _tierColor(nextTier),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    '최고 등급 달성',
                    style: AppTheme.sans(
                      fontSize: 11,
                      color: tierColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Divider(color: AppTheme.border, height: 0.5),

          // Recent history (max 3)
          historyAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      '적립 내역이 없습니다',
                      style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                );
              }
              final displayItems = history.take(3).toList();
              return Column(
                children: [
                  ...displayItems.map((item) => _MileageHistoryRow(item: item)),
                  if (history.length > 3) ...[
                    const Divider(color: AppTheme.border, height: 0.5),
                    InkWell(
                      onTap: onTapMore,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            '전체 내역 보기',
                            style: AppTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    ),
    );
  }
}

class _MileageHistoryRow extends StatelessWidget {
  final MileageHistory item;
  const _MileageHistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isPositive = item.amount > 0;
    final formatter = NumberFormat('#,###');
    final dateFormat = DateFormat('MM.dd');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  item.type.displayName,
                  style: AppTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.reason,
                    style: AppTheme.sans(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isPositive ? '+' : ''}${formatter.format(item.amount)}P',
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isPositive ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            dateFormat.format(item.createdAt),
            style: AppTheme.sans(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

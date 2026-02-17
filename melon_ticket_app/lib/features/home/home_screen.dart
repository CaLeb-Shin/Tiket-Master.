import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/auth_service.dart';

const _bgTop = Color(0xFFF6FBFF);
const _bgBottom = Color(0xFFEAF2FB);
const _heroBlue = Color(0xFF0D3E67);
const _heroBlueSoft = Color(0xFF2F6FB2);
const _cardBorder = Color(0xFFD7DFE8);
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF5B6472);
const _textMuted = Color(0xFF8A94A3);
const _success = Color(0xFF027A48);
const _danger = Color(0xFFB42318);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final currentUser = ref.watch(currentUserProvider);
    final eventsAsync = ref.watch(eventsStreamProvider);
    final isLoggedIn = authState.value != null;
    final isAdmin = currentUser.valueOrNull?.isAdmin == true;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bgTop, _bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            const _BackdropShapes(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      width >= 900 ? 40 : 20,
                      16,
                      width >= 900 ? 40 : 20,
                      40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TopBar(
                          isLoggedIn: isLoggedIn,
                          isAdmin: isAdmin,
                        ),
                        const SizedBox(height: 18),
                        _HeroSection(
                          wide: width >= 980,
                          isLoggedIn: isLoggedIn,
                        ),
                        const SizedBox(height: 16),
                        _FeatureRow(wide: width >= 980),
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Text(
                              '추천 공연',
                              style: GoogleFonts.notoSans(
                                color: _textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: _cardBorder),
                              ),
                              child: Text(
                                'AI 좌석추천 + 360° 뷰',
                                style: GoogleFonts.notoSans(
                                  color: _heroBlue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '지금 예매 가능한 공연을 확인하고 모바일 티켓까지 바로 발급받으세요.',
                          style: GoogleFonts.notoSans(
                            color: _textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _EventGrid(eventsAsync: eventsAsync, width: width),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackdropShapes extends StatelessWidget {
  const _BackdropShapes();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -110,
            left: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFBFD7EE).withValues(alpha: 0.32),
              ),
            ),
          ),
          Positioned(
            top: 220,
            right: -120,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFCFE3F8).withValues(alpha: 0.4),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: 80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE4EEF9).withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool isLoggedIn;
  final bool isAdmin;

  const _TopBar({
    required this.isLoggedIn,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [_heroBlue, _heroBlueSoft],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _heroBlue.withValues(alpha: 0.2),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.confirmation_number_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '멜론티켓',
          style: GoogleFonts.notoSans(
            color: _textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const Spacer(),
        if (isAdmin)
          _TopButton(
            label: '관리자',
            filled: false,
            onTap: () => context.go('/admin'),
          ),
        if (isAdmin) const SizedBox(width: 8),
        _TopButton(
          label: isLoggedIn ? '내 티켓' : '로그인',
          filled: true,
          onTap: () =>
              isLoggedIn ? context.go('/tickets') : context.push('/login'),
        ),
      ],
    );
  }
}

class _TopButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _TopButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: _heroBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.notoSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _heroBlue,
                side: const BorderSide(color: _heroBlue, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.notoSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final bool wide;
  final bool isLoggedIn;

  const _HeroSection({
    required this.wide,
    required this.isLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    final content = [
      Expanded(
        flex: wide ? 5 : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                'NEW PREMIUM MOBILE TICKETING',
                style: GoogleFonts.robotoMono(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '공연 예매부터\n모바일 티켓 발권까지\n한 번에',
              style: GoogleFonts.notoSans(
                color: Colors.white,
                fontSize: wide ? 44 : 34,
                height: 1.15,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AI 좌석 추천, 360° 시야 확인, 취소/환불 정책 안내까지\n실전 예매 흐름으로 바로 이어집니다.',
              style: GoogleFonts.notoSans(
                color: const Color(0xFFD3E4F5),
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroChip(label: 'AI 추천 좌석'),
                _HeroChip(label: '360° 시야'),
                _HeroChip(label: '모바일 티켓'),
                _HeroChip(label: '환불 정책 내장'),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _heroBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '공연 둘러보기',
                    style: GoogleFonts.notoSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => isLoggedIn
                      ? context.go('/tickets')
                      : context.push('/login'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '내 티켓 열기',
                    style: GoogleFonts.notoSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (wide) const SizedBox(width: 18),
      Expanded(
        flex: wide ? 4 : 0,
        child: const _TicketMockup(),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [_heroBlue, _heroBlueSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _heroBlue.withValues(alpha: 0.25),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: content)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content.first,
                const SizedBox(height: 16),
                content.last,
              ],
            ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2A5D90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSans(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TicketMockup extends StatelessWidget {
  const _TicketMockup();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCFE0F0), width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '2026년 2월 1일 (일) · 스마트티켓 1매',
              style: GoogleFonts.notoSans(
                color: _heroBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stationText('서울', '06:37'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: _heroBlueSoft,
                  size: 22,
                ),
              ),
              Expanded(
                child: _stationText('영등포', '06:46', alignEnd: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: _cardBorder, height: 1),
          const SizedBox(height: 10),
          _mockRow('좌석', 'A구역 1층 12열 8번'),
          _mockRow('승차권번호', '82102-0130-11856-68'),
          _mockRow('결제금액', '132,000원', emphasize: true),
        ],
      ),
    );
  }

  Widget _stationText(String title, String time, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.notoSans(
            color: _textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        Text(
          time,
          style: GoogleFonts.robotoMono(
            color: _textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _mockRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.notoSans(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.notoSans(
              color: _textPrimary,
              fontSize: emphasize ? 16 : 12,
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final bool wide;

  const _FeatureRow({required this.wide});

  @override
  Widget build(BuildContext context) {
    const items = [
      _FeatureCard(
        icon: Icons.auto_awesome_rounded,
        title: 'AI 좌석 추천',
        desc: '예산·시야·선호 구역을 반영해 최적 좌석을 자동 제안합니다.',
      ),
      _FeatureCard(
        icon: Icons.threesixty_rounded,
        title: '360° 시야 확인',
        desc: 'Insta360 촬영 이미지를 좌석 단위로 연결해 실제 뷰를 제공합니다.',
      ),
      _FeatureCard(
        icon: Icons.receipt_long_rounded,
        title: '모바일 티켓/환불',
        desc: '발권, 취소, 환불 정책 안내까지 한 흐름에서 안전하게 처리합니다.',
      ),
    ];

    if (wide) {
      return Row(
        children: [
          Expanded(child: items[0]),
          const SizedBox(width: 10),
          Expanded(child: items[1]),
          const SizedBox(width: 10),
          Expanded(child: items[2]),
        ],
      );
    }

    return const Column(
      children: [
        _FeatureCard(
          icon: Icons.auto_awesome_rounded,
          title: 'AI 좌석 추천',
          desc: '예산·시야·선호 구역을 반영해 최적 좌석을 자동 제안합니다.',
        ),
        SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.threesixty_rounded,
          title: '360° 시야 확인',
          desc: 'Insta360 촬영 이미지를 좌석 단위로 연결해 실제 뷰를 제공합니다.',
        ),
        SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.receipt_long_rounded,
          title: '모바일 티켓/환불',
          desc: '발권, 취소, 환불 정책 안내까지 한 흐름에서 안전하게 처리합니다.',
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F2FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _heroBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSans(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.notoSans(
                    color: _textSecondary,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
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

class _EventGrid extends StatelessWidget {
  final AsyncValue<List<Event>> eventsAsync;
  final double width;

  const _EventGrid({required this.eventsAsync, required this.width});

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = width >= 1320
        ? 3
        : width >= 900
            ? 2
            : 1;

    return eventsAsync.when(
      loading: () => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: crossAxisCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: width >= 900 ? 1.42 : 1.26,
        ),
        itemBuilder: (_, __) => const _EventCardSkeleton(),
      ),
      error: (error, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        child: Text(
          '공연 목록을 불러오지 못했습니다.\n$error',
          style: GoogleFonts.notoSans(color: _danger, fontSize: 13),
        ),
      ),
      data: (events) {
        if (events.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.event_busy_rounded,
                  size: 38,
                  color: _textMuted,
                ),
                const SizedBox(height: 10),
                Text(
                  '등록된 공연이 없습니다',
                  style: GoogleFonts.notoSans(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        final preview = events.take(6).toList(growable: false);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: preview.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: width >= 900 ? 1.42 : 1.24,
          ),
          itemBuilder: (context, index) => _EventCard(event: preview[index]),
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final startText =
        DateFormat('M월 d일 (E) HH:mm', 'ko_KR').format(event.startAt);
    final priceText = NumberFormat('#,###', 'ko_KR').format(event.price);
    final status = _statusMeta(event);

    return InkWell(
      onTap: () => context.push('/event/${event.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                child: event.imageUrl != null && event.imageUrl!.isNotEmpty
                    ? Image.network(
                        event.imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _PosterFallback(event: event),
                      )
                    : _PosterFallback(event: event),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSans(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: status.$3,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status.$1,
                          style: GoogleFonts.notoSans(
                            color: status.$2,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    startText,
                    style: GoogleFonts.robotoMono(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.venueName?.isNotEmpty == true
                        ? event.venueName!
                        : '공연장 정보 없음',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSans(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '$priceText원~',
                        style: GoogleFonts.notoSans(
                          color: _heroBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _statusMeta(Event event) {
    if (event.status == EventStatus.soldOut || event.availableSeats <= 0) {
      return ('매진', _danger, const Color(0xFFFEE2E2));
    }
    if (event.isOnSale) {
      return ('예매중', _success, const Color(0xFFD1FAE5));
    }
    if (DateTime.now().isBefore(event.saleStartAt)) {
      return (
        '예매예정',
        const Color(0xFF1D4ED8),
        const Color(0xFFDBEAFE),
      );
    }
    return ('종료', _textMuted, const Color(0xFFF1F5F9));
  }
}

class _PosterFallback extends StatelessWidget {
  final Event event;

  const _PosterFallback({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A4F7C), Color(0xFF3D7DB8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                event.category ?? 'PERFORMANCE',
                style: GoogleFonts.robotoMono(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSans(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCardSkeleton extends StatelessWidget {
  const _EventCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _heroBlueSoft),
      ),
    );
  }
}

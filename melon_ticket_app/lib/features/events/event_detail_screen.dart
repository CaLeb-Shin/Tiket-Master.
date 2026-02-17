import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/review_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/services/auth_service.dart';
import 'review_section.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(eventId));
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: eventAsync.when(
        data: (event) {
          if (event == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy_rounded,
                      size: 48, color: AppTheme.gold.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text('공연을 찾을 수 없습니다',
                      style:
                          GoogleFonts.notoSans(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return _DetailBody(
            event: event,
            isLoggedIn: authState.value != null,
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
        error: (e, _) => Center(
          child: Text('오류가 발생했습니다',
              style: GoogleFonts.notoSans(color: AppTheme.error)),
        ),
      ),
    );
  }
}

// =============================================================================
// Detail Body
// =============================================================================

class _DetailBody extends StatelessWidget {
  final Event event;
  final bool isLoggedIn;
  const _DetailBody({required this.event, required this.isLoggedIn});


  @override
  Widget build(BuildContext context) {
    final canBuy = event.isOnSale && event.availableSeats > 0;
    final priceFormat = NumberFormat('#,###');

    return Column(
      children: [
        // ─── App Bar ───
        _AppBar(event: event),

        // ─── Scrollable Content ───
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Poster + Title + Status ──
                _PosterSection(event: event),

                const SizedBox(height: 20),

                // ── 공연 정보 테이블 ──
                _InfoTable(event: event),

                // ── 가격 정보 ──
                _PriceSection(event: event, priceFormat: priceFormat),

                // ── 혜택 배너 ──
                _BenefitBanner(),

                // ── 공연 소개 ──
                if (event.description.isNotEmpty)
                  _ContentSection(title: '공연 소개', content: event.description),

                // ── 출연진 ──
                if (event.cast != null && event.cast!.isNotEmpty)
                  _ContentSection(title: '출연진', content: event.cast!),

                // ── 주최/기획 ──
                if (event.organizer != null || event.planner != null)
                  _ContentSection(
                    title: '주최/기획',
                    content: [
                      if (event.organizer != null && event.organizer!.isNotEmpty)
                        '주최: ${event.organizer}',
                      if (event.planner != null && event.planner!.isNotEmpty)
                        '기획: ${event.planner}',
                    ].join('\n'),
                  ),

                // ── 할인 정책 (놀티켓 스타일) ──
                if (event.discountPolicies != null &&
                    event.discountPolicies!.isNotEmpty)
                  _DiscountPoliciesSection(
                    policies: event.discountPolicies!,
                    basePrice: event.price,
                  )
                else if (event.discount != null && event.discount!.isNotEmpty)
                  _ContentSection(title: '할인정보', content: event.discount!),

                // ── 유의사항 ──
                if (event.notice != null && event.notice!.isNotEmpty)
                  _ContentSection(title: '예매 유의사항', content: event.notice!),

                // ── 관람 후기 ──
                ReviewSection(eventId: event.id),

                const SizedBox(height: 120),
              ],
            ),
          ),
        ),

        // ─── Bottom CTA ───
        _BottomCTA(
          event: event,
          canBuy: canBuy,
          isLoggedIn: isLoggedIn,
          priceFormat: priceFormat,
        ),
      ],
    );
  }
}

// =============================================================================
// App Bar
// =============================================================================

class _AppBar extends StatelessWidget {
  final Event event;
  const _AppBar({required this.event});

  @override
  Widget build(BuildContext context) {
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
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textPrimary, size: 20),
          ),
          Expanded(
            child: Text(
              event.title,
              style: GoogleFonts.notoSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(event: event),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _shareEvent(context, event),
            icon: const Icon(Icons.share_rounded,
                color: AppTheme.textSecondary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _shareEvent(BuildContext context, Event event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShareSheet(event: event),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Event event;
  const _StatusChip({required this.event});

  @override
  Widget build(BuildContext context) {
    String text;
    Color bgColor;
    Color fgColor;

    if (event.status == EventStatus.soldOut || event.availableSeats == 0) {
      text = '매진';
      bgColor = AppTheme.error.withOpacity(0.15);
      fgColor = AppTheme.error;
    } else if (event.isOnSale) {
      text = '예매중';
      bgColor = AppTheme.success.withOpacity(0.15);
      fgColor = AppTheme.success;
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      text = '예매예정';
      bgColor = AppTheme.goldSubtle;
      fgColor = AppTheme.gold;
    } else {
      text = '종료';
      bgColor = AppTheme.textTertiary.withOpacity(0.15);
      fgColor = AppTheme.textTertiary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }
}

// =============================================================================
// Poster Section
// =============================================================================

class _PosterSection extends StatelessWidget {
  final Event event;
  const _PosterSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E)', 'ko_KR');

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 포스터 이미지 ──
          Container(
            width: 140,
            height: 196,
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: (event.imageUrl != null && event.imageUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: event.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppTheme.card,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _posterPlaceholder(),
                  )
                : _posterPlaceholder(),
          ),
          const SizedBox(width: 18),

          // ── 기본 정보 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 카테고리
                if (event.category != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      event.category!,
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.gold,
                      ),
                    ),
                  ),

                // 제목
                Text(
                  event.title,
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // 날짜
                _MiniInfo(
                  icon: Icons.calendar_today_rounded,
                  text: dateFormat.format(event.startAt),
                ),
                const SizedBox(height: 6),

                // 장소
                if (event.venueName != null) ...[
                  _MiniInfo(
                    icon: Icons.location_on_outlined,
                    text: event.venueName!,
                  ),
                  const SizedBox(height: 6),
                ],

                // 잔여좌석
                _MiniInfo(
                  icon: Icons.event_seat_outlined,
                  text: '잔여 ${event.availableSeats}석',
                  color: event.availableSeats > 0
                      ? AppTheme.success
                      : AppTheme.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      color: AppTheme.card,
      child: Center(
        child: ShaderMask(
          shaderCallback: (b) => AppTheme.goldGradient.createShader(b),
          child: const Icon(Icons.music_note_rounded,
              size: 40, color: Colors.white),
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _MiniInfo({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? AppTheme.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.notoSans(
              fontSize: 13,
              color: color ?? AppTheme.textSecondary,
              fontWeight: color != null ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Info Table (NOL 인터파크 스타일 테이블)
// =============================================================================

class _InfoTable extends StatelessWidget {
  final Event event;
  const _InfoTable({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Column(
          children: [
            _TableRow(label: '장소', value: event.venueName ?? '-'),
            _tableDivider(),
            _TableRow(
              label: '공연기간',
              value: dateFormat.format(event.startAt),
            ),
            if (event.runningTime != null) ...[
              _tableDivider(),
              _TableRow(
                label: '공연시간',
                value: '${event.runningTime}분',
              ),
            ],
            if (event.ageLimit != null) ...[
              _tableDivider(),
              _TableRow(label: '관람연령', value: event.ageLimit!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tableDivider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.border,
    );
  }
}

class _TableRow extends StatelessWidget {
  final String label;
  final String value;
  const _TableRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.notoSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Price Section (등급별 가격)
// =============================================================================

class _PriceSection extends StatelessWidget {
  final Event event;
  final NumberFormat priceFormat;
  const _PriceSection({required this.event, required this.priceFormat});

  @override
  Widget build(BuildContext context) {
    final grades = event.priceByGrade;
    final hasGrades = grades != null && grades.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      '가격',
                      style: GoogleFonts.notoSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                  if (!hasGrades)
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

            // 등급별 가격 리스트
            if (hasGrades)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  children: grades.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          // 등급 뱃지
                          Container(
                            width: 44,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _gradeColor(entry.key).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${entry.key}석',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _gradeColor(entry.key),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${priceFormat.format(entry.value)}원',
                            style: GoogleFonts.notoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Color _gradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'VIP':
        return AppTheme.gold;
      case 'R':
        return const Color(0xFF30D158);
      case 'S':
        return const Color(0xFF0A84FF);
      case 'A':
        return const Color(0xFFFF9F0A);
      case 'B':
        return AppTheme.textSecondary;
      default:
        return AppTheme.textSecondary;
    }
  }
}

// =============================================================================
// Benefit Banner
// =============================================================================

class _BenefitBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.goldSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.gold.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.local_offer_rounded,
                  size: 14, color: Color(0xFFFDF3F6)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 좌석 추천 · 360° 시야 보기',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
                  Text(
                    '모바일티켓 발급 후 공연 24시간/3시간 전 취소 정책이 적용됩니다',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      color: AppTheme.gold.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Content Section (설명, 출연진, 유의사항)
// =============================================================================

class _ContentSection extends StatelessWidget {
  final String title;
  final String content;
  const _ContentSection({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 구분선
          Container(height: 0.5, color: AppTheme.border),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: GoogleFonts.notoSans(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 할인 정책 섹션 (놀티켓 스타일) ───
class _DiscountPoliciesSection extends StatelessWidget {
  final List<dynamic> policies;
  final int basePrice;

  const _DiscountPoliciesSection({
    required this.policies,
    required this.basePrice,
  });

  @override
  Widget build(BuildContext context) {
    final priceFormat = NumberFormat('#,###');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: AppTheme.border),
          const SizedBox(height: 20),
          Text(
            '할인 정책',
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 일반가 (기본)
          _DiscountTile(
            name: '일반',
            price: '${priceFormat.format(basePrice)}원',
            isBase: true,
          ),

          // 할인 정책 카드
          ...policies.map((p) {
            final name = p.name as String;
            final rate = p.discountRate as double;
            final discounted = p.discountedPrice(basePrice) as int;
            final desc = p.description as String?;
            final minQty = p.minQuantity as int;
            final type = p.type as String;

            return _DiscountTile(
              name: name,
              price: '${priceFormat.format(discounted)}원',
              description: desc ??
                  (type == 'bulk'
                      ? '$minQty매 이상만 예매 가능. 전체취소만 가능.'
                      : null),
              discountRate: '${(rate * 100).toInt()}%',
              originalPrice: '${priceFormat.format(basePrice)}원',
            );
          }),
        ],
      ),
    );
  }
}

class _DiscountTile extends StatelessWidget {
  final String name;
  final String price;
  final bool isBase;
  final String? description;
  final String? discountRate;
  final String? originalPrice;

  const _DiscountTile({
    required this.name,
    required this.price,
    this.isBase = false,
    this.description,
    this.discountRate,
    this.originalPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isBase ? AppTheme.cardElevated : AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 이름 + 할인율
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (discountRate != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          discountRate!,
                          style: GoogleFonts.notoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                    Text(
                      name,
                      style: GoogleFonts.notoSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 가격
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (originalPrice != null && !isBase)
                    Text(
                      originalPrice!,
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    price,
                    style: GoogleFonts.notoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              style: GoogleFonts.notoSans(
                fontSize: 11,
                color: AppTheme.textTertiary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Bottom CTA
// =============================================================================

class _BottomCTA extends StatelessWidget {
  final Event event;
  final bool canBuy;
  final bool isLoggedIn;
  final NumberFormat priceFormat;

  const _BottomCTA({
    required this.event,
    required this.canBuy,
    required this.isLoggedIn,
    required this.priceFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: canBuy
          ? Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (isLoggedIn) {
                      context.push('/seats/${event.id}');
                    } else {
                      context.push('/login');
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      isLoggedIn ? '예매하기' : '로그인 후 예매',
                      style: GoogleFonts.notoSans(
                        color: const Color(0xFFFDF3F6),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  event.availableSeats == 0 ? '매진' : '판매 종료',
                  style: GoogleFonts.notoSans(
                    color: AppTheme.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
    );
  }
}

// ─── 공유 시트 (네이버 쇼핑 카드 스타일) ───
class _ShareSheet extends ConsumerWidget {
  final Event event;
  const _ShareSheet({required this.event});

  String get _shareUrl {
    final origin = Uri.base.origin;
    return origin.isNotEmpty
        ? '$origin/event/${event.id}'
        : 'https://melonticket-web-20260216.vercel.app/event/${event.id}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('yyyy년 M월 d일 (E) a h시 mm분', 'ko_KR');
    final ratingAsync = ref.watch(eventRatingProvider(event.id));
    final reviewsAsync = ref.watch(eventReviewsProvider(event.id));
    final hasDiscount = event.discount != null && event.discount!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 드래그 핸들 ──
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── 헤더 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Row(
              children: [
                const Icon(Icons.share_rounded,
                    size: 18, color: AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  '공연 공유하기',
                  style: GoogleFonts.notoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // ── 미리보기 카드 ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 포스터 이미지
                if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: event.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: AppTheme.cardElevated,
                        child: const Center(
                          child: Icon(Icons.image_rounded,
                              size: 40, color: AppTheme.textTertiary),
                        ),
                      ),
                    ),
                  )
                else
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.gold.withOpacity(0.15),
                            AppTheme.surface,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_note_rounded,
                                size: 36, color: AppTheme.gold),
                            const SizedBox(height: 6),
                            Text(
                              '멜론티켓',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 공연 정보
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 장소 태그
                      if (event.venueName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.gold.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event.venueName!,
                              style: GoogleFonts.notoSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.gold,
                              ),
                            ),
                          ),
                        ),

                      // 공연명
                      Text(
                        event.title,
                        style: GoogleFonts.notoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 8),

                      // 가격 정보
                      if (hasDiscount) ...[
                        Text(
                          '${priceFormat.format(event.price)}원',
                          style: GoogleFonts.notoSans(
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              event.discount!,
                              style: GoogleFonts.notoSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.error,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${priceFormat.format(event.price)}원',
                              style: GoogleFonts.notoSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ] else
                        Text(
                          '${priceFormat.format(event.price)}원',
                          style: GoogleFonts.notoSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),

                      const SizedBox(height: 8),

                      // 별점 + 리뷰 수
                      ratingAsync.when(
                        data: (rating) {
                          if (rating <= 0) return const SizedBox.shrink();
                          final reviewCount = reviewsAsync.valueOrNull?.length ?? 0;
                          return Row(
                            children: [
                              ...List.generate(5, (i) {
                                if (i < rating.floor()) {
                                  return const Icon(Icons.star_rounded,
                                      size: 14, color: AppTheme.gold);
                                } else if (i < rating.ceil() &&
                                    rating - rating.floor() >= 0.5) {
                                  return const Icon(Icons.star_half_rounded,
                                      size: 14, color: AppTheme.gold);
                                }
                                return Icon(Icons.star_outline_rounded,
                                    size: 14,
                                    color: AppTheme.textTertiary.withOpacity(0.4));
                              }),
                              const SizedBox(width: 4),
                              Text(
                                rating.toStringAsFixed(1),
                                style: GoogleFonts.notoSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$reviewCount개 리뷰',
                                style: GoogleFonts.notoSans(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 10),

                      // 일시 정보
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 13,
                              color: AppTheme.textTertiary.withOpacity(0.7)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              dateFormat.format(event.startAt),
                              style: GoogleFonts.notoSans(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 공연 보러가기 버튼
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.gold.withOpacity(0.3)),
                        ),
                        child: Center(
                          child: Text(
                            '공연 보러가기',
                            style: GoogleFonts.notoSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 멜론티켓 브랜딩
                      Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              gradient: AppTheme.goldGradient,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: Icon(Icons.music_note_rounded,
                                  size: 11, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '멜론티켓',
                            style: GoogleFonts.notoSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── URL 복사 버튼 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _shareUrl));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('링크가 복사되었습니다'),
                        ),
                      ],
                    ),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppTheme.goldGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'URL 복사하기',
                      style: GoogleFonts.notoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── URL 미리보기 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _shareUrl,
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

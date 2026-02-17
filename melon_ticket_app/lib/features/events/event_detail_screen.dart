import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../app/theme.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/models/event.dart';
import '../../services/auth_service.dart';
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

                // ── 할인정보 ──
                if (event.discount != null && event.discount!.isNotEmpty)
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
    final url = Uri.base.origin.isNotEmpty
        ? '${Uri.base.origin}/event/${event.id}'
        : 'https://melonticket-web-20260216.vercel.app/event/${event.id}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('공유 링크가 복사되었습니다\n$url'),
        duration: const Duration(seconds: 2),
      ),
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

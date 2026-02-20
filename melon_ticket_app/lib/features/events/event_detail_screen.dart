import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/widgets/premium_effects.dart';
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
                      size: 48, color: AppTheme.sage.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('공연을 찾을 수 없습니다',
                      style: AppTheme.sans(color: AppTheme.textSecondary)),
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
              style: AppTheme.sans(color: AppTheme.error)),
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

    return Stack(
      children: [
        // ─── Scrollable Content ───
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero Poster Section ──
              _HeroPosterSection(event: event),

              // ── Info Row (3-column) ──
              _InfoRow(event: event),

              // ── Admission (가격 정보) ──
              _AdmissionSection(event: event, priceFormat: priceFormat),

              // ── Performance Details ──
              _PerformanceDetailsSection(event: event),

              // ── 공연 소개 ──
              if (event.description.isNotEmpty)
                _EditorialContentSection(
                    title: 'About', content: event.description),

              // ── 출연진 ──
              if (event.cast != null && event.cast!.isNotEmpty)
                _EditorialContentSection(title: '출연진', content: event.cast!),

              // ── 주최/기획 ──
              if (event.organizer != null || event.planner != null)
                _EditorialContentSection(
                  title: '주최/기획',
                  content: [
                    if (event.organizer != null && event.organizer!.isNotEmpty)
                      '주최: ${event.organizer}',
                    if (event.planner != null && event.planner!.isNotEmpty)
                      '기획: ${event.planner}',
                  ].join('\n'),
                ),

              // ── 할인 정책 (항상 표시) ──
              if (event.discountPolicies != null &&
                  event.discountPolicies!.isNotEmpty)
                _DiscountSection(
                  policies: event.discountPolicies!,
                  event: event,
                )
              else if (event.discount != null && event.discount!.isNotEmpty)
                _ExpandablePolicy(
                  title: '할인 정책',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Text(
                      event.discount!,
                      style: AppTheme.sans(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.7,
                      ),
                    ),
                  ),
                ),

              // ── 유의사항 (Notice with accent border) ──
              if (event.notice != null && event.notice!.isNotEmpty)
                _NoticeSection(notice: event.notice!),

              // ── 관람 후기 ──
              ReviewSection(eventId: event.id),

              const SizedBox(height: 120),
            ],
          ),
        ),

        // ─── Floating Header ───
        _FloatingHeader(event: event),

        // ─── Bottom CTA ───
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomCTA(
            event: event,
            canBuy: canBuy,
            isLoggedIn: isLoggedIn,
            priceFormat: priceFormat,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Floating Header (overlaid on hero)
// =============================================================================

class _FloatingHeader extends StatelessWidget {
  final Event event;
  const _FloatingHeader({required this.event});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          left: 4,
          right: 8,
          bottom: 8,
        ),
        decoration: const BoxDecoration(
          gradient: AppTheme.topOverlay,
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
                  color: AppTheme.textPrimary, size: 18),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _shareEvent(context, event),
              icon: const Icon(Icons.ios_share_outlined,
                  color: AppTheme.textPrimary, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () {
                // favorite placeholder
              },
              icon: const Icon(Icons.favorite_border_rounded,
                  color: AppTheme.textPrimary, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  void _shareEvent(BuildContext context, Event event) {
    showSlideUpSheet(
      context: context,
      builder: (_) => _ShareSheet(event: event),
    );
  }
}

// =============================================================================
// Hero Poster Section (full-width, 70vh, ivory fade)
// =============================================================================

class _HeroPosterSection extends StatelessWidget {
  final Event event;
  const _HeroPosterSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final heroHeight = screenHeight * 0.7;

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background poster image ──
          if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: event.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: AppTheme.cardElevated,
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
              errorWidget: (_, __, ___) => _heroPosterPlaceholder(),
            )
          else
            _heroPosterPlaceholder(),

          // ── Ivory fade overlay at bottom ──
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.posterOverlay),
            ),
          ),

          // ── Floating title at bottom of poster ──
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // NOW BOOKING label with dot
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: event.isOnSale
                            ? AppTheme.success
                            : AppTheme.sage,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusLabel(event),
                      style: AppTheme.label(
                        fontSize: 10,
                        color: AppTheme.sage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Large serif title
                Text(
                  event.title,
                  style: AppTheme.serif(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.15,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Subtitle (category or venue) in sage uppercase
                if (event.category != null || event.venueName != null)
                  Text(
                    (event.category ?? event.venueName ?? '').toUpperCase(),
                    style: AppTheme.label(
                      fontSize: 11,
                      color: AppTheme.sage,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(Event event) {
    if (event.status == EventStatus.soldOut || event.availableSeats == 0) {
      return 'SOLD OUT';
    } else if (event.isOnSale) {
      return 'NOW BOOKING';
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      return 'COMING SOON';
    } else {
      return 'ENDED';
    }
  }

  Widget _heroPosterPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.cardElevated,
            AppTheme.sage.withValues(alpha: 0.08),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded,
            size: 64, color: AppTheme.sage.withValues(alpha: 0.3)),
      ),
    );
  }
}

// =============================================================================
// Info Row (3-column grid with vertical dividers)
// =============================================================================

class _InfoRow extends StatelessWidget {
  final Event event;
  const _InfoRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
    final timeFormat = DateFormat('HH:mm', 'ko_KR');

    String statusText;
    if (event.status == EventStatus.soldOut || event.availableSeats == 0) {
      statusText = '매진';
    } else if (event.isOnSale) {
      statusText = event.showRemainingSeats
          ? '잔여 ${event.availableSeats}석'
          : '예매중';
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      statusText = '예매예정';
    } else {
      statusText = '종료';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 0.5),
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Date column
            Expanded(
              child: _InfoColumn(
                label: 'DATE',
                value: dateFormat.format(event.startAt),
                subValue: timeFormat.format(event.startAt),
              ),
            ),
            // Divider
            Container(
              width: 0.5,
              color: AppTheme.sage.withValues(alpha: 0.3),
            ),
            // Location column
            Expanded(
              child: _InfoColumn(
                label: 'LOCATION',
                value: event.venueName ?? '-',
              ),
            ),
            // Divider
            Container(
              width: 0.5,
              color: AppTheme.sage.withValues(alpha: 0.3),
            ),
            // Status column
            Expanded(
              child: _InfoColumn(
                label: 'STATUS',
                value: statusText,
                valueColor: event.isOnSale && event.availableSeats > 0
                    ? AppTheme.success
                    : (event.availableSeats == 0
                        ? AppTheme.error
                        : AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;

  const _InfoColumn({
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTheme.label(fontSize: 9, color: AppTheme.sage),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue!,
              style: AppTheme.sans(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Admission Section (Price tiers - editorial minimal rows)
// =============================================================================

class _AdmissionSection extends StatelessWidget {
  final Event event;
  final NumberFormat priceFormat;
  const _AdmissionSection({required this.event, required this.priceFormat});

  @override
  Widget build(BuildContext context) {
    final grades = event.priceByGrade;
    final hasGrades = grades != null && grades.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section heading - italic serif
          Text(
            'Admission',
            style: AppTheme.serif(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          if (hasGrades)
            ..._sortedGrades(grades).map((entry) {
              return _AdmissionRow(
                grade: entry.key,
                price: '${priceFormat.format(entry.value)}원',
                color: _gradeColor(entry.key),
              );
            })
          else
            _AdmissionRow(
              grade: '전석',
              price: '${priceFormat.format(event.price)}원',
              color: AppTheme.gold,
            ),
        ],
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
      case 'B':
        return AppTheme.sage;
      default:
        return AppTheme.sage;
    }
  }
}

class _AdmissionRow extends StatelessWidget {
  final String grade;
  final String price;
  final Color color;
  const _AdmissionRow(
      {required this.grade, required this.price, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Colored dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // Grade name
          Text(
            '${grade}석',
            style: AppTheme.sans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          // Price
          Text(
            price,
            style: AppTheme.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Performance Details Section (grid: label + value)
// =============================================================================

class _PerformanceDetailsSection extends StatelessWidget {
  final Event event;
  const _PerformanceDetailsSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR');
    final details = <_DetailItem>[];

    details.add(_DetailItem('공연일시', dateFormat.format(event.startAt)));
    if (event.venueName != null) {
      details.add(_DetailItem('공연장', event.venueName!));
    }
    if (event.runningTime != null) {
      details.add(_DetailItem('공연시간', '${event.runningTime}분'));
    }
    if (event.ageLimit != null) {
      details.add(_DetailItem('관람등급', event.ageLimit!));
    }
    if (event.cast != null && event.cast!.isNotEmpty) {
      details.add(_DetailItem('출연진', event.cast!));
    }

    if (details.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Details',
            style: AppTheme.serif(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          ...details.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        item.label.toUpperCase(),
                        style: AppTheme.label(
                          fontSize: 9,
                          color: AppTheme.sage,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        item.value,
                        style: AppTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _DetailItem {
  final String label;
  final String value;
  const _DetailItem(this.label, this.value);
}

// =============================================================================
// Editorial Content Section (description, cast, etc.)
// =============================================================================

class _EditorialContentSection extends StatelessWidget {
  final String title;
  final String content;
  const _EditorialContentSection(
      {required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thin divider
          Container(height: 0.5, color: AppTheme.border),
          const SizedBox(height: 24),
          Text(
            title,
            style: AppTheme.serif(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            content,
            style: AppTheme.sans(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Expandable Policy Section
// =============================================================================

class _ExpandablePolicy extends StatefulWidget {
  final String title;
  final Widget child;
  const _ExpandablePolicy({required this.title, required this.child});

  @override
  State<_ExpandablePolicy> createState() => _ExpandablePolicyState();
}

class _ExpandablePolicyState extends State<_ExpandablePolicy> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.border, width: 0.5),
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: AppTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 20, color: AppTheme.sage),
                    ),
                  ],
                ),
              ),
            ),
            // Expandable content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: widget.child,
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Discount Section (always visible, prominent)
// =============================================================================

class _DiscountSection extends StatelessWidget {
  final List<dynamic> policies;
  final Event event;

  const _DiscountSection({required this.policies, required this.event});

  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFF30D158),
    'S': Color(0xFF0A84FF),
    'A': Color(0xFFFF9F0A),
    'B': Color(0xFF8E8E93),
  };

  @override
  Widget build(BuildContext context) {
    final priceFormat = NumberFormat('#,###');
    final grades = event.priceByGrade;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: AppTheme.border),
          const SizedBox(height: 24),
          Text(
            'Discount',
            style: AppTheme.serif(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...policies.map((p) {
            final name = p.name as String;
            final rate = p.discountRate as double;
            final desc = p.description as String?;
            final applicableGrades =
                p.applicableGrades as List<String>?;
            final rateText = '${(rate * 100).toInt()}%';

            // 적용 등급별 할인가 계산
            final targetGrades = applicableGrades ??
                (grades?.keys.toList() ?? ['전석']);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 할인율 배지
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          rateText,
                          style: AppTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: AppTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 등급별 할인가
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: targetGrades.map((g) {
                      final basePrice = grades?[g] ?? event.price;
                      final discounted =
                          (basePrice * (1 - rate)).round();
                      final color =
                          _gradeColors[g] ?? AppTheme.sage;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$g석',
                            style: AppTheme.sans(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${priceFormat.format(basePrice)}원',
                            style: AppTheme.sans(
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ).copyWith(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '→ ${priceFormat.format(discounted)}원',
                            style: AppTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  if (desc != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// (Legacy _DiscountPoliciesContent and _DiscountRow removed — replaced by _DiscountSection)

// =============================================================================
// Notice Section (left burgundy border accent)
// =============================================================================

class _NoticeSection extends StatelessWidget {
  final String notice;
  const _NoticeSection({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.gold, width: 2),
          ),
          color: AppTheme.cardElevated,
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '예매 유의사항',
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              notice,
              style: AppTheme.sans(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Bottom CTA (fixed, ivory bg + backdrop blur)
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.92),
            border: const Border(
                top: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: canBuy
              ? Row(
                  children: [
                    // Calendar icon button
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppTheme.sage.withValues(alpha: 0.3),
                            width: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: IconButton(
                        onPressed: () {
                          // calendar add placeholder
                        },
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: 20, color: AppTheme.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Book Tickets button
                    Expanded(
                      child: ShimmerButton(
                        text: isLoggedIn ? 'BOOK TICKETS' : 'LOGIN TO BOOK',
                        onPressed: () {
                          if (isLoggedIn) {
                            context.push('/seats/${event.id}');
                          } else {
                            context.push('/login');
                          }
                        },
                        height: 54,
                        borderRadius: 4,
                      ),
                    ),
                  ],
                )
              : Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppTheme.cardElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      event.availableSeats == 0
                          ? 'SOLD OUT'
                          : 'SALE ENDED',
                      style: AppTheme.label(
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// =============================================================================
// Share Sheet (kept functional, restyled editorial)
// =============================================================================

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 헤더 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Row(
            children: [
              const Icon(Icons.ios_share_outlined,
                  size: 18, color: AppTheme.gold),
              const SizedBox(width: 8),
              Text(
                '공연 공유하기',
                style: AppTheme.serif(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
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
            borderRadius: BorderRadius.circular(4),
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
                          AppTheme.gold.withValues(alpha: 0.15),
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
                            'MELON TICKET',
                            style: AppTheme.label(
                              fontSize: 10,
                              color: AppTheme.gold,
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
                        child: Text(
                          event.venueName!.toUpperCase(),
                          style: AppTheme.label(
                            fontSize: 9,
                            color: AppTheme.sage,
                          ),
                        ),
                      ),

                    // 공연명
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

                    // 가격 정보
                    if (hasDiscount) ...[
                      Text(
                        '${priceFormat.format(event.price)}원',
                        style: AppTheme.sans(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ).copyWith(decoration: TextDecoration.lineThrough),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            event.discount!,
                            style: AppTheme.sans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.error,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${priceFormat.format(event.price)}원',
                            style: AppTheme.sans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Text(
                        '${priceFormat.format(event.price)}원',
                        style: AppTheme.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),

                    const SizedBox(height: 8),

                    // 별점 + 리뷰 수
                    ratingAsync.when(
                      data: (rating) {
                        if (rating <= 0) return const SizedBox.shrink();
                        final reviewCount =
                            reviewsAsync.valueOrNull?.length ?? 0;
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
                                  color: AppTheme.textTertiary
                                      .withValues(alpha: 0.4));
                            }),
                            const SizedBox(width: 4),
                            Text(
                              rating.toStringAsFixed(1),
                              style: AppTheme.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$reviewCount개 리뷰',
                              style: AppTheme.sans(
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
                            color:
                                AppTheme.textTertiary.withValues(alpha: 0.7)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            dateFormat.format(event.startAt),
                            style: AppTheme.sans(
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
                        color: AppTheme.gold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppTheme.gold.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Text(
                          'VIEW PERFORMANCE',
                          style: AppTheme.label(
                            fontSize: 10,
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
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Center(
                            child: Icon(Icons.music_note_rounded,
                                size: 11, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'MELON TICKET',
                          style: AppTheme.label(
                            fontSize: 9,
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
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('링크가 복사되었습니다'),
                      ),
                    ],
                  ),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.link_rounded,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'COPY LINK',
                    style: AppTheme.label(
                      fontSize: 12,
                      color: AppTheme.onAccent,
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
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              _shareUrl,
              style: AppTheme.sans(
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
    );
  }
}

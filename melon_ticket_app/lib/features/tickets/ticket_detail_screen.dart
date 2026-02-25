import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/seat.dart';
import 'package:melon_core/data/models/ticket.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/ticket_repository.dart';
import 'package:melon_core/data/repositories/venue_view_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

const _navy = AppTheme.goldDark;
const _lineBlue = AppTheme.gold;
const _surface = AppTheme.background;
const _softBlue = AppTheme.surface;
const _cardBorder = AppTheme.border;
const _textPrimary = AppTheme.textPrimary;
const _textSecondary = AppTheme.textSecondary;
const _danger = AppTheme.error;
const _success = AppTheme.success;
const _warning = AppTheme.warning;

final _ticketStreamProvider =
    StreamProvider.family<Ticket?, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).getTicketStream(ticketId);
});

final _seatStreamProvider =
    StreamProvider.family<Seat?, String>((ref, seatId) async* {
  if (seatId.isEmpty) {
    yield null;
    return;
  }
  final seat = await ref.watch(seatRepositoryProvider).getSeat(seatId);
  yield seat;
});

class TicketDetailScreen extends ConsumerWidget {
  final String ticketId;
  final bool initialGroupQr;
  final String? groupQrOrderId;

  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    this.initialGroupQr = false,
    this.groupQrOrderId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketAsync = ref.watch(_ticketStreamProvider(ticketId));

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(
          '승차권 정보',
          style: AppTheme.nanum(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            shadows: AppTheme.textShadow,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.menu_rounded),
          ),
        ],
      ),
      body: ticketAsync.when(
        data: (ticket) {
          if (ticket == null) {
            return const _CenteredMessage(
              icon: Icons.confirmation_number_outlined,
              title: '티켓을 찾을 수 없습니다',
              subtitle: '티켓이 삭제되었거나 권한이 없습니다.',
            );
          }
          if (initialGroupQr && groupQrOrderId != null) {
            return _GroupQrScreen(orderId: groupQrOrderId!);
          }
          return _TicketDetailBody(ticket: ticket);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: _lineBlue),
        ),
        error: (error, _) => _CenteredMessage(
          icon: Icons.error_outline_rounded,
          title: '오류가 발생했습니다',
          subtitle: '$error',
          isError: true,
        ),
      ),
    );
  }
}

class _TicketDetailBody extends ConsumerWidget {
  final Ticket ticket;

  const _TicketDetailBody({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(ticket.eventId));

    return eventAsync.when(
      data: (event) {
        if (event == null) {
          return const _CenteredMessage(
            icon: Icons.event_busy_rounded,
            title: '공연 정보를 불러올 수 없습니다',
            subtitle: '잠시 후 다시 시도해 주세요.',
          );
        }

        final seatAsync = ref.watch(_seatStreamProvider(ticket.seatId));
        final seat = seatAsync.valueOrNull;
        final seatLoading = seatAsync.isLoading;
        final currentUser = ref.watch(currentUserProvider).valueOrNull;
        final now = DateTime.now();
        final canRequestCancel =
            ticket.status == TicketStatus.issued &&
            !ticket.hasAnyCheckin &&
            event.startAt.isAfter(now);

        // 업그레이드 가능 조건
        final currentGrade = seat?.grade;
        final canUpgrade = !ticket.isStanding &&
            ticket.status == TicketStatus.issued &&
            !ticket.hasAnyCheckin &&
            currentGrade != null &&
            currentGrade != 'VIP' &&
            currentUser != null;
        final upgradeCost = _getUpgradeCost(currentGrade);
        final targetGrade = _getTargetGrade(currentGrade);
        final hasEnoughMileage = currentUser != null &&
            upgradeCost > 0 &&
            currentUser.mileage.balance >= upgradeCost;

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                child: Column(
                  children: [
                    _BoardingPassTicket(
                      ticket: ticket,
                      event: event,
                      seat: seat,
                      seatLoading: seatLoading,
                    ),
                    const SizedBox(height: 12),
                    _TicketReceiptCard(
                      ticket: ticket,
                      event: event,
                    ),
                    if (canUpgrade) ...[
                      const SizedBox(height: 12),
                      _UpgradeCard(
                        currentGrade: currentGrade,
                        targetGrade: targetGrade,
                        cost: upgradeCost,
                        balance: currentUser.mileage.balance,
                        hasEnoughMileage: hasEnoughMileage,
                        onUpgrade: hasEnoughMileage
                            ? () => _requestUpgrade(
                                  context: context,
                                  ref: ref,
                                  ticket: ticket,
                                  currentGrade: currentGrade,
                                  targetGrade: targetGrade,
                                  cost: upgradeCost,
                                )
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _TicketPolicyCard(
                      ticket: ticket,
                      event: event,
                    ),
                  ],
                ),
              ),
            ),
            _BottomActionBar(
              ticket: ticket,
              canRequestCancel: canRequestCancel,
              onOpenEvent: () => context.push('/event/${event.id}'),
              onCancel: canRequestCancel
                  ? () async => _requestCancellation(
                        context: context,
                        ref: ref,
                        ticket: ticket,
                        event: event,
                      )
                  : null,
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: _lineBlue),
      ),
      error: (error, _) => _CenteredMessage(
        icon: Icons.error_outline_rounded,
        title: '공연 정보 조회 실패',
        subtitle: '$error',
        isError: true,
      ),
    );
  }

  Future<void> _requestCancellation({
    required BuildContext context,
    required WidgetRef ref,
    required Ticket ticket,
    required Event event,
  }) async {
    final now = DateTime.now();
    final daysBeforeEvent = event.startAt.difference(now).inHours / 24;
    String policyText;
    if (daysBeforeEvent < 0) {
      policyText = '관람일 이후에는 취소/환불이 불가합니다.';
    } else if (daysBeforeEvent < 1) {
      policyText = '관람 당일에는 취소/환불이 불가합니다.';
    } else if (daysBeforeEvent < 3) {
      policyText = '현재 취소 시 수수료 30%가 부과됩니다.';
    } else if (daysBeforeEvent < 7) {
      policyText = '현재 취소 시 수수료 20%가 부과됩니다.';
    } else if (daysBeforeEvent < 10) {
      policyText = '현재 취소 시 수수료 10%가 부과됩니다.';
    } else {
      policyText = '현재 취소 시 소정의 수수료만 부과됩니다.';
    }

    final confirm = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AnimatedDialogContent(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '취소/환불',
                style: AppTheme.nanum(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                  shadows: AppTheme.textShadow,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '해당 티켓을 취소하고 환불을 진행할까요?\n$policyText',
                style: AppTheme.nanum(
                  height: 1.5,
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ShimmerButton(
                      text: '취소/환불',
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      height: 48,
                      borderRadius: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text('닫기', style: AppTheme.nanum()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true || !context.mounted) return;

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .requestTicketCancellation(ticketId: ticket.id);
      if (!context.mounted) return;
      final amount = (result['refundAmount'] as num?)?.toInt() ?? 0;
      final amountText = NumberFormat('#,###', 'ko_KR').format(amount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('반환 완료: $amountText원 환불'),
          backgroundColor: _success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      final errorMsg = _parseFirebaseError(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: _danger,
        ),
      );
    }
  }

  Future<void> _requestUpgrade({
    required BuildContext context,
    required WidgetRef ref,
    required Ticket ticket,
    required String currentGrade,
    required String targetGrade,
    required int cost,
  }) async {
    final confirm = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AnimatedDialogContent(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '좌석 업그레이드',
                style: AppTheme.nanum(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                  shadows: AppTheme.textShadow,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GradeBadge(grade: currentGrade),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.gold,
                      size: 20,
                    ),
                  ),
                  _GradeBadge(grade: targetGrade),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${NumberFormat('#,###', 'ko_KR').format(cost)}P를 사용하여\n좌석 등급을 업그레이드하시겠습니까?',
                style: AppTheme.nanum(
                  height: 1.5,
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text('취소', style: AppTheme.nanum()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShimmerButton(
                      text: '업그레이드',
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      height: 48,
                      borderRadius: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true || !context.mounted) return;

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .upgradeTicketSeat(ticketId: ticket.id);
      if (!context.mounted) return;
      final newGrade = result['newGrade'] as String? ?? targetGrade;
      final newSeatDisplay = result['newSeatDisplay'] as String? ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$newGrade 등급으로 업그레이드 완료! $newSeatDisplay'),
          backgroundColor: _success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      final errorMsg = _parseFirebaseError(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: _danger,
        ),
      );
    }
  }
}

int _getUpgradeCost(String? grade) {
  switch (grade) {
    case 'A':
      return 2000;
    case 'S':
      return 3000;
    case 'R':
      return 5000;
    default:
      return 0;
  }
}

String _getTargetGrade(String? grade) {
  switch (grade) {
    case 'A':
      return 'S';
    case 'S':
      return 'R';
    case 'R':
      return 'VIP';
    default:
      return '';
  }
}

Color _gradeColor(String grade) {
  switch (grade) {
    case 'VIP':
      return const Color(0xFFC9A84C);
    case 'R':
      return const Color(0xFF6B4FA0);
    case 'S':
      return const Color(0xFF2D6A4F);
    case 'A':
      return const Color(0xFF3B7DD8);
    default:
      return _textSecondary;
  }
}

class _GradeBadge extends StatelessWidget {
  final String grade;

  const _GradeBadge({required this.grade});

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        grade,
        style: AppTheme.nanum(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  final String currentGrade;
  final String targetGrade;
  final int cost;
  final int balance;
  final bool hasEnoughMileage;
  final VoidCallback? onUpgrade;

  const _UpgradeCard({
    required this.currentGrade,
    required this.targetGrade,
    required this.cost,
    required this.balance,
    required this.hasEnoughMileage,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final targetColor = _gradeColor(targetGrade);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: targetColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upgrade_rounded, size: 18, color: targetColor),
              const SizedBox(width: 6),
              Text(
                '좌석 업그레이드',
                style: AppTheme.nanum(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  shadows: AppTheme.textShadow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _GradeBadge(grade: currentGrade),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppTheme.gold,
                  size: 16,
                ),
              ),
              _GradeBadge(grade: targetGrade),
              const Spacer(),
              Text(
                '${NumberFormat('#,###', 'ko_KR').format(cost)}P',
                style: AppTheme.nanum(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: targetColor,
                  shadows: AppTheme.textShadow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '보유 마일리지: ${NumberFormat('#,###', 'ko_KR').format(balance)}P',
            style: AppTheme.nanum(
              fontSize: 12,
              color: hasEnoughMileage ? _textSecondary : _danger,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: hasEnoughMileage
                ? ShimmerButton(
                    text: '$targetGrade 등급으로 업그레이드',
                    onPressed: onUpgrade ?? () {},
                    height: 44,
                    borderRadius: 10,
                  )
                : OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      '마일리지 부족',
                      style: AppTheme.nanum(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Boarding Pass Style Ticket Card
// =============================================================================

/// ClipPath that creates the boarding-pass perforation cutouts on left/right
class _BoardingPassClipper extends CustomClipper<Path> {
  final double notchRadius;
  final double notchPosition; // fraction from top (0.0 ~ 1.0)

  const _BoardingPassClipper({
    this.notchRadius = 18,
    this.notchPosition = 0.55,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    final notchY = size.height * notchPosition;

    // Start from top-left with rounded corner
    path.moveTo(14, 0);
    path.lineTo(size.width - 14, 0);
    path.arcToPoint(
      Offset(size.width, 14),
      radius: const Radius.circular(14),
    );

    // Right edge down to notch
    path.lineTo(size.width, notchY - notchRadius);
    // Right semicircle cutout (inward)
    path.arcToPoint(
      Offset(size.width, notchY + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // Right edge down to bottom-right corner
    path.lineTo(size.width, size.height - 14);
    path.arcToPoint(
      Offset(size.width - 14, size.height),
      radius: const Radius.circular(14),
    );

    // Bottom edge
    path.lineTo(14, size.height);
    path.arcToPoint(
      Offset(0, size.height - 14),
      radius: const Radius.circular(14),
    );

    // Left edge up to notch
    path.lineTo(0, notchY + notchRadius);
    // Left semicircle cutout (inward)
    path.arcToPoint(
      Offset(0, notchY - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // Left edge up to top-left corner
    path.lineTo(0, 14);
    path.arcToPoint(
      const Offset(14, 0),
      radius: const Radius.circular(14),
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BoardingPassClipper oldClipper) =>
      notchRadius != oldClipper.notchRadius ||
      notchPosition != oldClipper.notchPosition;
}

class _BoardingPassTicket extends ConsumerWidget {
  final Ticket ticket;
  final Event event;
  final Seat? seat;
  final bool seatLoading;

  const _BoardingPassTicket({
    required this.ticket,
    required this.event,
    required this.seat,
    required this.seatLoading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventDate =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(event.startAt);
    final eventTime = DateFormat('HH:mm', 'ko_KR').format(event.startAt);
    final ticketNumber = ticket.id.length > 8
        ? ticket.id.substring(ticket.id.length - 8).toUpperCase()
        : ticket.id.toUpperCase();

    // Determine grade color for accents
    final grade = seat?.grade ?? '';
    final gradeCol = grade.isNotEmpty ? _gradeColor(grade) : AppTheme.gold;

    // Resolve inline seat view (reusing 5-step matching)
    VenueSeatView? matchedView;
    if (!ticket.isStanding && seat != null && event.venueId.isNotEmpty) {
      final viewsAsync = ref.watch(venueViewsProvider(event.venueId));
      matchedView = viewsAsync.whenOrNull(
        data: (views) {
          if (views.isEmpty) return null;
          return _findBestSeatView(views, seat!);
        },
      );
    }

    return ClipPath(
      clipper: const _BoardingPassClipper(
        notchRadius: 18,
        notchPosition: 0.55,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.card,
          boxShadow: [
            ...AppShadows.card,
            BoxShadow(
              color: gradeCol.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // ──────────────────────────────────────────
            // TOP SECTION: Event info header (grade-tinted gradient)
            // ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    gradeCol,
                    gradeCol.withValues(alpha: 0.85),
                    AppTheme.gold,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.confirmation_number_rounded,
                    size: 14,
                    color: AppTheme.onAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SMART TICKET',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onAccent,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusBackground(ticket.status),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(ticket.status),
                      style: AppTheme.nanum(
                        color: _statusTextColor(ticket.status),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        noShadow: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ──────────────────────────────────────────
            // Event title + date/venue info
            // ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: AppTheme.nanum(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      shadows: AppTheme.textShadowStrong,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.calendar_today_rounded,
                        text: eventDate,
                      ),
                      const SizedBox(width: 10),
                      _InfoChip(
                        icon: Icons.access_time_rounded,
                        text: eventTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _InfoChip(
                    icon: Icons.location_on_outlined,
                    text: event.venueName?.isNotEmpty == true
                        ? event.venueName!
                        : '공연장 정보 없음',
                  ),
                ],
              ),
            ),

            // ──────────────────────────────────────────
            // MIDDLE SECTION: Large seat info
            // ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: ticket.isStanding
                  ? _StandingSeatDisplay(ticket: ticket)
                  : _SeatInfoDisplay(
                      seat: seat,
                      seatLoading: seatLoading,
                      gradeColor: gradeCol,
                    ),
            ),

            // ──────────────────────────────────────────
            // INLINE SEAT VIEW (5-step matched image)
            // ──────────────────────────────────────────
            if (matchedView != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: _InlineSeatView(
                  view: matchedView,
                  onTap: () => _showSeatViewSheet(context, matchedView!),
                ),
              ),

            // ──────────────────────────────────────────
            // PERFORATION LINE (dotted)
            // ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                width: double.infinity,
                height: 1,
                child: CustomPaint(
                  painter: _DottedLinePainter(
                    color: AppTheme.sage.withValues(alpha: 0.3),
                    dashWidth: 5,
                    dashSpace: 4,
                  ),
                ),
              ),
            ),

            // ──────────────────────────────────────────
            // BOTTOM SECTION: QR code + ticket number
            // ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // QR code (left)
                  Container(
                    width: 120,
                    height: 120,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: ticket.status == TicketStatus.issued
                        ? _CompactQrSection(ticket: ticket)
                        : _InactiveQrCompact(status: ticket.status),
                  ),
                  const SizedBox(width: 14),
                  // Ticket meta (right)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '예매번호',
                          style: AppTheme.label(
                            fontSize: 9,
                            color: _textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ticketNumber,
                          style: GoogleFonts.robotoMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: _textPrimary.withValues(alpha: 0.1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '발행일시',
                          style: AppTheme.label(
                            fontSize: 9,
                            color: _textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('yyyy.MM.dd HH:mm', 'ko_KR')
                              .format(ticket.issuedAt),
                          style: AppTheme.nanum(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        if (ticket.status == TicketStatus.issued) ...[
                          const SizedBox(height: 10),
                          _QrTimerBadge(ticket: ticket),
                          const SizedBox(height: 6),
                          const _LiveIndicator(),
                        ],
                      ],
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

  void _showSeatViewSheet(BuildContext context, VenueSeatView view) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        view.isPanorama360
                            ? Icons.threesixty_rounded
                            : view.isPanorama180
                                ? Icons.panorama_horizontal_rounded
                                : Icons.visibility_rounded,
                        size: 20,
                        color: AppTheme.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '내 좌석에서 본 시야',
                          style: AppTheme.nanum(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                            shadows: AppTheme.textShadow,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          view.displayName,
                          style: AppTheme.nanum(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (view.description != null && view.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        view.description!,
                        style: AppTheme.nanum(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: view.is360
                          ? PanoramaViewer(
                              sensorControl: SensorControl.orientation,
                              animSpeed: 1.0,
                              minLongitude:
                                  view.isPanorama180 ? -90.0 : -180.0,
                              maxLongitude:
                                  view.isPanorama180 ? 90.0 : 180.0,
                              child: Image.network(
                                view.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.broken_image_rounded,
                                          size: 40, color: _textSecondary),
                                      const SizedBox(height: 8),
                                      Text(
                                        '이미지를 불러올 수 없습니다',
                                        style: AppTheme.nanum(
                                          fontSize: 13,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : InteractiveViewer(
                              minScale: 1.0,
                              maxScale: 4.0,
                              child: CachedNetworkImage(
                                imageUrl: view.imageUrl,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator(
                                      color: AppTheme.gold),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.broken_image_rounded,
                                          size: 40, color: _textSecondary),
                                      const SizedBox(height: 8),
                                      Text(
                                        '이미지를 불러올 수 없습니다',
                                        style: AppTheme.nanum(
                                          fontSize: 13,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
              ],
            );
          },
        );
      },
    );
  }
}

/// The large seat info display in the middle of the boarding pass
class _SeatInfoDisplay extends StatelessWidget {
  final Seat? seat;
  final bool seatLoading;
  final Color gradeColor;

  const _SeatInfoDisplay({
    required this.seat,
    required this.seatLoading,
    required this.gradeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (seatLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '좌석 정보 확인 중...',
            style: AppTheme.nanum(
              fontSize: 14,
              color: _textSecondary,
            ),
          ),
        ),
      );
    }

    if (seat == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '좌석 정보 없음',
            style: AppTheme.nanum(
              fontSize: 14,
              color: _textSecondary,
            ),
          ),
        ),
      );
    }

    final grade = seat!.grade ?? '';
    final block = seat!.block;
    final floor = seat!.floor;
    final row = seat!.row ?? '';
    final number = seat!.number;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: gradeColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gradeColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          // Grade badge row (with subtle glow)
          if (grade.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: gradeColor.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: gradeColor.withValues(alpha: 0.18),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    '$grade석',
                    style: AppTheme.nanum(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: gradeColor,
                      noShadow: true,
                    ),
                  ),
                ),
              ],
            ),
          if (grade.isNotEmpty) const SizedBox(height: 10),

          // Main seat info grid
          Row(
            children: [
              Expanded(
                child: _SeatInfoColumn(
                  label: '구역',
                  value: block,
                  large: true,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: gradeColor.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _SeatInfoColumn(
                  label: '층',
                  value: floor,
                  large: false,
                ),
              ),
              if (row.isNotEmpty) ...[
                Container(
                  width: 1,
                  height: 36,
                  color: gradeColor.withValues(alpha: 0.12),
                ),
                Expanded(
                  child: _SeatInfoColumn(
                    label: '열',
                    value: row,
                    large: true,
                  ),
                ),
              ],
              Container(
                width: 1,
                height: 36,
                color: gradeColor.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _SeatInfoColumn(
                  label: '번호',
                  value: '$number',
                  large: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeatInfoColumn extends StatelessWidget {
  final String label;
  final String value;
  final bool large;

  const _SeatInfoColumn({
    required this.label,
    required this.value,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppTheme.label(
            fontSize: 9,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: large
              ? GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(
                      color: _textPrimary.withValues(alpha: 0.08),
                      blurRadius: 6,
                    ),
                  ],
                )
              : AppTheme.nanum(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StandingSeatDisplay extends StatelessWidget {
  final Ticket ticket;

  const _StandingSeatDisplay({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
            ),
            child: Text(
              'STANDING',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.gold,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            ticket.entryNumber != null
                ? '#${ticket.entryNumber}'
                : '입장권',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (ticket.entryNumber != null)
            Text(
              '입장 순번',
              style: AppTheme.nanum(
                fontSize: 12,
                color: _textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Small info chip with icon + text
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: AppTheme.nanum(
              fontSize: 12,
              color: _textSecondary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Dotted line painter for the perforation
class _DottedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  const _DottedLinePainter({
    required this.color,
    this.dashWidth = 5,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    double startX = 24; // start after left notch
    final endX = size.width - 24; // end before right notch

    while (startX < endX) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(math.min(startX + dashWidth, endX), 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter old) =>
      color != old.color || dashWidth != old.dashWidth;
}

// =============================================================================
// Compact QR for boarding pass bottom section
// =============================================================================

class _CompactQrSection extends ConsumerStatefulWidget {
  final Ticket ticket;

  const _CompactQrSection({required this.ticket});

  @override
  ConsumerState<_CompactQrSection> createState() => _CompactQrSectionState();
}

class _CompactQrSectionState extends ConsumerState<_CompactQrSection> {
  static const int _refreshIntervalSeconds = 120;

  int _remainingSeconds = _refreshIntervalSeconds;
  String? _qrData;
  bool _isLoading = true;
  String? _errorText;
  bool _isRefreshingToken = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _refreshQrToken();
  }

  @override
  void didUpdateWidget(covariant _CompactQrSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticket.id != oldWidget.ticket.id ||
        widget.ticket.qrVersion != oldWidget.ticket.qrVersion) {
      _refreshQrToken();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      }
      if (_remainingSeconds <= 0) {
        _refreshQrToken();
      }
    });
  }

  Future<void> _refreshQrToken() async {
    if (_isRefreshingToken) return;
    if (!mounted) return;

    _isRefreshingToken = true;
    setState(() {
      _isLoading = _qrData == null;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .issueQrToken(ticketId: widget.ticket.id);
      final token = result['token'] as String?;
      final exp = result['exp'] as int?;

      if (token == null || token.isEmpty || exp == null) {
        throw Exception('QR 토큰 응답이 올바르지 않습니다');
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final secondsLeft = (exp - now).clamp(1, _refreshIntervalSeconds).toInt();

      if (!mounted) return;
      setState(() {
        _qrData = token;
        _remainingSeconds = secondsLeft;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'QR 발급 실패';
      });
    } finally {
      _isRefreshingToken = false;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: _lineBlue,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_qrData == null) {
      return Center(
        child: GestureDetector(
          onTap: _refreshQrToken,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh_rounded, size: 20, color: _textSecondary),
              const SizedBox(height: 4),
              Text(
                _errorText ?? 'QR 실패',
                style: AppTheme.nanum(fontSize: 10, color: _textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _refreshQrToken,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: _qrData!));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR 데이터가 복사되었습니다'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: QrImageView(
        data: _qrData!,
        version: QrVersions.auto,
        size: 108,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF111827),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF111827),
        ),
        gapless: true,
      ),
    );
  }
}

/// QR timer badge shown next to the QR in the boarding pass
class _QrTimerBadge extends ConsumerStatefulWidget {
  final Ticket ticket;

  const _QrTimerBadge({required this.ticket});

  @override
  ConsumerState<_QrTimerBadge> createState() => _QrTimerBadgeState();
}

class _QrTimerBadgeState extends ConsumerState<_QrTimerBadge> {
  static const int _refreshIntervalSeconds = 120;

  int _remainingSeconds = _refreshIntervalSeconds;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      }
      if (_remainingSeconds <= 0) {
        _remainingSeconds = _refreshIntervalSeconds;
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatRemaining(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isLow = _remainingSeconds <= 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isLow ? AppTheme.cardElevated : AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLow ? AppTheme.warning : AppTheme.borderLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 12,
            color: isLow ? AppTheme.warning : _textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            _formatRemaining(_remainingSeconds),
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              color: isLow ? AppTheme.warning : _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LIVE Indicator — pulsing dot + real-time clock + shimmer wave (MT-045)
// =============================================================================

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseOpacity;

  late final AnimationController _shimmerController;

  Timer? _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();

    // Pulsing red dot: opacity 0.3 → 1.0, 1-second cycle
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Shimmer gradient sweep: continuous 2-second loop
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Real-time clock updated every second
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTime();
    });
  }

  void _updateTime() {
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment(
                -1.0 + 2.0 * _shimmerController.value,
                0.0,
              ),
              end: Alignment(
                0.0 + 2.0 * _shimmerController.value,
                0.0,
              ),
              colors: const [
                Color(0xFFF5F3F0),
                Color(0xFFFAF8F5),
                Color(0xFFF5F3F0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing red dot
              FadeTransition(
                opacity: _pulseOpacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x40EF4444),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // LIVE text
              FadeTransition(
                opacity: _pulseOpacity,
                child: Text(
                  'LIVE',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFEF4444),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Real-time clock
              Text(
                _currentTime,
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InactiveQrCompact extends StatelessWidget {
  final TicketStatus status;

  const _InactiveQrCompact({required this.status});

  @override
  Widget build(BuildContext context) {
    final isUsed = status == TicketStatus.used;
    final icon = isUsed ? Icons.done_all_rounded : Icons.cancel_rounded;
    final color = isUsed ? _success : _danger;
    final label = isUsed ? '입장 완료' : '반환 완료';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTheme.nanum(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Receipt / Policy / Bottom Action (unchanged logic)
// =============================================================================

class _TicketReceiptCard extends StatefulWidget {
  final Ticket ticket;
  final Event event;

  const _TicketReceiptCard({
    required this.ticket,
    required this.event,
  });

  @override
  State<_TicketReceiptCard> createState() => _TicketReceiptCardState();
}

class _TicketReceiptCardState extends State<_TicketReceiptCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final event = widget.event;
    final issueText =
        DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(ticket.issuedAt);
    final startText =
        DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(event.startAt);
    final totalAmount =
        '${NumberFormat('#,###', 'ko_KR').format(event.price)}원';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: always visible
            Row(
              children: [
                Expanded(
                  child: Text(
                    '영수증',
                    style: AppTheme.nanum(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                      letterSpacing: -0.2,
                      shadows: AppTheme.textShadow,
                    ),
                  ),
                ),
                if (!_expanded)
                  Text(
                    totalAmount,
                    style: AppTheme.nanum(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                      shadows: AppTheme.textShadow,
                    ),
                  ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
            // Expandable details
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        const _ReceiptRow(
                            label: '결제방식', value: '모바일티켓'),
                        _ReceiptRow(
                            label: '승차권 상태',
                            value: _statusLabel(ticket.status)),
                        _ReceiptRow(label: '공연 시작', value: startText),
                        _ReceiptRow(label: '발행일시', value: issueText),
                        if (ticket.usedAt != null)
                          _ReceiptRow(
                            label: '입장 완료',
                            value: DateFormat('yyyy.MM.dd HH:mm', 'ko_KR')
                                .format(ticket.usedAt!),
                            valueColor: _success,
                          ),
                        if (ticket.canceledAt != null)
                          _ReceiptRow(
                            label: '반환 완료',
                            value: DateFormat('yyyy.MM.dd HH:mm', 'ko_KR')
                                .format(ticket.canceledAt!),
                            valueColor: _danger,
                          ),
                        const Divider(color: _cardBorder, height: 24),
                        _ReceiptRow(
                          label: '결제금액',
                          value: totalAmount,
                          valueColor: _textPrimary,
                          emphasize: true,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketPolicyCard extends StatelessWidget {
  final Ticket ticket;
  final Event event;

  const _TicketPolicyCard({
    required this.ticket,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remainMinutes = event.startAt.difference(now).inMinutes;
    final refundHint = remainMinutes >= 24 * 60
        ? '공연 24시간 이전: 100% 환불'
        : remainMinutes >= 3 * 60
            ? '공연 3시간 이전: 70% 환불'
            : '공연 3시간 이내: 환불 불가';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이용안내',
            style: AppTheme.nanum(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
              shadows: AppTheme.textShadow,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '• QR 코드는 2분마다 자동 갱신됩니다.\n'
            '• 화면 캡처/사진 이미지는 유효한 승차권이 아닙니다.\n'
            '• 입장 시 본인 확인이 필요할 수 있습니다.\n'
            '• 반환/취소 정책은 결제 시점과 동일하게 적용됩니다.',
            style: AppTheme.nanum(
              fontSize: 13,
              color: _textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: _warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    refundHint,
                    style: AppTheme.nanum(
                      color: AppTheme.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
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

class _BottomActionBar extends StatelessWidget {
  final Ticket ticket;
  final bool canRequestCancel;
  final VoidCallback onOpenEvent;
  final Future<void> Function()? onCancel;

  const _BottomActionBar({
    required this.ticket,
    required this.canRequestCancel,
    required this.onOpenEvent,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final canCancel = canRequestCancel && onCancel != null;
    final cancelLabel = canCancel
        ? '취소/환불'
        : ticket.status == TicketStatus.canceled
            ? '취소완료'
            : ticket.status == TicketStatus.used
                ? '이용완료'
                : ticket.hasAnyCheckin
                    ? '입장확인'
                    : '취소불가';

    return Container(
      color: _softBlue,
      padding: EdgeInsets.fromLTRB(
        0,
        6,
        0,
        MediaQuery.of(context).padding.bottom == 0
            ? 6
            : MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onOpenEvent,
                style: TextButton.styleFrom(
                  foregroundColor: _navy,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  '공연정보',
                  style: AppTheme.nanum(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    shadows: AppTheme.textShadow,
                  ),
                ),
              ),
            ),
            Container(width: 1, color: AppTheme.border),
            Expanded(
              child: TextButton(
                onPressed: canCancel ? () => onCancel!() : null,
                style: TextButton.styleFrom(
                  foregroundColor: canCancel ? _danger : _textSecondary,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  cancelLabel,
                  style: AppTheme.nanum(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    shadows: AppTheme.textShadow,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.nanum(
                fontSize: emphasize ? 16 : 13,
                color: emphasize ? _textPrimary : _textSecondary,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                shadows: emphasize ? AppTheme.textShadow : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTheme.nanum(
              fontSize: emphasize ? 28 : 14,
              color: valueColor ?? _textPrimary,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: emphasize ? -0.4 : 0,
              shadows: emphasize ? AppTheme.textShadowStrong : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isError;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? _danger : _textSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
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
                shadows: AppTheme.textShadow,
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
          ],
        ),
      ),
    );
  }
}

String _parseFirebaseError(String error) {
  final bracketMatch = RegExp(r'\[.*?\]\s*(.+)').firstMatch(error);
  if (bracketMatch != null) {
    return bracketMatch.group(1)!;
  }
  if (error.startsWith('Exception:')) {
    return error.substring('Exception:'.length).trim();
  }
  return '반환 처리 중 오류가 발생했습니다';
}

String _statusLabel(TicketStatus status) {
  switch (status) {
    case TicketStatus.issued:
      return '스마트티켓';
    case TicketStatus.used:
      return '이용완료';
    case TicketStatus.canceled:
      return '반환완료';
  }
}

Color _statusTextColor(TicketStatus status) {
  switch (status) {
    case TicketStatus.issued:
      return AppTheme.onAccent;
    case TicketStatus.used:
      return AppTheme.success;
    case TicketStatus.canceled:
      return AppTheme.error;
  }
}

Color _statusBackground(TicketStatus status) {
  switch (status) {
    case TicketStatus.issued:
      return AppTheme.gold;
    case TicketStatus.used:
      return const Color(0x1A30D158);
    case TicketStatus.canceled:
      return const Color(0x1AFF5A5F);
  }
}

// =============================================================================
// 내 좌석 시야 — 5단계 매칭 + 인라인 이미지 (MT-038)
// =============================================================================

/// Top-level 5-step seat view matching (reusable from multiple widgets)
VenueSeatView? _findBestSeatView(
    Map<String, VenueSeatView> views, Seat seat) {
  final zone = seat.block.trim();
  final floor = seat.floor.trim();
  final row = (seat.row ?? '').trim();
  final number = seat.number;

  // 1. exact seat (zone + floor + row + seat)
  if (row.isNotEmpty) {
    final k1 = VenueSeatView.buildKey(
        zone: zone, floor: floor, row: row, seat: number);
    if (views.containsKey(k1)) return views[k1];
  }

  // 2. exact row (zone + floor + row)
  if (row.isNotEmpty) {
    final k2 = VenueSeatView.buildKey(zone: zone, floor: floor, row: row);
    if (views.containsKey(k2)) return views[k2];
  }

  // 3. nearest row in same zone/floor
  if (row.isNotEmpty) {
    final rowNum = int.tryParse(row);
    if (rowNum != null) {
      VenueSeatView? nearest;
      int bestDist = 999;
      for (final v in views.values) {
        if (v.zone.trim() == zone &&
            v.floor.trim() == floor &&
            v.row != null &&
            v.seat == null) {
          final vRow = int.tryParse(v.row!.trim());
          if (vRow != null) {
            final dist = (vRow - rowNum).abs();
            if (dist < bestDist) {
              bestDist = dist;
              nearest = v;
            }
          }
        }
      }
      if (nearest != null) return nearest;
    }
  }

  // 4. seat without row (zone + floor + seat)
  final k4 =
      VenueSeatView.buildKey(zone: zone, floor: floor, seat: number);
  if (views.containsKey(k4)) return views[k4];

  // 5. zone representative (zone + floor)
  final k5 = VenueSeatView.buildKey(zone: zone, floor: floor);
  if (views.containsKey(k5)) return views[k5];

  return null;
}

/// Inline seat view image displayed directly inside the boarding pass card.
/// Shows the matched seat view photo with gradient overlay, label, and 360 badge.
class _InlineSeatView extends StatelessWidget {
  final VenueSeatView view;
  final VoidCallback onTap;

  const _InlineSeatView({required this.view, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  view.is360
                      ? Icons.view_in_ar_rounded
                      : Icons.visibility_rounded,
                  size: 14,
                  color: AppTheme.gold,
                ),
                const SizedBox(width: 5),
                Text(
                  '내 좌석에서 본 시야',
                  style: AppTheme.nanum(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gold,
                  ),
                ),
                const Spacer(),
                Text(
                  view.displayName,
                  style: AppTheme.nanum(
                    fontSize: 10,
                    color: AppTheme.gold.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.open_in_full_rounded,
                    size: 12,
                    color: AppTheme.gold.withValues(alpha: 0.5)),
              ],
            ),
          ),

          // Image container
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image with shimmer placeholder
                  CachedNetworkImage(
                    imageUrl: view.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppTheme.surface,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppTheme.gold,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppTheme.surface,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.broken_image_rounded,
                                size: 28, color: _textSecondary),
                            const SizedBox(height: 4),
                            Text(
                              '이미지를 불러올 수 없습니다',
                              style: AppTheme.nanum(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Subtle gradient overlay (bottom fade for readability)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 360 badge (top-right)
                  if (view.is360)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.gold.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.view_in_ar_rounded,
                                size: 11, color: AppTheme.gold),
                            const SizedBox(width: 3),
                            Text(
                              '360\u00B0',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // "Tap to expand" hint (bottom-right)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.zoom_out_map_rounded,
                              size: 11, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text(
                            '크게 보기',
                            style: AppTheme.nanum(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                              noShadow: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Group QR Screen — 통합 QR 코드 표시
// =============================================================================

class _GroupQrScreen extends ConsumerStatefulWidget {
  final String orderId;

  const _GroupQrScreen({required this.orderId});

  @override
  ConsumerState<_GroupQrScreen> createState() => _GroupQrScreenState();
}

class _GroupQrScreenState extends ConsumerState<_GroupQrScreen> {
  static const int _refreshInterval = 120;

  String? _qrData;
  int _ticketCount = 0;
  int _remainingSeconds = _refreshInterval;
  bool _isLoading = true;
  String? _errorText;
  bool _isRefreshing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _refresh();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      }
      if (_remainingSeconds <= 0) _refresh();
    });
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    setState(() {
      _isLoading = _qrData == null;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .issueGroupQrToken(orderId: widget.orderId);
      final token = result['token'] as String?;
      final exp = result['exp'] as int?;
      final count = result['ticketCount'] as int? ?? 0;

      if (token == null || exp == null) {
        throw Exception('통합 QR 토큰 응답 오류');
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final left = (exp - now).clamp(1, _refreshInterval).toInt();

      if (!mounted) return;
      setState(() {
        _qrData = token;
        _ticketCount = count;
        _remainingSeconds = left;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = '통합 QR 발급 실패';
      });
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Title
            Text(
              '통합 입장 QR',
              style: AppTheme.nanum(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                shadows: AppTheme.textShadow,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '총 $_ticketCount매',
                style: AppTheme.nanum(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.onAccent,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // QR Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 180,
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _lineBlue,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : _qrData == null
                      ? GestureDetector(
                          onTap: _refresh,
                          child: SizedBox(
                            width: 180,
                            height: 180,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.refresh_rounded,
                                    size: 32, color: _textSecondary),
                                const SizedBox(height: 8),
                                Text(
                                  _errorText ?? '발급 실패',
                                  style: AppTheme.nanum(
                                      fontSize: 13, color: _textSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: _refresh,
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: _qrData!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('통합 QR 데이터가 복사되었습니다'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: QrImageView(
                            data: _qrData!,
                            version: QrVersions.auto,
                            size: 180,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF111827),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF111827),
                            ),
                            gapless: true,
                          ),
                        ),
            ),
            const SizedBox(height: 16),

            // Timer
            Text(
              '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
              style: GoogleFonts.robotoMono(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _remainingSeconds < 30 ? _danger : _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'QR 유효시간',
              style: AppTheme.nanum(fontSize: 11, color: _textSecondary),
            ),
            const SizedBox(height: 20),

            // Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: _textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '같은 주문의 모든 티켓을 한번에 입장 처리합니다',
                          style: AppTheme.nanum(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
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
    );
  }
}

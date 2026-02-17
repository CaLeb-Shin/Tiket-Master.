import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

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

  const TicketDetailScreen({super.key, required this.ticketId});

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
          style: GoogleFonts.notoSans(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
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
        final now = DateTime.now();
        final canRequestCancel =
            ticket.status == TicketStatus.issued && event.startAt.isAfter(now);

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                child: Column(
                  children: [
                    _TicketTopCard(
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
    final remainingMinutes = event.startAt.difference(now).inMinutes;
    final policyText = remainingMinutes >= 24 * 60
        ? '현재 취소 시 100% 환불됩니다.'
        : remainingMinutes >= 3 * 60
            ? '현재 취소 시 70% 환불됩니다.'
            : '공연 3시간 이내로 취소가 제한됩니다.';

    final confirm = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AnimatedDialogContent(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '승차권 반환',
                style: GoogleFonts.notoSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '해당 티켓을 반환하고 환불을 진행할까요?\n$policyText',
                style: GoogleFonts.notoSans(
                  height: 1.5,
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text('닫기', style: GoogleFonts.notoSans()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShimmerButton(
                      text: '반환 진행',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('반환 실패: $e'),
          backgroundColor: _danger,
        ),
      );
    }
  }
}

class _TicketTopCard extends StatelessWidget {
  final Ticket ticket;
  final Event event;
  final Seat? seat;
  final bool seatLoading;

  const _TicketTopCard({
    required this.ticket,
    required this.event,
    required this.seat,
    required this.seatLoading,
  });

  @override
  Widget build(BuildContext context) {
    final eventDate =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(event.startAt);
    final eventTime = DateFormat('HH:mm', 'ko_KR').format(event.startAt);
    final revealText =
        DateFormat('M월 d일 HH:mm', 'ko_KR').format(event.revealAt);
    final issuedAtText =
        DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(ticket.issuedAt);

    return GlowCard(
      borderRadius: 14,
      padding: EdgeInsets.zero,
      backgroundColor: AppTheme.card.withValues(alpha: 0.85),
      borderColor: _cardBorder,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    eventDate,
                    style: GoogleFonts.notoSans(
                      color: AppTheme.onAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusBackground(ticket.status),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(ticket.status),
                    style: GoogleFonts.notoSans(
                      color: _statusTextColor(ticket.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: GoogleFonts.notoSans(
                    color: _textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _TopMetaText(
                  label: '공연일시',
                  value:
                      '${DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(event.startAt)} $eventTime',
                ),
                _TopMetaText(
                  label: '공연장',
                  value: event.venueName?.isNotEmpty == true
                      ? event.venueName!
                      : '공연장 정보 없음',
                ),
                const SizedBox(height: 10),
                const Divider(color: _cardBorder, height: 1),
                const SizedBox(height: 10),
                _TopDataRow(label: '승차권 번호', value: ticket.id, mono: true),
                _TopDataRow(label: '발행일시', value: issuedAtText),
                if (seat != null)
                  _TopDataRow(label: '좌석', value: seat!.displayName)
                else if (!event.isSeatsRevealed)
                  _TopDataRow(label: '좌석', value: '좌석 공개 대기 ($revealText)')
                else if (seatLoading)
                  const _TopDataRow(label: '좌석', value: '좌석 정보 확인 중')
                else
                  const _TopDataRow(label: '좌석', value: '좌석 정보 없음'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderLight),
                  ),
                  child: ticket.status == TicketStatus.issued
                      ? _QrSection(ticket: ticket)
                      : _InactiveQrSection(status: ticket.status),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketReceiptCard extends StatelessWidget {
  final Ticket ticket;
  final Event event;

  const _TicketReceiptCard({
    required this.ticket,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final issueText =
        DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(ticket.issuedAt);
    final startText =
        DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(event.startAt);

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
            '영수증',
            style: GoogleFonts.notoSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          const _ReceiptRow(label: '결제방식', value: '모바일티켓'),
          _ReceiptRow(label: '승차권 상태', value: _statusLabel(ticket.status)),
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
            value: '${NumberFormat('#,###', 'ko_KR').format(event.price)}원',
            valueColor: _textPrimary,
            emphasize: true,
          ),
        ],
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
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '• QR 코드는 2분마다 자동 갱신됩니다.\n'
            '• 화면 캡처/사진 이미지는 유효한 승차권이 아닙니다.\n'
            '• 입장 시 본인 확인이 필요할 수 있습니다.\n'
            '• 반환/취소 정책은 결제 시점과 동일하게 적용됩니다.',
            style: GoogleFonts.notoSans(
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
                    style: GoogleFonts.notoSans(
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
        ? '반환하기'
        : ticket.status == TicketStatus.canceled
            ? '반환완료'
            : ticket.status == TicketStatus.used
                ? '이용완료'
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
                onPressed: canCancel ? () => onCancel!() : null,
                style: TextButton.styleFrom(
                  foregroundColor: canCancel ? _navy : _textSecondary,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  cancelLabel,
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Container(width: 1, color: AppTheme.border),
            Expanded(
              child: TextButton(
                onPressed: onOpenEvent,
                style: TextButton.styleFrom(
                  foregroundColor: _navy,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  '공연정보',
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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

class _QrSection extends ConsumerStatefulWidget {
  final Ticket ticket;

  const _QrSection({required this.ticket});

  @override
  ConsumerState<_QrSection> createState() => _QrSectionState();
}

class _QrSectionState extends ConsumerState<_QrSection> {
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
  void didUpdateWidget(covariant _QrSection oldWidget) {
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
        _errorText = 'QR 발급 실패: $e';
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

  String _formatRemaining(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isLow = _remainingSeconds <= 30;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '입장 QR',
              style: GoogleFonts.notoSans(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            InkWell(
              onTap: _refreshQrToken,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded,
                        size: 14, color: _lineBlue),
                    const SizedBox(width: 4),
                    Text(
                      '새로고침',
                      style: GoogleFonts.notoSans(
                        color: _lineBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: 220,
          height: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
          ),
          child: Center(
            child: _qrData != null
                ? QrImageView(
                    data: _qrData!,
                    version: QrVersions.auto,
                    size: 186,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF111827),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF111827),
                    ),
                    gapless: true,
                  )
                : _isLoading
                    ? const CircularProgressIndicator(color: _lineBlue)
                    : Text(
                        _errorText ?? 'QR을 불러올 수 없습니다',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isLow ? AppTheme.cardElevated : _softBlue,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isLow ? AppTheme.warning : AppTheme.borderLight,
            ),
          ),
          child: Text(
            '유효시간 ${_formatRemaining(_remainingSeconds)}',
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              color: isLow ? AppTheme.warning : AppTheme.goldLight,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _InactiveQrSection extends StatelessWidget {
  final TicketStatus status;

  const _InactiveQrSection({required this.status});

  @override
  Widget build(BuildContext context) {
    final isUsed = status == TicketStatus.used;
    final icon = isUsed ? Icons.done_all_rounded : Icons.cancel_rounded;
    final color = isUsed ? _success : _danger;
    final label = isUsed ? '입장 완료된 티켓입니다' : '반환된 티켓입니다';

    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.notoSans(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopMetaText extends StatelessWidget {
  final String label;
  final String value;

  const _TopMetaText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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

class _TopDataRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _TopDataRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 12,
                color: _textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: mono
                    ? GoogleFonts.robotoMono(
                        fontSize: 12,
                        color: _textPrimary,
                        fontWeight: FontWeight.w600,
                      )
                    : GoogleFonts.notoSans(
                        fontSize: 12,
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
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
              style: GoogleFonts.notoSans(
                fontSize: emphasize ? 16 : 13,
                color: emphasize ? _textPrimary : _textSecondary,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: GoogleFonts.notoSans(
              fontSize: emphasize ? 28 : 14,
              color: valueColor ?? _textPrimary,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: emphasize ? -0.4 : 0,
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
          ],
        ),
      ),
    );
  }
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

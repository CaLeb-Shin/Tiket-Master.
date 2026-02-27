import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:melon_core/app/theme.dart';
import 'package:melon_core/widgets/premium_effects.dart';
import 'package:melon_core/data/models/ticket.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/ticket_repository.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/services/auth_service.dart';

const _lineBlue = AppTheme.gold;
const _softBlue = AppTheme.surface;
const _surface = AppTheme.background;
const _cardBorder = AppTheme.border;
const _textPrimary = AppTheme.textPrimary;
const _textSecondary = AppTheme.textSecondary;

class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.value?.uid;

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(
          '나의 티켓',
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
      body: userId == null
          ? _LoginRequired(
              onLogin: () => context.push('/login'),
            )
          : _TicketBody(userId: userId),
    );
  }
}

class _TicketBody extends ConsumerWidget {
  final String userId;

  const _TicketBody({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(myTicketsStreamProvider(userId));

    return ticketsAsync.when(
      data: (tickets) {
        // orderId별 티켓 수 집계 (통합 QR 표시용)
        final orderCounts = <String, int>{};
        for (final t in tickets) {
          if (t.orderId.isNotEmpty && t.status == TicketStatus.issued) {
            orderCounts[t.orderId] = (orderCounts[t.orderId] ?? 0) + 1;
          }
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _TicketSummary(totalCount: tickets.length),
            ),
            if (tickets.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyTicketState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                sliver: SliverList.separated(
                  itemCount: tickets.length,
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    final showGroupQr = (orderCounts[ticket.orderId] ?? 0) >= 2;
                    return _TicketCard(
                      ticket: ticket,
                      showGroupQr: showGroupQr,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                ),
              ),
          ],
        );
      },
      loading: () => Column(
        children: List.generate(5, (_) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ShimmerLoading(height: 80, borderRadius: 14),
        )),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '티켓을 불러오지 못했습니다\n$error',
            textAlign: TextAlign.center,
            style: AppTheme.nanum(
              color: AppTheme.error,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketSummary extends StatelessWidget {
  final int totalCount;

  const _TicketSummary({required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                today,
                style: AppTheme.nanum(
                  fontSize: 13,
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '스마트티켓 $totalCount매',
              style: AppTheme.nanum(
                fontSize: 13,
                color: _lineBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends ConsumerWidget {
  final Ticket ticket;
  final bool showGroupQr;

  const _TicketCard({required this.ticket, this.showGroupQr = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(ticket.eventId));

    return eventAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: ShimmerLoading(height: 80, borderRadius: 14),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (event) {
        if (event == null) return const SizedBox.shrink();

        final dateText =
            DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(event.startAt);
        final timeText = DateFormat('HH:mm', 'ko_KR').format(event.startAt);
        final statusMeta = _statusMeta(ticket.status);
        final venueText = (event.venueName == null || event.venueName!.isEmpty)
            ? '공연장 정보 없음'
            : event.venueName!;

        return PressableScale(
          onTap: () => context.push('/tickets/${ticket.id}'),
          child: Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: AppTheme.gold.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateText,
                          style: AppTheme.nanum(
                            color: AppTheme.onAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusMeta.background,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusMeta.label,
                          style: AppTheme.nanum(
                            color: statusMeta.foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.nanum(
                          color: _textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          shadows: AppTheme.textShadow,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _stationBlock(
                              title: '입장시각',
                              subtitle: timeText,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 22,
                            color: AppTheme.goldLight,
                          ),
                          Expanded(
                            child: _stationBlock(
                              title: '공연장',
                              subtitle: venueText,
                              alignEnd: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SeatInfoRow(ticket: ticket, ref: ref),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: _softBlue,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(13)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => context.push('/event/${event.id}'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(13),
                              ),
                            ),
                          ),
                          child: Text(
                            '공연 정보',
                            style: AppTheme.nanum(
                              fontWeight: FontWeight.w700,
                              fontSize: showGroupQr ? 13 : 15,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 44,
                        color: AppTheme.border,
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () =>
                              context.push('/tickets/${ticket.id}'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(showGroupQr ? 0 : 13),
                              ),
                            ),
                          ),
                          child: Text(
                            'QR 보기',
                            style: AppTheme.nanum(
                              fontWeight: FontWeight.w700,
                              fontSize: showGroupQr ? 13 : 15,
                            ),
                          ),
                        ),
                      ),
                      if (showGroupQr) ...[
                        Container(
                          width: 1,
                          height: 44,
                          color: AppTheme.border,
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () => context.push(
                              '/tickets/${ticket.id}?groupQr=true&orderId=${ticket.orderId}',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.gold,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(13),
                                ),
                              ),
                            ),
                            child: Text(
                              '통합 QR',
                              style: AppTheme.nanum(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppTheme.gold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _stationBlock({
    required String title,
    required String subtitle,
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.nanum(
            fontSize: 12,
            color: _textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.nanum(
            fontSize: 20,
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            shadows: AppTheme.textShadowStrong,
          ),
        ),
      ],
    );
  }

  _TicketStatusMeta _statusMeta(TicketStatus status) {
    switch (status) {
      case TicketStatus.issued:
        return const _TicketStatusMeta(
          label: '스마트티켓',
          foreground: AppTheme.onAccent,
          background: AppTheme.gold,
        );
      case TicketStatus.used:
        return const _TicketStatusMeta(
          label: '이용완료',
          foreground: AppTheme.success,
          background: Color(0x1A30D158),
        );
      case TicketStatus.canceled:
        return const _TicketStatusMeta(
          label: '반환완료',
          foreground: AppTheme.error,
          background: Color(0x1AFF5A5F),
        );
    }
  }
}

class _SeatInfoRow extends StatelessWidget {
  final Ticket ticket;
  final WidgetRef ref;

  const _SeatInfoRow({required this.ticket, required this.ref});

  static const _gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFF6B4FA0),
    'S': Color(0xFF2D6A4F),
    'A': Color(0xFF3B7DD8),
  };

  @override
  Widget build(BuildContext context) {
    if (ticket.isStanding) {
      return _buildRow(
        badge: _gradeBadge('스탠딩', const Color(0xFF607D8B)),
        text: ticket.entryNumber != null
            ? '입장번호 ${ticket.entryNumber}번'
            : '자유석',
        checkedIn: ticket.isEntryCheckedIn,
      );
    }

    if (ticket.seatId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder(
      future: ref.read(seatRepositoryProvider).getSeat(ticket.seatId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildRow(
            badge: _gradeBadge('···', AppTheme.textTertiary),
            text: '좌석 정보 불러오는 중',
            checkedIn: false,
          );
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return _buildRow(
            badge: _gradeBadge('좌석', AppTheme.textSecondary),
            text: '좌석 배정 완료',
            checkedIn: ticket.isEntryCheckedIn,
          );
        }
        final seat = snapshot.data!;
        final grade = seat.grade ?? '';
        final color = _gradeColors[grade] ?? AppTheme.textSecondary;
        final location = seat.row != null && seat.row!.isNotEmpty
            ? '${seat.block}구역 ${seat.row}열 ${seat.number}번'
            : '${seat.block}구역 ${seat.number}번';

        return _buildRow(
          badge: _gradeBadge(grade.isNotEmpty ? grade : '일반', color),
          text: location,
          checkedIn: ticket.isEntryCheckedIn,
        );
      },
    );
  }

  Widget _buildRow({
    required Widget badge,
    required String text,
    required bool checkedIn,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        children: [
          badge,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.nanum(
                fontSize: 12,
                color: _textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (checkedIn) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
            const SizedBox(width: 3),
            Text(
              '입장완료',
              style: AppTheme.nanum(
                fontSize: 11,
                color: AppTheme.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gradeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: AppTheme.nanum(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TicketStatusMeta {
  final String label;
  final Color foreground;
  final Color background;

  const _TicketStatusMeta({
    required this.label,
    required this.foreground,
    required this.background,
  });
}

class _LoginRequired extends StatelessWidget {
  final VoidCallback onLogin;

  const _LoginRequired({required this.onLogin});

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
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppTheme.gold,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '로그인 후 모바일 티켓을 확인할 수 있습니다',
              style: AppTheme.nanum(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
                shadows: AppTheme.textShadow,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: FilledButton(
                onPressed: onLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: AppTheme.onAccent,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  '로그인',
                  style: AppTheme.nanum(
                    fontWeight: FontWeight.w700,
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

class _EmptyTicketState extends StatelessWidget {
  const _EmptyTicketState();

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
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: const Icon(
                Icons.confirmation_number_outlined,
                color: AppTheme.gold,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '보유한 티켓이 없습니다',
              style: AppTheme.nanum(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
                shadows: AppTheme.textShadow,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '예매 후 발급된 모바일 티켓이 이곳에 표시됩니다.',
              textAlign: TextAlign.center,
              style: AppTheme.nanum(
                fontSize: 13,
                color: _textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

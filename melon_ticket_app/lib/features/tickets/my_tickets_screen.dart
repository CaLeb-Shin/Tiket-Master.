import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../data/models/ticket.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../services/auth_service.dart';

const _navy = Color(0xFF0D3E67);
const _lineBlue = Color(0xFF2F6FB2);
const _softBlue = Color(0xFFE7F0FA);
const _surface = Color(0xFFF3F5F8);
const _cardBorder = Color(0xFFD7DFE8);
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _textMuted = Color(0xFF94A3B8);

class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.value?.uid;

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(
          '나의 티켓',
          style: GoogleFonts.notoSans(
            color: Colors.white,
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
                    return _TicketCard(ticket: tickets[index]);
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: _lineBlue),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '티켓을 불러오지 못했습니다\n$error',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              color: const Color(0xFFB42318),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                today,
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '스마트티켓 $totalCount매',
              style: GoogleFonts.notoSans(
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

  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(ticket.eventId));

    return eventAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: _lineBlue),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (event) {
        if (event == null) return const SizedBox.shrink();

        final dateText =
            DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(event.startAt);
        final issuedAtText =
            DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(ticket.issuedAt);
        final timeText = DateFormat('HH:mm', 'ko_KR').format(event.startAt);
        final statusMeta = _statusMeta(ticket.status);
        final venueText = (event.venueName == null || event.venueName!.isEmpty)
            ? '공연장 정보 없음'
            : event.venueName!;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/tickets/${ticket.id}'),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: _lineBlue,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateText,
                          style: GoogleFonts.notoSans(
                            color: Colors.white,
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
                          style: GoogleFonts.notoSans(
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
                        style: GoogleFonts.notoSans(
                          color: _textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
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
                            color: _lineBlue,
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
                      _metaRow(
                        label: '승차권번호',
                        value: ticket.id,
                        mono: true,
                      ),
                      _metaRow(
                        label: '발행시각',
                        value: issuedAtText,
                      ),
                      if (!event.isSeatsRevealed)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '좌석은 ${DateFormat('M월 d일 HH:mm', 'ko_KR').format(event.revealAt)} 공개',
                            style: GoogleFonts.notoSans(
                              fontSize: 11,
                              color: _textMuted,
                            ),
                          ),
                        ),
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
                          onPressed: () =>
                              context.push('/tickets/${ticket.id}'),
                          style: TextButton.styleFrom(
                            foregroundColor: _navy,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(13),
                              ),
                            ),
                          ),
                          child: Text(
                            'QR 보기',
                            style: GoogleFonts.notoSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 44,
                        color: const Color(0xFFB8C9D9),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () => context.push('/event/${event.id}'),
                          style: TextButton.styleFrom(
                            foregroundColor: _navy,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(13),
                              ),
                            ),
                          ),
                          child: Text(
                            '공연 정보',
                            style: GoogleFonts.notoSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metaRow({
    required String label,
    required String value,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDDE3EA)),
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
          style: GoogleFonts.notoSans(
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
          style: GoogleFonts.notoSans(
            fontSize: 20,
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
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
          foreground: Color(0xFF065F46),
          background: Color(0xFFD1FAE5),
        );
      case TicketStatus.used:
        return const _TicketStatusMeta(
          label: '이용완료',
          foreground: Color(0xFF1D4ED8),
          background: Color(0xFFDBEAFE),
        );
      case TicketStatus.canceled:
        return const _TicketStatusMeta(
          label: '반환완료',
          foreground: Color(0xFFB91C1C),
          background: Color(0xFFFEE2E2),
        );
    }
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: _lineBlue,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '로그인 후 모바일 티켓을 확인할 수 있습니다',
              style: GoogleFonts.notoSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: FilledButton(
                onPressed: onLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: _lineBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  '로그인',
                  style: GoogleFonts.notoSans(
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: const Icon(
                Icons.confirmation_number_outlined,
                color: _lineBlue,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '보유한 티켓이 없습니다',
              style: GoogleFonts.notoSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '예매 후 발급된 모바일 티켓이 이곳에 표시됩니다.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSans(
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

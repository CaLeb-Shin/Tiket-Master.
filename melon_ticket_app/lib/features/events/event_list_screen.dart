import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/services/auth_service.dart';

class EventListScreen extends ConsumerWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);
    final authState = ref.watch(authStateProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.confirmation_number_rounded,
                color: AppTheme.primaryColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '멜론티켓',
              style: GoogleFonts.notoSans(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          // 내 티켓
          if (authState.value != null)
            IconButton(
              icon: const Icon(Icons.confirmation_number_outlined),
              onPressed: () => context.push('/tickets'),
              tooltip: '내 티켓',
              style: IconButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
              ),
            ),
          // 어드민/스태프 메뉴
          if (currentUser.value?.isStaff == true)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'scanner':
                    context.push('/staff/scanner');
                    break;
                  case 'admin':
                    context.push('/admin');
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'scanner',
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_scanner_rounded,
                          color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Text('입장 스캐너', style: GoogleFonts.notoSans()),
                    ],
                  ),
                ),
                if (currentUser.value?.isAdmin == true)
                  PopupMenuItem(
                    value: 'admin',
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings_rounded,
                            color: AppTheme.textSecondary, size: 20),
                        const SizedBox(width: 12),
                        Text('관리자', style: GoogleFonts.notoSans()),
                      ],
                    ),
                  ),
              ],
            ),
          // 로그인/로그아웃
          IconButton(
            icon: Icon(
              authState.value != null
                  ? Icons.logout_rounded
                  : Icons.login_rounded,
            ),
            onPressed: () {
              if (authState.value != null) {
                ref.read(authServiceProvider).signOut();
              } else {
                context.push('/login');
              }
            },
            tooltip: authState.value != null ? '로그아웃' : '로그인',
            style: IconButton.styleFrom(
              foregroundColor: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: eventsAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.dividerColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.event_busy_rounded,
                      size: 48,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '등록된 공연이 없습니다',
                    style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '새로운 공연이 곧 등록될 예정입니다',
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return _EventCard(event: event);
            },
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              Text(
                '공연 목록을 불러오는 중...',
                style: GoogleFonts.notoSans(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppTheme.errorColor,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '오류가 발생했습니다',
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.refresh(eventsStreamProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 시도'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(160, 48),
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

class _EventCard extends StatelessWidget {
  final Event event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('M월 d일 (E) HH:mm', 'ko_KR');
    final priceFormat = NumberFormat('#,###', 'ko_KR');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: AppShadows.small,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/event/${event.id}'),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 이미지
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (event.imageUrl != null)
                        Image.network(
                          event.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _ImagePlaceholder(),
                        )
                      else
                        _ImagePlaceholder(),

                      // 그라데이션 오버레이
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 상태 뱃지
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _StatusBadge(event: event),
                      ),

                      // 잔여 좌석
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '잔여 ${event.availableSeats}석',
                            style: GoogleFonts.notoSans(
                              color: event.availableSeats > 0
                                  ? Colors.white
                                  : const Color(0xFFFF6B6B),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 콘텐츠
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목
                    Text(
                      event.title,
                      style: GoogleFonts.notoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

                    // 날짜와 가격
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 15,
                                color: AppTheme.textTertiary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateFormat.format(event.startAt),
                                style: GoogleFonts.notoSans(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${priceFormat.format(event.price)}원',
                            style: GoogleFonts.notoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryDark,
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
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.dividerColor,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 48,
          color: AppTheme.textTertiary.withOpacity(0.5),
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
    Color bgColor;
    Color textColor;
    String text;
    IconData icon;

    if (event.status == EventStatus.soldOut || event.availableSeats == 0) {
      bgColor = const Color(0xFFEF4444);
      textColor = Colors.white;
      text = '매진';
      icon = Icons.block_rounded;
    } else if (event.isOnSale) {
      bgColor = AppTheme.primaryColor;
      textColor = Colors.white;
      text = '판매중';
      icon = Icons.check_circle_rounded;
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      bgColor = const Color(0xFFF59E0B);
      textColor = Colors.white;
      text = '판매예정';
      icon = Icons.schedule_rounded;
    } else {
      bgColor = const Color(0xFF6B7280);
      textColor = Colors.white;
      text = '판매종료';
      icon = Icons.cancel_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.notoSans(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

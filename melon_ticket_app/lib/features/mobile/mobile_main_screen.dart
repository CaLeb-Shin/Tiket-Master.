import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/models/event.dart';
import '../tickets/my_tickets_screen.dart';

class MobileMainScreen extends ConsumerStatefulWidget {
  const MobileMainScreen({super.key});

  @override
  ConsumerState<MobileMainScreen> createState() => _MobileMainScreenState();
}

class _MobileMainScreenState extends ConsumerState<MobileMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoggedIn = authState.value != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const _HomeTab(),
          isLoggedIn
              ? const MyTicketsScreen()
              : _LoginRequiredTab(onLogin: () => context.push('/login')),
          _ProfileTab(isLoggedIn: isLoggedIn),
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
                  icon: Icons.home_rounded,
                  label: '홈',
                  isSelected: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.confirmation_number_rounded,
                  label: '내 티켓',
                  isSelected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: '마이',
                  isSelected: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Nav Item ───
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
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
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.gold : AppTheme.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppTheme.gold : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Home Tab ───
class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return CustomScrollView(
      slivers: [
        // ── 앱바 ──
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.surface,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 20,
              right: 20,
              bottom: 14,
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'M',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFFDF3F6),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '멜론티켓',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 세그먼트 메뉴 ──
        SliverToBoxAdapter(
          child: Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryChip(label: '전체', isSelected: true),
                  const SizedBox(width: 8),
                  _CategoryChip(label: '콘서트'),
                  const SizedBox(width: 8),
                  _CategoryChip(label: '뮤지컬'),
                  const SizedBox(width: 8),
                  _CategoryChip(label: '연극'),
                  const SizedBox(width: 8),
                  _CategoryChip(label: '클래식'),
                ],
              ),
            ),
          ),
        ),

        // ── 구분선 ──
        SliverToBoxAdapter(
          child: Container(height: 0.5, color: AppTheme.border),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.gold.withOpacity(0.18),
                    AppTheme.cardElevated,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.gold.withOpacity(0.25),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.goldSubtle,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '추천',
                          style: GoogleFonts.notoSans(
                            color: AppTheme.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '모바일 예매 추천',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'AI 좌석 추천 + 360° 시야 + 모바일티켓',
                    style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '좌석 선택 화면에서 구역별 시야를 확인하고 취소/환불 정책까지 한 번에 확인하세요.',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: OutlinedButton(
              onPressed: () => context.push('/demo-flow'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.gold.withOpacity(0.55)),
                foregroundColor: AppTheme.gold,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '공연등록부터 스캔까지 데모 실행',
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        // ── 공연 목록 ──
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
                        color: AppTheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ERROR',
                        style: GoogleFonts.robotoMono(
                          color: AppTheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '공연 정보를 불러올 수 없습니다',
                      style:
                          GoogleFonts.notoSans(color: AppTheme.textSecondary),
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

// ─── Category Chip ───
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  const _CategoryChip({required this.label, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.gold : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.gold : AppTheme.border,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSans(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? const Color(0xFFFDF3F6) : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ─── Event Card (NOL 인터파크 스타일 수평 카드) ───
class _EventCard extends StatelessWidget {
  final Event event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
    final priceFormat = NumberFormat('#,###');

    return GestureDetector(
      onTap: () => context.push('/event/${event.id}'),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 포스터 썸네일 ──
            Container(
              width: 100,
              height: 140,
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(8),
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
                        color: AppTheme.card,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _PosterPlaceholder(),
                    )
                  else
                    _PosterPlaceholder(),
                  // 상태 뱃지
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _StatusBadge(event: event),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // ── 정보 ──
            Expanded(
              child: SizedBox(
                height: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 카테고리
                    if (event.category != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          event.category!,
                          style: GoogleFonts.notoSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),

                    // 제목
                    Text(
                      event.title,
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // 날짜
                    Text(
                      dateFormat.format(event.startAt),
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),

                    // 장소
                    if (event.venueName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.venueName!,
                        style: GoogleFonts.notoSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const Spacer(),

                    // 가격
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
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            letterSpacing: 1.0,
            color: AppTheme.gold.withOpacity(0.45),
            fontWeight: FontWeight.w700,
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
      label = '예매중';
      bgColor = AppTheme.success;
      fgColor = Colors.white;
    } else if (event.status == EventStatus.soldOut ||
        event.availableSeats == 0) {
      label = '매진';
      bgColor = AppTheme.error;
      fgColor = Colors.white;
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      label = '예매예정';
      bgColor = AppTheme.gold;
      fgColor = const Color(0xFFFDF3F6);
    } else {
      label = '종료';
      bgColor = AppTheme.textTertiary;
      fgColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
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
              color: AppTheme.goldSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'EMPTY',
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                color: AppTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '등록된 공연이 없습니다',
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Login Required Tab ───
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
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Text(
                      'LOGIN',
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        color: AppTheme.gold.withOpacity(0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '로그인이 필요합니다',
                  style: GoogleFonts.notoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '티켓을 확인하려면 로그인해주세요',
                  style: GoogleFonts.notoSans(
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

// ─── Profile Tab ───
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
              '마이페이지',
              style: GoogleFonts.notoSans(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),

            // 사용자 정보 카드
            if (isLoggedIn)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppTheme.goldGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          profileInitial,
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFFDF3F6),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1,
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
                            style: GoogleFonts.notoSans(
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
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '관리자',
                                style: GoogleFonts.notoSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
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
                icon: Icons.login_rounded,
                title: '로그인',
                subtitle: '계정에 로그인하세요',
                onTap: () => context.push('/login'),
              ),

            const SizedBox(height: 16),

            // 스태프/관리자 메뉴
            if (currentUser.value?.isStaff == true) ...[
              _MenuItem(
                icon: Icons.qr_code_scanner_rounded,
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
                onTap: () => context.push('/admin/events/create'),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.location_city_rounded,
                title: '공연장 관리',
                subtitle: '좌석배치도 · 3D 시야 업로드',
                onTap: () => context.push('/admin/venues'),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.admin_panel_settings_rounded,
                title: '관리자 대시보드',
                subtitle: '공연 및 좌석 관리',
                onTap: () => context.push('/admin'),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 16),

            if (isLoggedIn)
              _MenuItem(
                icon: Icons.logout_rounded,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppTheme.error.withOpacity(0.15)
                    : AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isDestructive ? AppTheme.error : AppTheme.textSecondary,
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
                    style: GoogleFonts.notoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color:
                          isDestructive ? AppTheme.error : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

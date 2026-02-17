import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/services/auth_service.dart';

const _deckBgTop = Color(0xFF080C14);
const _deckBgBottom = Color(0xFF0E1626);
const _deckPanel = Color(0xFF121C2E);
const _deckPanelSoft = Color(0xFF19253B);
const _deckBorder = Color(0xFF29354A);
const _deckText = Color(0xFFF3F6FB);
const _deckTextDim = Color(0xFF97A4BB);
const _deckBrand = Color(0xFFCFB36A);
const _deckMint = Color(0xFF5CD6B3);

class WebAdminDashboard extends ConsumerStatefulWidget {
  const WebAdminDashboard({super.key});

  @override
  ConsumerState<WebAdminDashboard> createState() => _WebAdminDashboardState();
}

class _WebAdminDashboardState extends ConsumerState<WebAdminDashboard> {
  int _selectedMenuIndex = 0;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser.isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
      );
    }

    if (currentUser.value?.isAdmin != true) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: AppTheme.textTertiary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '관리자 권한이 필요합니다',
                    style: GoogleFonts.notoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '관리자 계정으로 로그인한 뒤 다시 접근해 주세요.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: () => context.push('/setup'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          foregroundColor: const Color(0xFFFDF3F6),
                        ),
                        child: Text(
                          '승인 요청',
                          style:
                              GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => context.go('/'),
                        child: Text(
                          '홈으로 이동',
                          style:
                              GoogleFonts.notoSans(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _deckBgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: _AdminBackdrop()),
          Row(
            children: [
              _Sidebar(
                selectedIndex: _selectedMenuIndex,
                onMenuSelected: (index) =>
                    setState(() => _selectedMenuIndex = index),
                onLogout: () async {
                  await ref.read(authServiceProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
              Expanded(child: _buildContent()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedMenuIndex) {
      case 0:
        return const _DashboardContent();
      case 1:
        return const _EventsContent();
      case 2:
        return const _StatsContent();
      default:
        return const _DashboardContent();
    }
  }
}

class _AdminBackdrop extends StatelessWidget {
  const _AdminBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_deckBgTop, _deckBgBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _GridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x19A1B1C8)
      ..strokeWidth = 1;
    const gap = 64.0;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 사이드바 ───
class _Sidebar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onMenuSelected;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.selectedIndex,
    required this.onMenuSelected,
    required this.onLogout,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  int _hoveredIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 278,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xD9101726), Color(0xEE0B111D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          right: BorderSide(color: _deckBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          // 로고
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE2CA85), Color(0xFFB99336)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _deckBrand.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'M',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFFDF3F6),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MELON',
                      style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _deckBrand,
                        letterSpacing: 1.2,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      'TICKET ADMIN',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _deckTextDim,
                        letterSpacing: 2.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Container(height: 1, color: _deckBorder),
          ),

          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ADMIN COMMAND',
                style: GoogleFonts.robotoMono(
                  color: _deckTextDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 메뉴
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _buildMenuItem(0, '01', '대시보드'),
                  const SizedBox(height: 4),
                  _buildMenuItem(1, '02', '공연 관리'),
                  const SizedBox(height: 4),
                  _buildMenuItem(2, '03', '통계'),
                  const SizedBox(height: 4),
                  _buildMenuItem(
                    3,
                    '04',
                    '공연장 관리',
                    selectable: false,
                    onTap: () => context.push('/venues'),
                  ),
                ],
              ),
            ),
          ),

          // 로그아웃
          Padding(
            padding: const EdgeInsets.all(16),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onLogout,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111A2A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _deckBorder, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '로그아웃',
                        style: GoogleFonts.notoSans(
                          color: _deckTextDim,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    int index,
    String code,
    String label, {
    bool selectable = true,
    VoidCallback? onTap,
  }) {
    final isSelected = selectable && widget.selectedIndex == index;
    final isHovered = _hoveredIndex == index;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      child: GestureDetector(
        onTap: onTap ?? () => widget.onMenuSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1D2A42)
                : isHovered
                    ? const Color(0xFF141F32)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF334563) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _deckBrand.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 22,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isSelected ? _deckBrand : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                width: 28,
                alignment: Alignment.centerLeft,
                child: Text(
                  code,
                  style: GoogleFonts.robotoMono(
                    color: isSelected ? _deckBrand : _deckTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.notoSans(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? _deckText : _deckTextDim,
                  fontSize: 14,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _deckMint,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _deckMint.withOpacity(0.55),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 대시보드 ───
class _DashboardContent extends ConsumerWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A2740), Color(0xFF121C2E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _deckBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 980;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: compact ? constraints.maxWidth : 640,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'OPERATIONS DECK',
                                    style: GoogleFonts.robotoMono(
                                      color: _deckTextDim,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '공연 운영 대시보드',
                                    style: GoogleFonts.notoSans(
                                      color: _deckText,
                                      fontSize: compact ? 30 : 38,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.0,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '예매·좌석·발권 상태를 한 화면에서 빠르게 파악하고 운영 액션으로 바로 이동하세요.',
                                    style: GoogleFonts.notoSans(
                                      color: _deckTextDim,
                                      fontSize: 14,
                                      height: 1.55,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _GoldButton(
                                  label: '공연장 관리',
                                  onTap: () => context.push('/venues'),
                                ),
                                _GoldButton(
                                  label: '새 공연 등록',
                                  onTap: () =>
                                      context.push('/events/create'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _DeckTag(label: '실시간 이벤트 상태'),
                            _DeckTag(label: '좌석 배정/검수'),
                            _DeckTag(label: '발권 운영'),
                            _DeckTag(label: '환불 정책 모니터링'),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              eventsAsync.when(
                data: (events) {
                  final totalEvents = events.length;
                  final activeEvents = events.where((e) => e.isOnSale).length;
                  final totalSeats =
                      events.fold<int>(0, (sum, e) => sum + e.totalSeats);
                  final soldSeats = events.fold<int>(
                    0,
                    (sum, e) => sum + (e.totalSeats - e.availableSeats),
                  );
                  final utilization = totalSeats > 0
                      ? ((soldSeats / totalSeats) * 100).toStringAsFixed(1)
                      : '0.0';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              code: 'EVENT',
                              label: '전체 공연',
                              value: '$totalEvents',
                              footnote: '현재 등록된 운영 건수',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              code: 'LIVE',
                              label: '판매 중',
                              value: '$activeEvents',
                              accentColor: _deckMint,
                              footnote: '즉시 예매 가능한 공연',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              code: 'SEAT',
                              label: '총 좌석',
                              value: NumberFormat('#,###').format(totalSeats),
                              footnote: '등록 좌석 풀',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              code: 'TICK',
                              label: '판매 티켓',
                              value: NumberFormat('#,###').format(soldSeats),
                              accentColor: _deckBrand,
                              footnote: '좌석 점유율 $utilization%',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _DarkCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 18, 24, 14),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '최근 공연',
                                    style: GoogleFonts.notoSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: _deckText,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  Text(
                                    '최신 5건',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 11,
                                      color: _deckTextDim,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(height: 1, color: _deckBorder),
                            _EventsTable(events: events.take(5).toList()),
                          ],
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(80),
                    child: CircularProgressIndicator(color: _deckBrand),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(80),
                    child: Text(
                      '오류: $e',
                      style: GoogleFonts.notoSans(color: _deckTextDim),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckTag extends StatelessWidget {
  final String label;

  const _DeckTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF22324D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF3A4F70)),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSans(
          color: _deckText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── 통계 카드 (다크 테마) ───
class _StatCard extends StatefulWidget {
  final String code;
  final String label;
  final String value;
  final Color? accentColor;
  final String? footnote;

  const _StatCard({
    required this.code,
    required this.label,
    required this.value,
    this.accentColor,
    this.footnote,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? _deckTextDim;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isHovered
                ? const [Color(0xFF1A2740), Color(0xFF152135)]
                : const [Color(0xFF151F31), Color(0xFF121B2B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered ? accent.withOpacity(0.45) : _deckBorder,
            width: 1,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: accent.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.code,
                    style: GoogleFonts.robotoMono(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 1,
                    color: _deckBorder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.value,
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _deckText,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: GoogleFonts.notoSans(
                fontSize: 13,
                color: _deckTextDim,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.footnote != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.footnote!,
                style: GoogleFonts.notoSans(
                  fontSize: 11,
                  color: _deckTextDim.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 다크 카드 ───
class _DarkCard extends StatelessWidget {
  final Widget child;

  const _DarkCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _deckPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _deckBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── 골드 버튼 ───
class _GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _GoldButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<_GoldButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE5CB82), Color(0xFFB7933A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF9A7A2C), width: 1),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: _deckBrand.withOpacity(0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.notoSans(
                  color: const Color(0xFFFDF3F6),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 1.5,
                color: const Color(0xFFFDF3F6).withOpacity(0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 공연 테이블 ───
class _EventsTable extends StatelessWidget {
  final List<Event> events;

  const _EventsTable({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(60),
        child: Center(
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _deckPanelSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _deckBorder),
                ),
                child: Text(
                  'NO EVENTS',
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    color: _deckBrand.withOpacity(0.8),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '등록된 공연이 없습니다',
                style: GoogleFonts.notoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _deckTextDim,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '새 공연을 등록해보세요',
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  color: _deckTextDim.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: const BoxDecoration(color: _deckPanelSoft),
          child: Row(
            children: [
              SizedBox(
                width: 280,
                child: Text('공연명',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _deckTextDim,
                    )),
              ),
              Expanded(
                child: Text('일시',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _deckTextDim,
                    )),
              ),
              SizedBox(
                width: 120,
                child: Text('좌석',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _deckTextDim,
                    )),
              ),
              SizedBox(
                width: 100,
                child: Text('상태',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _deckTextDim,
                    )),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Container(height: 1, color: _deckBorder),

        // 행
        ...events.map((event) => _EventRow(event: event)),
      ],
    );
  }
}

class _EventRow extends StatefulWidget {
  final Event event;
  const _EventRow({required this.event});

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final soldSeats = event.totalSeats - event.availableSeats;
    final ratio = event.totalSeats > 0 ? soldSeats / event.totalSeats : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _isHovered ? const Color(0xFF18243A) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // 공연명
            SizedBox(
              width: 280,
              child: Row(
                children: [
                  // 포스터 썸네일
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _deckPanelSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _deckBorder, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: event.imageUrl != null && event.imageUrl!.isNotEmpty
                        ? Image.network(
                            event.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _PosterFallback(title: event.title),
                          )
                        : _PosterFallback(title: event.title),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _deckText,
                          ),
                        ),
                        if (event.venueName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            event.venueName!,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSans(
                              fontSize: 12,
                              color: _deckTextDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 일시
            Expanded(
              child: Text(
                DateFormat('MM.dd (E) HH:mm', 'ko_KR').format(event.startAt),
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  color: _deckTextDim,
                ),
              ),
            ),

            // 좌석 (프로그레스 바 포함)
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$soldSeats / ${NumberFormat('#,###').format(event.totalSeats)}',
                    style: GoogleFonts.notoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _deckTextDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 3,
                      backgroundColor: _deckBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        ratio > 0.8
                            ? const Color(0xFFE3606D)
                            : ratio > 0.5
                                ? _deckBrand
                                : _deckMint,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 상태
            SizedBox(
              width: 100,
              child: _StatusBadge(event: event),
            ),

            // 메뉴
            SizedBox(
              width: 48,
              child: PopupMenuButton<String>(
                color: _deckPanelSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: _deckBorder, width: 1),
                ),
                onSelected: (value) {
                  if (value == 'seats') {
                    context.push('/events/${event.id}/seats');
                  }
                  if (value == 'assignments') {
                    context.push('/events/${event.id}/assignments');
                  }
                  if (value == 'bookers') {
                    context.push('/events/${event.id}/bookers');
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'seats',
                    child: Text(
                      '좌석 관리',
                      style:
                          GoogleFonts.notoSans(fontSize: 13, color: _deckText),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'assignments',
                    child: Text(
                      '배정 현황',
                      style:
                          GoogleFonts.notoSans(fontSize: 13, color: _deckText),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'bookers',
                    child: Text(
                      '예매자 목록',
                      style:
                          GoogleFonts.notoSans(fontSize: 13, color: _deckText),
                    ),
                  ),
                ],
                child: Container(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '옵션',
                    style: GoogleFonts.notoSans(
                      color: _deckTextDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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

class _PosterFallback extends StatelessWidget {
  final String title;

  const _PosterFallback({required this.title});

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'M';

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E2B43), Color(0xFF152035)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.robotoMono(
            color: _deckBrand.withOpacity(0.85),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── 상태 뱃지 (다크 테마) ───
class _StatusBadge extends StatelessWidget {
  final Event event;

  const _StatusBadge({required this.event});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;

    if (event.status == EventStatus.soldOut || event.availableSeats == 0) {
      color = const Color(0xFFE3606D);
      text = '매진';
    } else if (event.isOnSale) {
      color = _deckMint;
      text = '판매중';
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      color = _deckBrand;
      text = '판매예정';
    } else {
      color = _deckTextDim;
      text = '종료';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.notoSans(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─── 공연 관리 탭 ───
class _EventsContent extends ConsumerWidget {
  const _EventsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '공연 관리',
                    style: GoogleFonts.notoSans(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: _deckText,
                      letterSpacing: -0.8,
                    ),
                  ),
                  _GoldButton(
                    label: '새 공연 등록',
                    onTap: () => context.push('/events/create'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _DarkCard(
                child: eventsAsync.when(
                  data: (events) => _EventsTable(events: events),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(80),
                    child: Center(
                      child: CircularProgressIndicator(color: _deckBrand),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(80),
                    child: Center(
                      child: Text(
                        '오류: $e',
                        style: GoogleFonts.notoSans(color: _deckTextDim),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 통계 탭 ───
class _StatsContent extends ConsumerWidget {
  const _StatsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(allEventsStreamProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '통계 대시보드',
                style: GoogleFonts.notoSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: _deckText,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: eventsAsync.when(
                  data: (events) => _StatsBody(events: events),
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: _deckBrand),
                  ),
                  error: (e, _) => Center(
                    child: Text('오류: $e',
                        style: GoogleFonts.notoSans(color: Colors.redAccent)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final List<Event> events;
  const _StatsBody({required this.events});

  @override
  Widget build(BuildContext context) {
    final priceFormat = NumberFormat('#,###');
    final now = DateTime.now();

    // 통계 계산
    final totalEvents = events.length;
    final activeEvents = events.where((e) => e.status == EventStatus.active).length;
    final totalSeats = events.fold<int>(0, (s, e) => s + e.totalSeats);
    final soldSeats = events.fold<int>(0, (s, e) => s + (e.totalSeats - e.availableSeats));
    final occupancyRate = totalSeats > 0 ? (soldSeats / totalSeats * 100) : 0.0;
    final estimatedRevenue = events.fold<int>(
        0, (s, e) => s + ((e.totalSeats - e.availableSeats) * e.price));
    final upcomingEvents =
        events.where((e) => e.startAt.isAfter(now)).length;
    final pastEvents = events.where((e) => e.startAt.isBefore(now)).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI 카드 행 ──
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _KpiCard(
                icon: Icons.event_rounded,
                label: '총 공연',
                value: '$totalEvents',
                subtext: '진행중 $activeEvents',
                color: _deckBrand,
              ),
              _KpiCard(
                icon: Icons.event_seat_rounded,
                label: '총 좌석 / 판매',
                value: '${priceFormat.format(soldSeats)} / ${priceFormat.format(totalSeats)}',
                subtext: '점유율 ${occupancyRate.toStringAsFixed(1)}%',
                color: _deckMint,
              ),
              _KpiCard(
                icon: Icons.payments_rounded,
                label: '예상 매출',
                value: '${priceFormat.format(estimatedRevenue)}원',
                subtext: '판매 좌석 기준',
                color: const Color(0xFFFFB347),
              ),
              _KpiCard(
                icon: Icons.calendar_month_rounded,
                label: '예정 / 종료',
                value: '$upcomingEvents / $pastEvents',
                subtext: '공연 일정',
                color: const Color(0xFF64B5F6),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ── 공연별 실적 테이블 ──
          Text(
            '공연별 실적',
            style: GoogleFonts.notoSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _deckText,
            ),
          ),
          const SizedBox(height: 12),
          _DarkCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 헤더
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _deckPanelSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _tableHeader('공연명', flex: 3),
                        _tableHeader('상태'),
                        _tableHeader('판매/전체'),
                        _tableHeader('점유율'),
                        _tableHeader('예상매출'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 데이터 행
                  ...events.map((event) {
                    final sold = event.totalSeats - event.availableSeats;
                    final rate = event.totalSeats > 0
                        ? (sold / event.totalSeats * 100)
                        : 0.0;
                    final revenue = sold * event.price;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: _deckBorder.withOpacity(0.5), width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              event.title,
                              style: GoogleFonts.notoSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _deckText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: _StatusDot(
                              label: event.status == EventStatus.active
                                  ? '진행중'
                                  : event.status == EventStatus.soldOut
                                      ? '매진'
                                      : '종료',
                              color: event.status == EventStatus.active
                                  ? _deckMint
                                  : event.status == EventStatus.soldOut
                                      ? Colors.redAccent
                                      : _deckTextDim,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '$sold / ${event.totalSeats}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.robotoMono(
                                fontSize: 12,
                                color: _deckTextDim,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _OccupancyBar(rate: rate),
                          ),
                          Expanded(
                            child: Text(
                              '${priceFormat.format(revenue)}원',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.robotoMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _deckBrand,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: flex > 1 ? TextAlign.left : TextAlign.center,
        style: GoogleFonts.notoSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _deckTextDim,
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: _DarkCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.notoSans(
                          fontSize: 11, color: _deckTextDim),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.notoSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _deckText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtext,
                      style: GoogleFonts.notoSans(
                        fontSize: 11,
                        color: color.withOpacity(0.8),
                      ),
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

class _StatusDot extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.notoSans(fontSize: 11, color: color),
        ),
      ],
    );
  }
}

class _OccupancyBar extends StatelessWidget {
  final double rate;
  const _OccupancyBar({required this.rate});

  @override
  Widget build(BuildContext context) {
    final clampedRate = rate.clamp(0.0, 100.0);
    return Column(
      children: [
        Text(
          '${clampedRate.toStringAsFixed(0)}%',
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: clampedRate >= 80
                ? _deckMint
                : clampedRate >= 50
                    ? _deckBrand
                    : _deckTextDim,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: clampedRate / 100,
              backgroundColor: _deckBorder,
              color: clampedRate >= 80
                  ? _deckMint
                  : clampedRate >= 50
                      ? _deckBrand
                      : _deckTextDim,
            ),
          ),
        ),
      ],
    );
  }
}

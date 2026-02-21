import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;
import '../../app/admin_theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

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
        backgroundColor: AdminTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AdminTheme.gold),
        ),
      );
    }

    if (currentUser.value?.isAdmin != true) {
      return Scaffold(
        backgroundColor: AdminTheme.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: AdminTheme.sage.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '관리자 권한이 필요합니다',
                    style: AdminTheme.serif(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '관리자 계정으로 로그인한 뒤 다시 접근해 주세요.',
                    textAlign: TextAlign.center,
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () => context.push('/setup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminTheme.gold,
                          foregroundColor: AdminTheme.onAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: Text(
                          '승인 요청',
                          style: AdminTheme.sans(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => context.go('/'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminTheme.textPrimary,
                          side: BorderSide(color: AdminTheme.sage.withValues(alpha: 0.3), width: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: Text(
                          '홈으로 이동',
                          style: AdminTheme.sans(fontWeight: FontWeight.w700),
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
      backgroundColor: AdminTheme.background,
      body: Row(
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

// ─── Sidebar (Editorial Light) ───
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
      width: 260,
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border(
          right: BorderSide(
              color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AdminTheme.goldGradient,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: AdminShadows.small,
                  ),
                  child: Center(
                    child: Text(
                      'M',
                      style: AdminTheme.serif(
                        color: AdminTheme.onAccent,
                        fontSize: 20,
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
                      style: AdminTheme.label(
                        fontSize: 12,
                        color: AdminTheme.gold,
                      ),
                    ),
                    Text(
                      'TICKET ADMIN',
                      style: AdminTheme.label(
                        fontSize: 8,
                        color: AdminTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            height: 0.5,
            color: AdminTheme.border,
          ),

          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'NAVIGATION',
                style: AdminTheme.label(fontSize: 9, color: AdminTheme.textTertiary),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Menu
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _buildMenuItem(0, '01', '대시보드'),
                  const SizedBox(height: 2),
                  _buildMenuItem(1, '02', '공연 관리'),
                  const SizedBox(height: 2),
                  _buildMenuItem(2, '03', '통계'),
                  const SizedBox(height: 2),
                  _buildMenuItem(
                    3,
                    '04',
                    '공연장 관리',
                    selectable: false,
                    onTap: () => context.push('/venues'),
                  ),
                  const SizedBox(height: 2),
                  // 데모 테스트 메뉴 (나중에 이 블록만 삭제하면 제거 완료)
                  _buildMenuItem(
                    4,
                    'D',
                    '데모 테스트',
                    selectable: false,
                    onTap: () => context.push('/demo'),
                  ),
                ],
              ),
            ),
          ),

          // Logout
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
                    color: AdminTheme.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AdminTheme.border, width: 0.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '로그아웃',
                        style: AdminTheme.sans(
                          color: AdminTheme.textSecondary,
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
                ? AdminTheme.gold.withValues(alpha: 0.06)
                : isHovered
                    ? AdminTheme.sage.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color:
                  isSelected ? AdminTheme.gold.withValues(alpha: 0.15) : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 20,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AdminTheme.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  code,
                  style: AdminTheme.label(
                    fontSize: 10,
                    color: isSelected ? AdminTheme.gold : AdminTheme.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AdminTheme.sans(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      isSelected ? AdminTheme.textPrimary : AdminTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AdminTheme.success,
                    shape: BoxShape.circle,
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

// ─── Dashboard Content ───
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
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                  boxShadow: AdminShadows.card,
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
                                    'OPERATIONS',
                                    style: AdminTheme.label(
                                        fontSize: 10, color: AdminTheme.sage),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '공연 운영 대시보드',
                                    style: AdminTheme.serif(
                                      fontSize: compact ? 26 : 32,
                                      fontWeight: FontWeight.w700,
                                      color: AdminTheme.textPrimary,
                                      letterSpacing: -0.5,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '예매, 좌석, 발권 상태를 한 화면에서 빠르게 파악하고 운영 액션으로 바로 이동하세요.',
                                    style: AdminTheme.sans(
                                      color: AdminTheme.textSecondary,
                                      fontSize: 14,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ActionButton(
                                  label: '공연장 관리',
                                  onTap: () => context.push('/venues'),
                                ),
                                _ActionButton(
                                  label: '새 공연 등록',
                                  onTap: () =>
                                      context.push('/events/create'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _EditorialTag(label: '실시간 이벤트 상태'),
                            _EditorialTag(label: '좌석 배정/검수'),
                            _EditorialTag(label: '발권 운영'),
                            _EditorialTag(label: '환불 정책 모니터링'),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
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
                              accentColor: AdminTheme.success,
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
                              accentColor: AdminTheme.gold,
                              footnote: '좌석 점유율 $utilization%',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _LightCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 20, 24, 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '최근 공연',
                                    style: AdminTheme.serif(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AdminTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '최신 5건',
                                    style: AdminTheme.label(
                                      fontSize: 10,
                                      color: AdminTheme.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(height: 0.5, color: AdminTheme.border),
                            _EventsTable(events: events.take(5).toList()),
                          ],
                        ),
                      ),
                    ],
                  );
                },
                loading: () => Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(
                            4,
                            (_) => const Expanded(
                                  child: Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 6),
                                    child: ShimmerLoading(
                                        height: 120, borderRadius: 4),
                                  ),
                                )),
                      ),
                      const SizedBox(height: 22),
                      const ShimmerLoading(height: 300, borderRadius: 4),
                    ],
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(80),
                    child: Text(
                      '오류: $e',
                      style: AdminTheme.sans(color: AdminTheme.textSecondary),
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

class _EditorialTag extends StatelessWidget {
  final String label;

  const _EditorialTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AdminTheme.background,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Text(
        label,
        style: AdminTheme.sans(
          color: AdminTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Stat Card (Editorial Light) ───
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
    final accent = widget.accentColor ?? AdminTheme.sage;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isHovered
                ? accent.withValues(alpha: 0.3)
                : AdminTheme.border,
            width: 0.5,
          ),
          boxShadow: _isHovered ? AdminShadows.card : AdminShadows.small,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    widget.code,
                    style: AdminTheme.label(fontSize: 9, color: accent),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 0.5,
                    color: AdminTheme.border,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.value,
              style: AdminTheme.serif(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.footnote != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.footnote!,
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Light Card ───
class _LightCard extends StatelessWidget {
  final Widget child;

  const _LightCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
        boxShadow: AdminShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ─── Action Button (Editorial) ───
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: AdminTheme.goldGradient,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AdminTheme.sans(
                  color: AdminTheme.onAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 1,
                color: AdminTheme.onAccent.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Events Table ───
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
                  color: AdminTheme.background,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Text(
                  'NO EVENTS',
                  style: AdminTheme.label(
                    fontSize: 10,
                    color: AdminTheme.gold,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '등록된 공연이 없습니다',
                style: AdminTheme.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '새 공연을 등록해보세요',
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: AdminTheme.cardElevated,
          child: Row(
            children: [
              SizedBox(
                width: 280,
                child: Text('공연명',
                    style: AdminTheme.label(
                        fontSize: 10, color: AdminTheme.textTertiary)),
              ),
              Expanded(
                child: Text('일시',
                    style: AdminTheme.label(
                        fontSize: 10, color: AdminTheme.textTertiary)),
              ),
              SizedBox(
                width: 120,
                child: Text('좌석',
                    style: AdminTheme.label(
                        fontSize: 10, color: AdminTheme.textTertiary)),
              ),
              SizedBox(
                width: 100,
                child: Text('상태',
                    style: AdminTheme.label(
                        fontSize: 10, color: AdminTheme.textTertiary)),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Container(height: 0.5, color: AdminTheme.border),

        // Rows
        ...events.map((event) =>
            PressableScale(onTap: null, child: _EventRow(event: event))),
      ],
    );
  }
}

class _EventRow extends ConsumerStatefulWidget {
  final Event event;
  const _EventRow({required this.event});

  @override
  ConsumerState<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends ConsumerState<_EventRow> {
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
        color: _isHovered
            ? AdminTheme.sage.withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // Event name
            SizedBox(
              width: 280,
              child: Row(
                children: [
                  // Poster thumbnail
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AdminTheme.cardElevated,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: AdminTheme.border, width: 0.5),
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
                          style: AdminTheme.sans(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AdminTheme.textPrimary,
                          ),
                        ),
                        if (event.venueName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            event.venueName!,
                            overflow: TextOverflow.ellipsis,
                            style: AdminTheme.sans(
                              fontSize: 12,
                              color: AdminTheme.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Date
            Expanded(
              child: Text(
                DateFormat('MM.dd (E) HH:mm', 'ko_KR').format(event.startAt),
                style: AdminTheme.sans(
                  fontSize: 13,
                  color: AdminTheme.textSecondary,
                ),
              ),
            ),

            // Seats
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$soldSeats / ${NumberFormat('#,###').format(event.totalSeats)}',
                    style: AdminTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 3,
                    child: shad.Progress(
                      progress: ratio,
                      backgroundColor: AdminTheme.border,
                      color: ratio > 0.8
                          ? AdminTheme.error
                          : ratio > 0.5
                              ? AdminTheme.warning
                              : AdminTheme.success,
                    ),
                  ),
                ],
              ),
            ),

            // Status
            SizedBox(
              width: 100,
              child: _StatusBadge(event: event),
            ),

            // Menu
            SizedBox(
              width: 48,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    shad.showDropdown(
                      context: context,
                      builder: (_) => shad.DropdownMenu(
                        children: [
                          shad.MenuButton(
                            child: Text(
                              '공연 수정',
                              style: AdminTheme.sans(fontSize: 13),
                            ),
                            onPressed: (_) =>
                                context.push('/events/${event.id}/edit'),
                          ),
                          shad.MenuButton(
                            child: Text(
                              '좌석 관리',
                              style: AdminTheme.sans(fontSize: 13),
                            ),
                            onPressed: (_) =>
                                context.push('/events/${event.id}/seats'),
                          ),
                          shad.MenuButton(
                            child: Text(
                              '배정 현황',
                              style: AdminTheme.sans(fontSize: 13),
                            ),
                            onPressed: (_) =>
                                context.push('/events/${event.id}/assignments'),
                          ),
                          shad.MenuButton(
                            child: Text(
                              '예매자 목록',
                              style: AdminTheme.sans(fontSize: 13),
                            ),
                            onPressed: (_) =>
                                context.push('/events/${event.id}/bookers'),
                          ),
                          const shad.MenuDivider(),
                          shad.MenuButton(
                              child: Text(
                                '공연 삭제',
                                style: AdminTheme.sans(
                                  fontSize: 13,
                                  color: AdminTheme.error,
                                ),
                              ),
                              onPressed: (_) => _showDeleteDialog(event),
                            ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '옵션',
                      style: AdminTheme.sans(
                        color: AdminTheme.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // 공연 삭제 — 3단계 확인 + 비밀번호 재인증
  // ═══════════════════════════════════════════════════════════════════════════

  void _showDeleteDialog(Event event) {
    final soldSeats = event.totalSeats - event.availableSeats;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DeleteEventDialog(
        event: event,
        soldSeats: soldSeats,
        onConfirmed: () async {
          try {
            await ref.read(eventRepositoryProvider).deleteEvent(event.id);
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('「${event.title}」이(가) 삭제되었습니다.'),
                  backgroundColor: AdminTheme.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              );
            }
          } catch (e) {
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('삭제 실패: $e'),
                  backgroundColor: AdminTheme.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              );
            }
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3단계 삭제 확인 다이얼로그
// ═══════════════════════════════════════════════════════════════════════════════

class _DeleteEventDialog extends StatefulWidget {
  final Event event;
  final int soldSeats;
  final Future<void> Function() onConfirmed;

  const _DeleteEventDialog({
    required this.event,
    required this.soldSeats,
    required this.onConfirmed,
  });

  @override
  State<_DeleteEventDialog> createState() => _DeleteEventDialogState();
}

class _DeleteEventDialogState extends State<_DeleteEventDialog> {
  bool _isDeleting = false;

  Future<void> _executeDelete() async {
    setState(() => _isDeleting = true);
    await widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _isDeleting
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 48, height: 48,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AdminTheme.error)),
                    const SizedBox(height: 20),
                    Text('삭제 중...', style: AdminTheme.serif(fontSize: 18, fontWeight: FontWeight.w600, color: AdminTheme.error)),
                    const SizedBox(height: 8),
                    Text('공연 데이터와 좌석을 삭제하고 있습니다.',
                        style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textSecondary)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AdminTheme.error.withValues(alpha: 0.12),
                      ),
                      child: Icon(Icons.delete_forever_rounded, size: 32, color: AdminTheme.error),
                    ),
                    const SizedBox(height: 20),
                    Text('공연을 삭제하시겠습니까?',
                        style: AdminTheme.serif(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminTheme.background,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AdminTheme.border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.event.title,
                              style: AdminTheme.sans(fontSize: 15, fontWeight: FontWeight.w700, color: AdminTheme.textPrimary)),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat('yyyy.MM.dd HH:mm').format(widget.event.startAt)}'
                            ' · ${NumberFormat('#,###').format(widget.event.totalSeats)}석'
                            '${widget.soldSeats > 0 ? ' · ${widget.soldSeats}석 판매됨' : ''}',
                            style: AdminTheme.sans(fontSize: 12, color: AdminTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AdminTheme.error.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: Text(
                        '이 작업은 되돌릴 수 없습니다. 공연 데이터와 모든 좌석이 영구 삭제됩니다.',
                        style: AdminTheme.sans(fontSize: 12, color: AdminTheme.error, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AdminTheme.textPrimary,
                                side: BorderSide(color: AdminTheme.border, width: 0.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              child: Text('취소', style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textSecondary)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _executeDelete,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AdminTheme.error,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              child: Text('삭제', style: AdminTheme.sans(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
        color: AdminTheme.cardElevated,
      ),
      child: Center(
        child: Text(
          initial,
          style: AdminTheme.serif(
            color: AdminTheme.gold,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Status Badge (Editorial Light) ───
class _StatusBadge extends StatelessWidget {
  final Event event;

  const _StatusBadge({required this.event});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;

    if (event.status == EventStatus.soldOut || event.availableSeats == 0) {
      color = AdminTheme.error;
      text = '매진';
    } else if (event.isOnSale) {
      color = AdminTheme.success;
      text = '판매중';
    } else if (DateTime.now().isBefore(event.saleStartAt)) {
      color = AdminTheme.warning;
      text = '판매예정';
    } else {
      color = AdminTheme.textTertiary;
      text = '종료';
    }

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
        const SizedBox(width: 8),
        Text(
          text,
          style: AdminTheme.sans(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Events Content Tab ───
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
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '공연 관리',
                    style: AdminTheme.serif(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  _ActionButton(
                    label: '새 공연 등록',
                    onTap: () => context.push('/events/create'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _LightCard(
                child: eventsAsync.when(
                  data: (events) => _EventsTable(events: events),
                  loading: () => Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        const ShimmerLoading(height: 48, borderRadius: 4),
                        const SizedBox(height: 12),
                        ...List.generate(
                            5,
                            (_) => const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child:
                                      ShimmerLoading(height: 64, borderRadius: 4),
                                )),
                      ],
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(80),
                    child: Center(
                      child: Text(
                        '오류: $e',
                        style:
                            AdminTheme.sans(color: AdminTheme.textSecondary),
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

// ─── Stats Tab ───
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
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '통계 대시보드',
                style: AdminTheme.serif(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: eventsAsync.when(
                  data: (events) => _StatsBody(events: events),
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AdminTheme.gold),
                  ),
                  error: (e, _) => Center(
                    child: Text('오류: $e',
                        style: AdminTheme.sans(color: AdminTheme.error)),
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

    // Stats calculations
    final totalEvents = events.length;
    final activeEvents =
        events.where((e) => e.status == EventStatus.active).length;
    final totalSeats = events.fold<int>(0, (s, e) => s + e.totalSeats);
    final soldSeats = events.fold<int>(
        0, (s, e) => s + (e.totalSeats - e.availableSeats));
    final occupancyRate =
        totalSeats > 0 ? (soldSeats / totalSeats * 100) : 0.0;
    final estimatedRevenue = events.fold<int>(
        0, (s, e) => s + ((e.totalSeats - e.availableSeats) * e.price));
    final upcomingEvents =
        events.where((e) => e.startAt.isAfter(now)).length;
    final pastEvents = events.where((e) => e.startAt.isBefore(now)).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI cards
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _KpiCard(
                icon: Icons.event_rounded,
                label: '총 공연',
                value: '$totalEvents',
                subtext: '진행중 $activeEvents',
                color: AdminTheme.gold,
              ),
              _KpiCard(
                icon: Icons.event_seat_rounded,
                label: '총 좌석 / 판매',
                value:
                    '${priceFormat.format(soldSeats)} / ${priceFormat.format(totalSeats)}',
                subtext: '점유율 ${occupancyRate.toStringAsFixed(1)}%',
                color: AdminTheme.success,
              ),
              _KpiCard(
                icon: Icons.payments_rounded,
                label: '예상 매출',
                value: '${priceFormat.format(estimatedRevenue)}원',
                subtext: '판매 좌석 기준',
                color: AdminTheme.warning,
              ),
              _KpiCard(
                icon: Icons.calendar_month_rounded,
                label: '예정 / 종료',
                value: '$upcomingEvents / $pastEvents',
                subtext: '공연 일정',
                color: AdminTheme.info,
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Performance table
          Text(
            '공연별 실적',
            style: AdminTheme.serif(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _LightCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: AdminTheme.cardElevated,
                      borderRadius: BorderRadius.circular(2),
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
                  // Data rows
                  ...events.map((event) {
                    final sold = event.totalSeats - event.availableSeats;
                    final rate = event.totalSeats > 0
                        ? (sold / event.totalSeats * 100)
                        : 0.0;
                    final revenue = sold * event.price;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: AdminTheme.border, width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              event.title,
                              style: AdminTheme.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AdminTheme.textPrimary,
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
                                  ? AdminTheme.success
                                  : event.status == EventStatus.soldOut
                                      ? AdminTheme.error
                                      : AdminTheme.textTertiary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '$sold / ${event.totalSeats}',
                              textAlign: TextAlign.center,
                              style: AdminTheme.sans(
                                fontSize: 12,
                                color: AdminTheme.textSecondary,
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
                              style: AdminTheme.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AdminTheme.gold,
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
        style: AdminTheme.label(fontSize: 10, color: AdminTheme.textTertiary),
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
      child: Container(
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AdminTheme.border, width: 0.5),
          boxShadow: AdminShadows.small,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
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
                      style: AdminTheme.sans(
                          fontSize: 11, color: AdminTheme.textTertiary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AdminTheme.serif(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtext,
                      style: AdminTheme.sans(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.8),
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
          style: AdminTheme.sans(fontSize: 11, color: color),
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
          style: AdminTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: clampedRate >= 80
                ? AdminTheme.success
                : clampedRate >= 50
                    ? AdminTheme.warning
                    : AdminTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 4,
          child: shad.Progress(
            progress: clampedRate / 100,
            backgroundColor: AdminTheme.border,
            color: clampedRate >= 80
                ? AdminTheme.success
                : clampedRate >= 50
                    ? AdminTheme.warning
                    : AdminTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}

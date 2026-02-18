import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/services/auth_service.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final eventsAsync = ref.watch(eventsStreamProvider);

    if (currentUser.value?.isAdmin != true) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(
            'Administration',
            style: AppTheme.serif(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 48, color: AppTheme.sage.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                '관리자 권한이 필요합니다',
                style: AppTheme.serif(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '승인 요청 후 오너 승인을 기다려 주세요',
                style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: () => context.push('/setup'),
              child: Text(
                '티켓 어드민 승인 요청',
                style: AppTheme.label(fontSize: 12, color: AppTheme.onAccent),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Dashboard',
          style: AppTheme.serif(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QUICK MENU',
              style: AppTheme.label(fontSize: 10, color: AppTheme.sage),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 52) / 2,
                  child: _QuickMenuCard(
                    icon: Icons.add_circle_outline,
                    title: '공연 등록',
                    onTap: () => context.push('/events/create'),
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 52) / 2,
                  child: _QuickMenuCard(
                    icon: Icons.location_city_outlined,
                    title: '공연장 관리',
                    onTap: () => context.push('/venues'),
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 52) / 2,
                  child: _QuickMenuCard(
                    icon: Icons.qr_code_scanner,
                    title: '입장 스캐너',
                    onTap: () => context.push('/staff/scanner'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'EVENTS',
              style: AppTheme.label(fontSize: 10, color: AppTheme.sage),
            ),
            const SizedBox(height: 12),
            eventsAsync.when(
              data: (events) {
                if (events.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: Center(
                      child: Text(
                        '등록된 공연이 없습니다',
                        style: AppTheme.sans(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(2),
                        border:
                            Border.all(color: AppTheme.border, width: 0.5),
                        boxShadow: AppShadows.small,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        title: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${event.availableSeats}/${event.totalSeats}석  |  ${event.status.name}',
                          style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_horiz,
                            color: AppTheme.sage,
                            size: 20,
                          ),
                          onSelected: (value) {
                            switch (value) {
                              case 'seats':
                                context.push('/events/${event.id}/seats');
                                break;
                              case 'assignments':
                                context.push(
                                    '/events/${event.id}/assignments');
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'seats',
                              child: Text(
                                '좌석 관리',
                                style: AppTheme.sans(fontSize: 13),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'assignments',
                              child: Text(
                                '배정 현황',
                                style: AppTheme.sans(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppTheme.gold),
                ),
              ),
              error: (error, stack) => Text(
                '오류: $error',
                style: AppTheme.sans(color: AppTheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickMenuCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppTheme.border, width: 0.5),
          boxShadow: AppShadows.small,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: AppTheme.gold),
              const SizedBox(height: 10),
              Text(
                title,
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

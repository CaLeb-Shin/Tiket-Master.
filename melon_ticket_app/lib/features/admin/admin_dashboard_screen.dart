import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/event_repository.dart';
import '../../services/auth_service.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final eventsAsync = ref.watch(eventsStreamProvider);

    // 권한 체크
    if (currentUser.value?.isAdmin != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('관리자')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('관리자 권한이 필요합니다'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 대시보드'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 빠른 메뉴
            Text(
              '빠른 메뉴',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _QuickMenuCard(
                    icon: Icons.add_circle_outline,
                    title: '공연 등록',
                    onTap: () => context.push('/admin/events/create'),
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _QuickMenuCard(
                    icon: Icons.location_city_outlined,
                    title: '공연장 관리',
                    onTap: () => context.push('/admin/venues'),
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 2,
                  child: _QuickMenuCard(
                    icon: Icons.qr_code_scanner,
                    title: '입장 스캐너',
                    onTap: () => context.push('/staff/scanner'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 공연 목록
            Text(
              '공연 관리',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            eventsAsync.when(
              data: (events) {
                if (events.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('등록된 공연이 없습니다')),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${event.availableSeats}/${event.totalSeats}석 | ${event.status.name}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'seats':
                                context.push('/admin/events/${event.id}/seats');
                                break;
                              case 'assignments':
                                context.push(
                                    '/admin/events/${event.id}/assignments');
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'seats',
                              child: Text('좌석 관리'),
                            ),
                            const PopupMenuItem(
                              value: 'assignments',
                              child: Text('배정 현황'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text('오류: $error'),
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
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 32, color: Theme.of(context).primaryColor),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

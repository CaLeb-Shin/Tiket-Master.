import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/data/models/app_notification.dart';
import 'package:melon_core/data/repositories/notification_repository.dart';
import 'package:intl/intl.dart';

class NotificationListScreen extends ConsumerWidget {
  const NotificationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.value?.uid;

    if (userId == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildAppBar(context, ref, null),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_off_outlined,
                  size: 48, color: AppTheme.sage),
              const SizedBox(height: 16),
              Text('로그인 후 알림을 확인할 수 있습니다',
                  style: AppTheme.sans(
                      fontSize: 14, color: AppTheme.textSecondary,
                      noShadow: true)),
            ],
          ),
        ),
      );
    }

    final notificationsAsync = ref.watch(notificationsStreamProvider(userId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(context, ref, userId),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 48, color: AppTheme.sage),
                  const SizedBox(height: 16),
                  Text('아직 알림이 없습니다',
                      style: AppTheme.sans(
                          fontSize: 14, color: AppTheme.textSecondary,
                          noShadow: true)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppTheme.borderLight),
            itemBuilder: (context, index) {
              final notif = notifications[index];
              return _NotificationTile(
                notification: notif,
                onTap: () => _handleTap(context, ref, notif),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
        error: (_, __) => Center(
          child: Text('알림을 불러올 수 없습니다',
              style: AppTheme.sans(
                  fontSize: 14, color: AppTheme.error, noShadow: true)),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, WidgetRef ref, String? userId) {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: AppTheme.textPrimary,
        onPressed: () => context.pop(),
      ),
      title: Text('알림',
          style: AppTheme.serif(
              fontSize: 18, noShadow: true, color: AppTheme.textPrimary)),
      centerTitle: true,
      actions: [
        if (userId != null)
          TextButton(
            onPressed: () {
              ref
                  .read(notificationRepositoryProvider)
                  .markAllAsRead(userId);
            },
            child: Text('모두 읽음',
                style: AppTheme.sans(
                    fontSize: 12, color: AppTheme.sage, noShadow: true)),
          ),
      ],
    );
  }

  void _handleTap(
      BuildContext context, WidgetRef ref, AppNotification notif) {
    // 읽음 처리
    if (!notif.read) {
      ref.read(notificationRepositoryProvider).markAsRead(notif.id);
    }

    // 딥링크 처리
    final eventId = notif.data['eventId'] as String?;
    final type = notif.data['type'] as String?;

    if (type == 'booking_confirmed' || type == 'event_reminder') {
      if (eventId != null && eventId.isNotEmpty) {
        context.go('/?event=$eventId');
      }
    } else if (type == 'seats_revealed' || type == 'seat_assigned') {
      // 티켓 탭으로 이동
      context.go('/?tab=2');
    }
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nType = notification.notificationType;
    final timeAgo = _formatTimeAgo(notification.createdAt);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: notification.read
            ? Colors.transparent
            : AppTheme.goldSubtle,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 타입 아이콘
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(nType.icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 14),
            // 내용
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: AppTheme.sans(
                            fontSize: 14,
                            fontWeight: notification.read
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: AppTheme.textPrimary,
                            noShadow: true,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!notification.read)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: AppTheme.sans(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        noShadow: true),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeAgo,
                    style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        noShadow: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('M/d').format(dateTime);
  }
}

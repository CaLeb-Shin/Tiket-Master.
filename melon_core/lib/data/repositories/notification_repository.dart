import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(firestoreServiceProvider));
});

/// 로그인 유저의 알림 스트림 (최신순 50개)
final notificationsStreamProvider =
    StreamProvider.family<List<AppNotification>, String>((ref, userId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.notifications
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => AppNotification.fromFirestore(d)).toList());
});

/// 미읽은 알림 개수 스트림
final unreadNotificationCountProvider =
    StreamProvider.family<int, String>((ref, userId) {
  final fs = ref.watch(firestoreServiceProvider);
  return fs.notifications
      .where('userId', isEqualTo: userId)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((snap) => snap.docs.length);
});

class NotificationRepository {
  final FirestoreService _fs;

  NotificationRepository(this._fs);

  /// 알림 목록 조회
  Future<List<AppNotification>> getNotifications(String userId,
      {int limit = 50}) async {
    final snap = await _fs.notifications
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => AppNotification.fromFirestore(d)).toList();
  }

  /// 단건 읽음 처리
  Future<void> markAsRead(String notificationId) async {
    await _fs.notifications.doc(notificationId).update({'read': true});
  }

  /// 전체 읽음 처리
  Future<void> markAllAsRead(String userId) async {
    final snap = await _fs.notifications
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;

    final batch = _fs.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  /// 알림 삭제
  Future<void> deleteNotification(String notificationId) async {
    await _fs.notifications.doc(notificationId).delete();
  }
}

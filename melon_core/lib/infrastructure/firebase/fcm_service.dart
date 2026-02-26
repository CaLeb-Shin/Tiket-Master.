import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fcmServiceProvider = Provider<FcmService>((ref) => FcmService());

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<String>? _tokenRefreshSub;

  /// FCM 초기화 (앱 시작 시 호출)
  Future<void> initialize() async {
    try {
      // 권한 요청
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] 알림 권한 거부됨');
        return;
      }

      // 웹은 VAPID key 필요 (Firebase Console에서 생성)
      final token = await _messaging.getToken(
        vapidKey: kIsWeb
            ? 'BL-u5j5WLLVJZv7JoxwFt3B0Q0nq9cWzEhJ1z2GqGfjYxOvLQhYKYsVp8R2D5kXPbA-9MKMUZ8nQrGdoaWbPsQ'
            : null,
      );

      if (token != null) {
        await _saveFcmToken(token);
      }

      // 토큰 갱신 리스너
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(_saveFcmToken);

      // 포그라운드 메시지 표시 설정
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('[FCM] 초기화 완료, 토큰: ${token?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[FCM] 초기화 실패: $e');
    }
  }

  /// Firestore에 FCM 토큰 저장
  Future<void> _saveFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[FCM] 토큰 저장 실패: $e');
    }
  }

  /// FCM 토큰 가져오기
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// 포그라운드 메시지 스트림
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  /// 메시지 클릭 시
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// 앱 종료 상태에서 메시지 클릭으로 열린 경우
  Future<RemoteMessage?> getInitialMessage() {
    return _messaging.getInitialMessage();
  }

  /// 특정 토픽 구독
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
    } catch (_) {}
  }

  /// 토픽 구독 해제
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (_) {}
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
  }
}

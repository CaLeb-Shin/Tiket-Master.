import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fcmServiceProvider = Provider<FcmService>((ref) => FcmService());

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// 알림 권한 요청
  Future<NotificationSettings> requestPermission() async {
    return await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// FCM 토큰 가져오기
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// 토큰 갱신 스트림
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// 포그라운드 메시지 스트림
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  /// 메시지 클릭 시
  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  /// 앱 종료 상태에서 메시지 클릭으로 열린 경우
  Future<RemoteMessage?> getInitialMessage() {
    return _messaging.getInitialMessage();
  }

  /// 특정 토픽 구독
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  /// 토픽 구독 해제
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }
}

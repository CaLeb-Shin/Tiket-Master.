import 'package:flutter/foundation.dart';

class PlatformUtils {
  /// 웹 플랫폼인지 확인
  static bool get isWeb => kIsWeb;
  
  /// 모바일 플랫폼인지 확인 (iOS, Android)
  static bool get isMobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || 
                                          defaultTargetPlatform == TargetPlatform.android);
  
  /// 데스크톱 플랫폼인지 확인
  static bool get isDesktop => !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
                                           defaultTargetPlatform == TargetPlatform.macOS ||
                                           defaultTargetPlatform == TargetPlatform.linux);
  
  /// 관리자 모드로 동작해야 하는지 (웹 또는 데스크톱)
  static bool get isAdminPlatform => isWeb || isDesktop;
  
  /// 모바일 예매 모드로 동작해야 하는지
  static bool get isBookingPlatform => isMobile;
}

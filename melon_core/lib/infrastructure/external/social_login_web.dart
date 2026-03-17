import 'dart:js_interop';

@JS('loginWithKakao')
external JSPromise<JSString> _loginWithKakao();

@JS('loginWithNaver')
external JSPromise<JSString> _loginWithNaver();

/// 카카오 JS SDK 로그인 → 액세스 토큰 반환
Future<String?> getKakaoAccessToken() async {
  try {
    final token = (await _loginWithKakao().toDart).toDart;
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

/// 네이버 팝업 로그인 → "code|redirectUri" 형식 문자열 반환
Future<Map<String, String>?> getNaverAuthCode() async {
  try {
    final result = (await _loginWithNaver().toDart).toDart;
    if (result.isEmpty) return null;
    // JS에서 "code|redirectUri" 형식으로 전달
    final parts = result.split('|');
    if (parts.length < 2) return null;
    return {'code': parts[0], 'redirectUri': parts[1]};
  } catch (_) {
    return null;
  }
}

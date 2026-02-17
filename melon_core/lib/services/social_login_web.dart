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

/// 네이버 팝업 로그인 → 액세스 토큰 반환
Future<String?> getNaverAccessToken() async {
  try {
    final token = (await _loginWithNaver().toDart).toDart;
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

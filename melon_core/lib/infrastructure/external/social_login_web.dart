import 'dart:js_interop';

@JS('loginWithKakao')
external JSPromise<JSString> _loginWithKakao();

@JS('loginWithNaver')
external JSPromise<JSAny> _loginWithNaver();

/// 카카오 JS SDK 로그인 → 액세스 토큰 반환
Future<String?> getKakaoAccessToken() async {
  try {
    final token = (await _loginWithKakao().toDart).toDart;
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

/// 네이버 팝업 로그인 → {code, redirectUri} 반환
Future<Map<String, String>?> getNaverAuthCode() async {
  try {
    final result = await _loginWithNaver().toDart;
    // JS object → Dart Map
    final jsObj = result as JSObject;
    final code = (jsObj.getProperty('code'.toJS) as JSString).toDart;
    final redirectUri =
        (jsObj.getProperty('redirectUri'.toJS) as JSString).toDart;
    if (code.isEmpty) return null;
    return {'code': code, 'redirectUri': redirectUri};
  } catch (_) {
    return null;
  }
}

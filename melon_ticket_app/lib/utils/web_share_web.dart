import 'dart:js_interop';

@JS('navigator.share')
external JSPromise<JSAny?>? _navigatorShare(JSObject shareData);

/// Try to use the Web Share API (navigator.share)
Future<bool> tryWebShare({
  required String title,
  required String text,
  required String url,
}) async {
  try {
    final shareData = <String, String>{
      'title': title,
      'text': text,
      'url': url,
    }.jsify() as JSObject;

    final promise = _navigatorShare(shareData);
    if (promise == null) return false;
    await promise.toDart;
    return true;
  } catch (_) {
    return false;
  }
}

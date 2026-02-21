/// Stub for non-web platforms
Future<bool> tryWebShare({
  required String title,
  required String text,
  required String url,
}) async {
  return false;
}

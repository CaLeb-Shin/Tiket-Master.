// Stub for dart:html — used on non-web platforms via conditional import.
// ignore_for_file: camel_case_types

class _Window {
  void open(String url, String target) {}
}

final window = _Window();

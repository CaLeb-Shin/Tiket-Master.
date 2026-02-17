import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final scannerDeviceServiceProvider = Provider<ScannerDeviceService>(
  (ref) => const ScannerDeviceService(),
);

class ScannerDeviceService {
  static const _prefsKeyInstallationId = 'scanner_installation_id';
  static const _uuid = Uuid();

  const ScannerDeviceService();

  Future<String> getOrCreateInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKeyInstallationId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = _uuid.v4();
    await prefs.setString(_prefsKeyInstallationId, created);
    return created;
  }

  String defaultLabel() {
    if (kIsWeb) return 'Web Scanner';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android Scanner';
      case TargetPlatform.iOS:
        return 'iOS Scanner';
      case TargetPlatform.macOS:
        return 'macOS Scanner';
      case TargetPlatform.windows:
        return 'Windows Scanner';
      case TargetPlatform.linux:
        return 'Linux Scanner';
      case TargetPlatform.fuchsia:
        return 'Fuchsia Scanner';
    }
  }

  String platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}


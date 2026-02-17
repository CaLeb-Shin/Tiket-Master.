import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/scanner_device.dart';

final scannerDeviceRepositoryProvider = Provider<ScannerDeviceRepository>((ref) {
  return ScannerDeviceRepository(ref.watch(firestoreServiceProvider));
});

class ScannerDeviceRepository {
  final FirestoreService _firestoreService;

  ScannerDeviceRepository(this._firestoreService);

  Stream<List<ScannerDevice>> streamAllDevices() {
    return _firestoreService.scannerDevices.snapshots().map((snapshot) {
      final devices =
          snapshot.docs.map((doc) => ScannerDevice.fromFirestore(doc)).toList();
      devices.sort((a, b) {
        final aTime = a.lastSeenAt ?? a.requestedAt ?? DateTime(1970);
        final bTime = b.lastSeenAt ?? b.requestedAt ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      return devices;
    });
  }
}


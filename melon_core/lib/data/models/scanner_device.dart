import 'package:cloud_firestore/cloud_firestore.dart';

class ScannerDevice {
  final String id;
  final String ownerUid;
  final String ownerEmail;
  final String ownerDisplayName;
  final String platform;
  final String label;
  final bool approved;
  final bool blocked;
  final DateTime? requestedAt;
  final DateTime? approvedAt;
  final DateTime? lastSeenAt;
  final String? approvedByEmail;

  const ScannerDevice({
    required this.id,
    required this.ownerUid,
    required this.ownerEmail,
    required this.ownerDisplayName,
    required this.platform,
    required this.label,
    required this.approved,
    required this.blocked,
    this.requestedAt,
    this.approvedAt,
    this.lastSeenAt,
    this.approvedByEmail,
  });

  factory ScannerDevice.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ScannerDevice(
      id: doc.id,
      ownerUid: data['ownerUid'] as String? ?? '',
      ownerEmail: data['ownerEmail'] as String? ?? '',
      ownerDisplayName: data['ownerDisplayName'] as String? ?? '',
      platform: data['platform'] as String? ?? '',
      label: data['label'] as String? ?? '',
      approved: data['approved'] == true,
      blocked: data['blocked'] == true,
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      lastSeenAt: (data['lastSeenAt'] as Timestamp?)?.toDate(),
      approvedByEmail: data['approvedByEmail'] as String?,
    );
  }
}


import 'package:cloud_firestore/cloud_firestore.dart';

/// 공연장 등록 요청 모델 (셀러 → 슈퍼어드민 승인)
class VenueRequest {
  final String id;
  final String sellerId;
  final String sellerName;
  final String venueName;
  final String address;
  final int seatCount;
  final String? description;
  final String status; // pending, approved, rejected
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? rejectReason;

  VenueRequest({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.venueName,
    required this.address,
    required this.seatCount,
    this.description,
    this.status = 'pending',
    required this.requestedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.rejectReason,
  });

  factory VenueRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VenueRequest(
      id: doc.id,
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      venueName: data['venueName'] ?? '',
      address: data['address'] ?? '',
      seatCount: data['seatCount'] ?? 0,
      description: data['description'],
      status: data['status'] ?? 'pending',
      requestedAt:
          (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: data['resolvedBy'],
      rejectReason: data['rejectReason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sellerId': sellerId,
      'sellerName': sellerName,
      'venueName': venueName,
      'address': address,
      'seatCount': seatCount,
      if (description != null) 'description': description,
      'status': status,
      'requestedAt': Timestamp.fromDate(requestedAt),
      if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
      if (resolvedBy != null) 'resolvedBy': resolvedBy,
      if (rejectReason != null) 'rejectReason': rejectReason,
    };
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

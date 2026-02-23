import 'package:cloud_firestore/cloud_firestore.dart';
import 'mileage.dart';

/// 사용자 모델
class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? phoneNumber;
  final UserRole role;
  final Mileage mileage;
  final String? referralCode;
  final bool isDemo; // 체험 계정 여부
  final List<String> badges; // 뱃지 목록
  final SellerProfile? sellerProfile; // 셀러 프로필 (role=seller일 때)
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.phoneNumber,
    required this.role,
    Mileage? mileage,
    this.referralCode,
    this.isDemo = false,
    this.badges = const [],
    this.sellerProfile,
    required this.createdAt,
    this.lastLoginAt,
  }) : mileage = mileage ?? Mileage();

  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;
  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isSeller => role == UserRole.seller;
  bool get isStaff => role == UserRole.staff || isAdmin;

  /// 역할만 변경한 복사본 생성 (테스트 모드용)
  AppUser copyWith({UserRole? role}) {
    return AppUser(
      id: id,
      email: email,
      displayName: displayName,
      phoneNumber: phoneNumber,
      role: role ?? this.role,
      mileage: mileage,
      referralCode: referralCode,
      isDemo: isDemo,
      badges: badges,
      sellerProfile: sellerProfile,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
    );
  }

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      id: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      phoneNumber: data['phoneNumber'],
      role: UserRole.fromString(data['role']),
      mileage: Mileage.fromMap(data['mileage'] as Map<String, dynamic>?),
      referralCode: data['referralCode'] as String?,
      isDemo: data['isDemo'] ?? false,
      badges: data['badges'] != null ? List<String>.from(data['badges']) : [],
      sellerProfile: data['sellerProfile'] != null
          ? SellerProfile.fromMap(data['sellerProfile'] as Map<String, dynamic>)
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'role': role.name,
      'mileage': mileage.toMap(),
      if (referralCode != null) 'referralCode': referralCode,
      'isDemo': isDemo,
      'badges': badges,
      if (sellerProfile != null) 'sellerProfile': sellerProfile!.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
    };
  }
}

/// 셀러 프로필
class SellerProfile {
  final String businessName; // 상호명
  final String? businessNumber; // 사업자번호
  final String? representativeName; // 대표자명
  final String? contactNumber; // 연락처
  final String? logoUrl;
  final String? description; // 소개글
  final String sellerStatus; // pending / active / suspended

  SellerProfile({
    required this.businessName,
    this.businessNumber,
    this.representativeName,
    this.contactNumber,
    this.logoUrl,
    this.description,
    this.sellerStatus = 'pending',
  });

  factory SellerProfile.fromMap(Map<String, dynamic> data) {
    return SellerProfile(
      businessName: data['businessName'] ?? '',
      businessNumber: data['businessNumber'],
      representativeName: data['representativeName'],
      contactNumber: data['contactNumber'],
      logoUrl: data['logoUrl'],
      description: data['description'],
      sellerStatus: data['sellerStatus'] ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessName': businessName,
      'businessNumber': businessNumber,
      'representativeName': representativeName,
      'contactNumber': contactNumber,
      'logoUrl': logoUrl,
      'description': description,
      'sellerStatus': sellerStatus,
    };
  }
}

enum UserRole {
  user, // 일반 사용자
  staff, // 스태프 (스캐너)
  seller, // 판매자/주최자
  admin, // 관리자
  superAdmin; // 플랫폼 운영자

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.user,
    );
  }
}

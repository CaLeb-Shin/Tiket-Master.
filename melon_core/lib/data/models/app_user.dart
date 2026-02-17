import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 모델
class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? phoneNumber;
  final UserRole role;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.phoneNumber,
    required this.role,
    required this.createdAt,
    this.lastLoginAt,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isStaff => role == UserRole.staff || role == UserRole.admin;

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      id: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      phoneNumber: data['phoneNumber'],
      role: UserRole.fromString(data['role']),
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
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
    };
  }
}

enum UserRole {
  user, // 일반 사용자
  staff, // 스태프 (스캐너)
  admin; // 관리자

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.user,
    );
  }
}

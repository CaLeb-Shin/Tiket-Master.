import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/app_user.dart';
import '../utils/referral_code.dart';
import 'social_login_web.dart'
    if (dart.library.io) 'social_login_stub.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.watch(authServiceProvider).getAppUser(user.uid);
});

/// 소셜 로그인 타입
enum SocialLoginType {
  google,
  kakao,
  naver,
  apple,
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 최종 승인권자(오너) 이메일
  static const String ownerEmail = 'sinbun001@gmail.com';

  static const List<String> _ownerEmails = [
    ownerEmail,
  ];

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 오너 이메일인지 확인
  bool _isOwnerEmail(String? email) {
    if (email == null) return false;
    return _ownerEmails.contains(email.toLowerCase());
  }

  /// 이메일 로그인
  Future<UserCredential> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _updateLastLogin(credential.user!.uid);
    return credential;
  }

  /// 이메일 회원가입
  Future<UserCredential> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
    bool requestAdminApproval = false,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Firestore에 사용자 정보 저장
    await _createUserDocument(
      uid: credential.user!.uid,
      email: email,
      displayName: displayName,
      provider: 'email',
    );

    // 관리자 승인 신청이 체크된 경우 승인 요청 생성 (오너 제외)
    if (requestAdminApproval && !_isOwnerEmail(email)) {
      await submitAdminApprovalRequest(
        uid: credential.user!.uid,
        email: email,
        displayName: displayName,
      );
    }

    return credential;
  }

  /// Google 로그인 (Firebase Auth 직접 사용)
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      UserCredential userCredential;

      if (kIsWeb) {
        // 웹: signInWithPopup 사용
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        // 모바일: signInWithProvider 사용
        userCredential = await _auth.signInWithProvider(googleProvider);
      }

      // 신규 사용자면 Firestore에 저장
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        await _createUserDocument(
          uid: userCredential.user!.uid,
          email: userCredential.user!.email,
          displayName: userCredential.user!.displayName,
          photoUrl: userCredential.user!.photoURL,
          provider: 'google',
        );
      } else {
        // 기존 사용자 - 오너 이메일이면 admin 권한 유지
        await _updateUserRoleIfOwner(
          userCredential.user!.uid,
          userCredential.user!.email,
        );
      }

      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  /// 카카오 로그인 (JS SDK → Cloud Functions → Custom Token)
  Future<UserCredential?> signInWithKakao() async {
    // 1. 카카오 JS SDK로 액세스 토큰 획득
    final accessToken = await getKakaoAccessToken();
    if (accessToken == null) return null;

    // 2. Cloud Functions에서 Custom Token 발급
    final callable = FirebaseFunctions.instance.httpsCallable('signInWithKakao');
    final result = await callable.call<Map<String, dynamic>>(
      {'accessToken': accessToken},
    );
    final customToken = result.data['customToken'] as String;

    // 3. Firebase Custom Token으로 로그인
    final credential = await _auth.signInWithCustomToken(customToken);
    return credential;
  }

  /// 네이버 로그인 (팝업 OAuth → Cloud Functions → Custom Token)
  Future<UserCredential?> signInWithNaver() async {
    // 1. 네이버 팝업 로그인으로 액세스 토큰 획득
    final accessToken = await getNaverAccessToken();
    if (accessToken == null) return null;

    // 2. Cloud Functions에서 Custom Token 발급
    final callable = FirebaseFunctions.instance.httpsCallable('signInWithNaver');
    final result = await callable.call<Map<String, dynamic>>(
      {'accessToken': accessToken},
    );
    final customToken = result.data['customToken'] as String;

    // 3. Firebase Custom Token으로 로그인
    final credential = await _auth.signInWithCustomToken(customToken);
    return credential;
  }

  /// 로그아웃
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// 사용자 정보 가져오기
  Future<AppUser?> getAppUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  /// 사용자 문서 생성
  Future<void> _createUserDocument({
    required String uid,
    String? email,
    String? displayName,
    String? photoUrl,
    required String provider,
  }) async {
    // 오너 이메일만 즉시 admin, 그 외는 user로 생성
    final role =
        _isOwnerEmail(email) ? UserRole.admin.name : UserRole.user.name;

    // 유니크 추천 코드 생성
    final referralCode = await _generateUniqueReferralCode();

    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'provider': provider,
      'role': role,
      'mileage': {'balance': 0, 'tier': 'bronze', 'totalEarned': 0},
      'referralCode': referralCode,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  /// 유니크한 추천 코드 생성 (Firestore 중복 체크)
  Future<String> _generateUniqueReferralCode() async {
    for (int i = 0; i < 10; i++) {
      final code = generateReferralCode();
      final existing = await _firestore
          .collection('users')
          .where('referralCode', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    // Fallback
    return generateReferralCode();
  }

  /// 기존 사용자의 권한 업데이트 (오너 이메일인 경우)
  Future<void> _updateUserRoleIfOwner(String uid, String? email) async {
    if (_isOwnerEmail(email)) {
      await _firestore.collection('users').doc(uid).update({
        'role': UserRole.admin.name,
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _updateLastLogin(uid);
    }
  }

  /// 관리자 승인 요청 생성/재요청
  Future<void> submitAdminApprovalRequest({
    String? uid,
    String? email,
    String? displayName,
  }) async {
    final user = _auth.currentUser;
    final targetUid = uid ?? user?.uid;
    if (targetUid == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final targetEmail = (email ?? user?.email ?? '').trim();
    if (targetEmail.isEmpty) {
      throw StateError('이메일 정보를 확인할 수 없습니다.');
    }
    if (_isOwnerEmail(targetEmail)) {
      return;
    }

    final targetDisplayName =
        (displayName ?? user?.displayName ?? targetEmail.split('@').first)
            .trim();

    await _firestore.collection('adminApprovalRequests').doc(targetUid).set({
      'userId': targetUid,
      'email': targetEmail,
      'displayName': targetDisplayName,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 오너가 승인 요청을 승인
  Future<void> approveAdminApprovalRequest(String targetUid) async {
    final approver = _auth.currentUser;
    if (approver == null || !_isOwnerEmail(approver.email)) {
      throw StateError('오너 계정만 승인할 수 있습니다.');
    }

    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(targetUid);
    final requestRef =
        _firestore.collection('adminApprovalRequests').doc(targetUid);

    batch.set(
        userRef,
        {
          'role': UserRole.admin.name,
          'adminApprovedAt': FieldValue.serverTimestamp(),
          'adminApprovedBy': approver.email,
          'lastLoginAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    batch.set(
        requestRef,
        {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedByUid': approver.uid,
          'approvedByEmail': approver.email,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  /// 오너가 승인 요청을 거절
  Future<void> rejectAdminApprovalRequest(String targetUid) async {
    final approver = _auth.currentUser;
    if (approver == null || !_isOwnerEmail(approver.email)) {
      throw StateError('오너 계정만 거절할 수 있습니다.');
    }

    await _firestore.collection('adminApprovalRequests').doc(targetUid).set({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedByUid': approver.uid,
      'rejectedByEmail': approver.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 마지막 로그인 시간 업데이트
  Future<void> _updateLastLogin(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }
}

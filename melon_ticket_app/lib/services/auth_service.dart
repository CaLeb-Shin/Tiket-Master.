import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/app_user.dart';

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

  // 관리자 이메일 목록
  static const List<String> _adminEmails = [
    'sinbun001@gmail.com',
  ];

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 관리자 이메일인지 확인
  bool _isAdminEmail(String? email) {
    if (email == null) return false;
    return _adminEmails.contains(email.toLowerCase());
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
  Future<UserCredential> signUpWithEmail(String email, String password, {String? displayName}) async {
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
        // 기존 사용자 - 관리자 이메일이면 권한 업데이트
        await _updateUserRoleIfAdmin(
          userCredential.user!.uid,
          userCredential.user!.email,
        );
      }

      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  /// 카카오 로그인 (Custom Token 방식 - Cloud Functions 필요)
  Future<UserCredential?> signInWithKakao() async {
    // 카카오 로그인은 다음 단계가 필요합니다:
    // 1. Kakao Developers에서 앱 등록
    // 2. kakao_flutter_sdk 패키지 설치 및 초기화
    // 3. 카카오 로그인 후 토큰 받기
    // 4. Cloud Functions에서 Firebase Custom Token 발급
    // 5. Custom Token으로 Firebase 로그인
    
    throw UnimplementedError(
      '카카오 로그인을 사용하려면 다음 설정이 필요합니다:\n'
      '1. Kakao Developers에서 앱 등록\n'
      '2. kakao_flutter_sdk 패키지 설치\n'
      '3. Cloud Functions에서 Custom Token 발급 로직 구현'
    );
  }

  /// 네이버 로그인 (Custom Token 방식 - Cloud Functions 필요)
  Future<UserCredential?> signInWithNaver() async {
    // 네이버 로그인은 다음 단계가 필요합니다:
    // 1. Naver Developers에서 앱 등록
    // 2. flutter_naver_login 패키지 설치 및 초기화
    // 3. 네이버 로그인 후 토큰 받기
    // 4. Cloud Functions에서 Firebase Custom Token 발급
    // 5. Custom Token으로 Firebase 로그인
    
    throw UnimplementedError(
      '네이버 로그인을 사용하려면 다음 설정이 필요합니다:\n'
      '1. Naver Developers에서 앱 등록\n'
      '2. flutter_naver_login 패키지 설치\n'
      '3. Cloud Functions에서 Custom Token 발급 로직 구현'
    );
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
    // 관리자 이메일이면 admin 권한 부여
    final role = _isAdminEmail(email) ? UserRole.admin.name : UserRole.user.name;
    
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'provider': provider,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  /// 기존 사용자의 권한 업데이트 (관리자 이메일인 경우)
  Future<void> _updateUserRoleIfAdmin(String uid, String? email) async {
    if (_isAdminEmail(email)) {
      await _firestore.collection('users').doc(uid).update({
        'role': UserRole.admin.name,
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _updateLastLogin(uid);
    }
  }

  /// 마지막 로그인 시간 업데이트
  Future<void> _updateLastLogin(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }
}

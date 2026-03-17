import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Brand Logo SVGs ───
const _naverLogoSvg =
    '<svg viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M13.56 10.07L6.28 0H0v20h6.44V9.93L13.72 20H20V0h-6.44v10.07z" fill="white"/>'
    '</svg>';

const _kakaoLogoSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 3C6.48 3 2 6.36 2 10.5c0 2.69 1.82 5.04 4.55 6.35l-.97 3.54c-.08.28.18.52.41.35l3.66-2.45c.77.12 1.57.17 2.38.17 5.52 0 10-3.33 10-7.46S17.52 3 12 3z" fill="#191600"/>'
    '</svg>';

const _googleLogoSvg =
    '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M43.6 20.1H42V20H24v8h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 8 3l5.7-5.7C34 6.1 29.3 4 24 4 13 4 4 13 4 24s9 20 20 20 20-9 20-20c0-1.3-.1-2.7-.4-3.9z" fill="#FFC107"/>'
    '<path d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 8 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" fill="#FF3D00"/>'
    '<path d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2A11.9 11.9 0 0124 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z" fill="#4CAF50"/>'
    '<path d="M43.6 20.1H42V20H24v8h11.3a12 12 0 01-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.7-.4-3.9z" fill="#1976D2"/>'
    '</svg>';

const _lastLoginProviderKey = 'lastLoginProvider';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _requestAdminApproval = false;

  String? _lastLoginProvider;

  /// 로그인 후 이동할 경로 (returnTo 파라미터)
  void _navigateAfterLogin() {
    if (!mounted) return;
    final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
    if (returnTo != null && returnTo.isNotEmpty) {
      context.go(Uri.decodeComponent(returnTo));
    } else {
      context.go('/');
    }
  }

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _loadLastLoginProvider();
  }

  Future<void> _loadLastLoginProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString(_lastLoginProviderKey);
    if (mounted && provider != null) {
      setState(() => _lastLoginProvider = provider);
    }
  }

  Future<void> _saveLastLoginProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLoginProviderKey, provider);
    if (mounted) {
      setState(() => _lastLoginProvider = provider);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);

      if (_isSignUp) {
        final wantsAdminApproval = _requestAdminApproval;
        await authService.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
          requestAdminApproval: wantsAdminApproval,
        );
        if (wantsAdminApproval && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '티켓 어드민 승인 신청이 접수되었습니다. 오너 승인 후 관리자 권한이 활성화됩니다.',
                style: AppTheme.nanum(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              backgroundColor: AppTheme.info,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
        await _saveLastLoginProvider('email');
      }

      if (mounted) {
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        _showError(_parseErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithKakao() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithKakao();
      if (result != null && mounted) {
        await _saveLastLoginProvider('kakao');
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        _showError('카카오 로그인 실패: ${_parseErrorMessage(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithNaver() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithNaver();
      if (result != null && mounted) {
        await _saveLastLoginProvider('naver');
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        _showError('네이버 로그인 실패: ${_parseErrorMessage(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithGoogle();

      if (result != null && mounted) {
        await _saveLastLoginProvider('google');
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        _showError('Google 로그인 실패: ${_parseErrorMessage(e.toString())}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInAsGuest() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInAnonymously();
      if (mounted) {
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        _showError('체험 로그인 실패: ${_parseErrorMessage(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 전화번호 인증 — 2단계 바텀시트 (번호 입력 → SMS 코드 입력)
  Future<void> _signInWithPhone() async {
    final phoneController = TextEditingController();
    final codeController = TextEditingController();
    ConfirmationResult? confirmationResult;
    bool isSending = false;
    bool isVerifying = false;
    String? errorText;

    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 핸들 바
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 타이틀
                    Text(
                      confirmationResult == null
                          ? '전화번호 인증'
                          : 'SMS 인증코드 입력',
                      style: AppTheme.nanum(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      confirmationResult == null
                          ? '휴대폰 번호를 입력하면 인증 코드를 보내드립니다'
                          : '${phoneController.text}로 발송된 6자리 코드를 입력해주세요',
                      style: AppTheme.nanum(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ─── Step 1: 전화번호 입력 ───
                    if (confirmationResult == null) ...[
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                          _PhoneNumberFormatter(),
                        ],
                        style: AppTheme.nanum(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          letterSpacing: 1,
                        ),
                        cursorColor: AppTheme.gold,
                        decoration: InputDecoration(
                          hintText: '010-1234-5678',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 16, right: 8),
                            child: Text('🇰🇷 +82',
                                style: TextStyle(fontSize: 15)),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                          filled: true,
                          fillColor: AppTheme.background,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppTheme.border, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppTheme.gold, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          hintStyle: AppTheme.nanum(
                              fontSize: 18, color: AppTheme.textTertiary),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: AppTheme.nanum(
                            fontSize: 13,
                            color: AppTheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildPhoneActionButton(
                        label: '인증코드 받기',
                        isLoading: isSending,
                        onTap: () async {
                          final raw = phoneController.text
                              .replaceAll(RegExp(r'[\s\-]'), '');
                          if (raw.length < 10) {
                            setSheetState(
                                () => errorText = '올바른 전화번호를 입력해주세요');
                            return;
                          }
                          setSheetState(() {
                            isSending = true;
                            errorText = null;
                          });
                          try {
                            final authService = ref.read(authServiceProvider);
                            final result =
                                await authService.sendPhoneVerificationCode(raw);
                            setSheetState(() {
                              confirmationResult = result;
                              isSending = false;
                            });
                          } catch (e) {
                            setSheetState(() {
                              isSending = false;
                              errorText =
                                  _parsePhoneError(e.toString());
                            });
                          }
                        },
                      ),
                    ],

                    // ─── Step 2: SMS 코드 입력 ───
                    if (confirmationResult != null) ...[
                      TextFormField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: AppTheme.nanum(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: 12,
                        ),
                        textAlign: TextAlign.center,
                        cursorColor: AppTheme.gold,
                        decoration: InputDecoration(
                          hintText: '000000',
                          filled: true,
                          fillColor: AppTheme.background,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppTheme.border, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppTheme.gold, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          hintStyle: AppTheme.nanum(
                            fontSize: 28,
                            color: AppTheme.textTertiary,
                            letterSpacing: 12,
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: AppTheme.nanum(
                            fontSize: 13,
                            color: AppTheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: isSending
                            ? null
                            : () async {
                                final raw = phoneController.text
                                    .replaceAll(RegExp(r'[\s\-]'), '');
                                setSheetState(() {
                                  isSending = true;
                                  errorText = null;
                                });
                                try {
                                  final authService =
                                      ref.read(authServiceProvider);
                                  final result = await authService
                                      .sendPhoneVerificationCode(raw);
                                  setSheetState(() {
                                    confirmationResult = result;
                                    isSending = false;
                                  });
                                } catch (e) {
                                  setSheetState(() {
                                    isSending = false;
                                    errorText = _parsePhoneError(e.toString());
                                  });
                                }
                              },
                        child: Text(
                          isSending ? '발송 중...' : '인증코드 재발송',
                          style: AppTheme.nanum(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.gold,
                            decoration: TextDecoration.underline,
                          ).copyWith(decorationColor: AppTheme.gold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPhoneActionButton(
                        label: '인증 확인',
                        isLoading: isVerifying,
                        onTap: () async {
                          if (codeController.text.length != 6) {
                            setSheetState(
                                () => errorText = '6자리 인증코드를 입력해주세요');
                            return;
                          }
                          setSheetState(() {
                            isVerifying = true;
                            errorText = null;
                          });
                          try {
                            final authService = ref.read(authServiceProvider);
                            await authService.verifyPhoneCode(
                              confirmationResult!,
                              codeController.text,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } catch (e) {
                            setSheetState(() {
                              isVerifying = false;
                              errorText = _parsePhoneError(e.toString());
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (success == true && mounted) {
      await _saveLastLoginProvider('phone');
      // 전화번호 로그인 시 네이버 주문 자동 매칭 (fire-and-forget)
      _autoClaimAndNotify();
      _navigateAfterLogin();
    }
  }

  /// 로그인 후 네이버 주문 자동 매칭 → 결과 스낵바
  Future<void> _autoClaimAndNotify() async {
    try {
      final authService = ref.read(authServiceProvider);
      final claimedCount = await authService.tryAutoClaimNaverOrders();
      if (claimedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '네이버 예매 $claimedCount건이 자동으로 연결되었습니다',
                    style: AppTheme.nanum(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF03C75A),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      // 자동 매칭 실패는 무시
    }
  }

  String _parsePhoneError(String error) {
    if (error.contains('invalid-phone-number')) {
      return '유효하지 않은 전화번호입니다';
    } else if (error.contains('too-many-requests')) {
      return '요청이 너무 많습니다. 잠시 후 다시 시도해주세요';
    } else if (error.contains('invalid-verification-code')) {
      return '인증코드가 올바르지 않습니다';
    } else if (error.contains('session-expired')) {
      return '인증 세션이 만료되었습니다. 다시 시도해주세요';
    } else if (error.contains('quota-exceeded')) {
      return 'SMS 발송 한도를 초과했습니다';
    }
    return error.replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  Widget _buildPhoneActionButton({
    required String label,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: isLoading ? null : AppTheme.goldGradient,
        color: isLoading ? AppTheme.border : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isLoading
            ? null
            : const [
                BoxShadow(
                  color: AppTheme.goldSubtle,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.textTertiary,
                    ),
                  )
                : Text(
                    label,
                    style: AppTheme.nanum(
                      color: const Color(0xFFFDF3F6),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      shadows: AppTheme.textShadowOnDark,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  String _parseErrorMessage(String error) {
    if (error.contains('user-not-found')) {
      return '등록되지 않은 이메일입니다';
    } else if (error.contains('wrong-password')) {
      return '비밀번호가 올바르지 않습니다';
    } else if (error.contains('email-already-in-use')) {
      return '이미 사용 중인 이메일입니다';
    } else if (error.contains('weak-password')) {
      return '비밀번호가 너무 약합니다';
    } else if (error.contains('invalid-email')) {
      return '올바르지 않은 이메일 형식입니다';
    } else if (error.contains('network-request-failed')) {
      return '네트워크 연결을 확인해주세요';
    }
    return error.replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTheme.nanum(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: bottomInset > 0 ? 24 : 0,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 56),

                  // --- Logo ---
                  _buildLogo(),
                  const SizedBox(height: 28),

                  // --- Title ---
                  _buildTitle(),
                  const SizedBox(height: 32),

                  // --- Login / Signup Tab ---
                  _buildTabToggle(),
                  const SizedBox(height: 24),

                  // --- 네이버 로그인 (최상단 강조) ---
                  _buildNaverPrimaryButton(),
                  const SizedBox(height: 16),

                  // --- 보조 로그인 (카카오 · 구글 · 전화번호) ---
                  _buildSecondaryLoginRow(),
                  const SizedBox(height: 24),

                  // --- Divider: "또는 이메일로 로그인" ---
                  _buildEmailDivider(),
                  const SizedBox(height: 24),

                  // --- Email Field ---
                  _buildLabel('이메일'),
                  const SizedBox(height: 8),
                  _buildEmailField(),
                  const SizedBox(height: 18),

                  // --- Password Field ---
                  _buildLabel('비밀번호'),
                  const SizedBox(height: 8),
                  _buildPasswordField(),
                  if (_isSignUp) ...[
                    const SizedBox(height: 14),
                    _buildAdminApprovalRequestBox(),
                  ],
                  const SizedBox(height: 28),

                  // --- Primary Action Button ---
                  _buildPrimaryButton(),
                  const SizedBox(height: 28),

                  // --- Guest (체험하기) at the bottom ---
                  _buildGuestButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Logo
  // ──────────────────────────────────────────────

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: AppTheme.goldGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: AppTheme.goldSubtle,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'M',
            style: AppTheme.nanum(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFFDF3F6),
              height: 1,
              shadows: AppTheme.textShadowOnDark,
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Title
  // ──────────────────────────────────────────────

  Widget _buildTitle() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) =>
              AppTheme.goldGradient.createShader(bounds),
          child: Text(
            '멜론티켓',
            style: AppTheme.nanum(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
              shadows: AppTheme.textShadowStrong,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isSignUp ? '이메일로 간편하게 가입하세요' : '다시 만나서 반가워요',
          style: AppTheme.nanum(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  "최근" Badge
  // ──────────────────────────────────────────────

  Widget _buildRecentBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppTheme.goldGradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '최근',
        style: AppTheme.nanum(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFDF3F6),
          shadows: AppTheme.textShadowOnDark,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  네이버 로그인 (최상단 강조 — 크고 눈에 띄게)
  // ──────────────────────────────────────────────

  Widget _buildNaverPrimaryButton() {
    final isLastUsed = _lastLoginProvider == 'naver';

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF03C75A),
        borderRadius: BorderRadius.circular(16),
        border: isLastUsed
            ? Border.all(color: AppTheme.gold, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF03C75A).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _signInWithNaver,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: SvgPicture.string(_naverLogoSvg, width: 22, height: 22),
                  ),
                ),
                if (isLastUsed) ...[
                  const SizedBox(width: 8),
                  _buildRecentBadge(),
                ],
                const Spacer(),
                Text(
                  '네이버로 시작하기',
                  style: AppTheme.nanum(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  보조 로그인 버튼 Row (카카오 · 구글 · 전화번호)
  // ──────────────────────────────────────────────

  Widget _buildSecondaryLoginRow() {
    return Row(
      children: [
        Expanded(child: _buildSecondaryButton(
          providerKey: 'kakao',
          label: '카카오',
          color: const Color(0xFFFEE500),
          textColor: const Color(0xFF191600),
          logoWidget: SvgPicture.string(_kakaoLogoSvg, width: 18, height: 18),
          onTap: _signInWithKakao,
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildSecondaryButton(
          providerKey: 'google',
          label: 'Google',
          color: AppTheme.card,
          textColor: AppTheme.textPrimary,
          logoWidget: SvgPicture.string(_googleLogoSvg, width: 18, height: 18),
          onTap: _signInWithGoogle,
          borderColor: AppTheme.border,
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildSecondaryButton(
          providerKey: 'phone',
          label: '전화번호',
          color: AppTheme.card,
          textColor: AppTheme.textPrimary,
          logoWidget: const Icon(
            Icons.phone_android_rounded,
            size: 18,
            color: AppTheme.textSecondary,
          ),
          onTap: _signInWithPhone,
          borderColor: AppTheme.border,
        )),
      ],
    );
  }

  Widget _buildSecondaryButton({
    required String providerKey,
    required String label,
    required Color color,
    required Color textColor,
    required Widget logoWidget,
    required VoidCallback onTap,
    Color? borderColor,
  }) {
    final isLastUsed = _lastLoginProvider == providerKey;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLastUsed ? AppTheme.gold : (borderColor ?? Colors.transparent),
          width: isLastUsed ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 20, height: 20, child: Center(child: logoWidget)),
              const SizedBox(height: 4),
              if (isLastUsed)
                _buildRecentBadge()
              else
                Text(
                  label,
                  style: AppTheme.nanum(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Email Divider ("또는 이메일로 로그인")
  // ──────────────────────────────────────────────

  Widget _buildEmailDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppTheme.border, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _isSignUp ? '또는 이메일로 가입' : '또는 이메일로 로그인',
            style: AppTheme.nanum(
              color: AppTheme.textTertiary,
              fontSize: 13,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppTheme.border, thickness: 0.5)),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Field Label
  // ──────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: AppTheme.nanum(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Email Field
  // ──────────────────────────────────────────────

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      focusNode: _emailFocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      style: AppTheme.nanum(
        fontSize: 15,
        color: AppTheme.textPrimary,
      ),
      cursorColor: AppTheme.gold,
      decoration: InputDecoration(
        hintText: 'email@example.com',
        prefixIcon: const Icon(
          Icons.mail_outline_rounded,
          color: AppTheme.textTertiary,
          size: 20,
        ),
        filled: true,
        fillColor: AppTheme.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle:
            AppTheme.nanum(fontSize: 15, color: AppTheme.textTertiary),
        errorStyle: AppTheme.nanum(fontSize: 12, color: AppTheme.error),
      ),
      onFieldSubmitted: (_) {
        FocusScope.of(context).requestFocus(_passwordFocus);
      },
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '이메일을 입력해주세요';
        }
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
          return '올바른 이메일 형식이 아닙니다';
        }
        return null;
      },
    );
  }

  // ──────────────────────────────────────────────
  //  Password Field
  // ──────────────────────────────────────────────

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      style: AppTheme.nanum(
        fontSize: 15,
        color: AppTheme.textPrimary,
      ),
      cursorColor: AppTheme.gold,
      decoration: InputDecoration(
        hintText: '6자 이상 입력',
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: AppTheme.textTertiary,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppTheme.textTertiary,
            size: 20,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        filled: true,
        fillColor: AppTheme.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle:
            AppTheme.nanum(fontSize: 15, color: AppTheme.textTertiary),
        errorStyle: AppTheme.nanum(fontSize: 12, color: AppTheme.error),
      ),
      onFieldSubmitted: (_) => _submit(),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '비밀번호를 입력해주세요';
        }
        if (value.length < 6) {
          return '비밀번호는 6자 이상이어야 합니다';
        }
        return null;
      },
    );
  }

  // ──────────────────────────────────────────────
  //  Primary Action Button (Gold Gradient)
  // ──────────────────────────────────────────────

  Widget _buildPrimaryButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: _isLoading ? null : AppTheme.goldGradient,
        color: _isLoading ? AppTheme.border : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: _isLoading
            ? null
            : const [
                BoxShadow(
                  color: AppTheme.goldSubtle,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _submit,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.textTertiary,
                    ),
                  )
                : Text(
                    _isSignUp ? '회원가입' : '이메일로 로그인',
                    style: AppTheme.nanum(
                      color: const Color(0xFFFDF3F6),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      shadows: AppTheme.textShadowOnDark,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminApprovalRequestBox() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: CheckboxListTile(
        value: _requestAdminApproval,
        onChanged: _isLoading
            ? null
            : (value) {
                setState(() => _requestAdminApproval = value ?? false);
              },
        activeColor: AppTheme.gold,
        checkColor: const Color(0xFFFDF3F6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          '티켓 어드민 승인 신청',
          style: AppTheme.nanum(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            shadows: AppTheme.textShadow,
          ),
        ),
        subtitle: Text(
          '가입 시 바로 관리자 권한이 부여되지 않으며 오너 승인 후 활성화됩니다.',
          style: AppTheme.nanum(
            fontSize: 11,
            color: AppTheme.textTertiary,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Guest Button (체험하기)
  // ──────────────────────────────────────────────

  Widget _buildGuestButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _signInAsGuest,
      child: Center(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '로그인 없이 ',
                style: AppTheme.nanum(
                  fontSize: 14,
                  color: AppTheme.textTertiary,
                ),
              ),
              TextSpan(
                text: '체험하기',
                style: AppTheme.nanum(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gold,
                  decoration: TextDecoration.underline,
                ).copyWith(decorationColor: AppTheme.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Tab-style Toggle (로그인 / 회원가입)
  // ──────────────────────────────────────────────

  Widget _buildTabToggle() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          _buildTab('로그인', !_isSignUp),
          _buildTab('회원가입', _isSignUp),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isActive) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          final wantSignUp = label == '회원가입';
          if (_isSignUp != wantSignUp) {
            setState(() {
              _isSignUp = wantSignUp;
              _requestAdminApproval = false;
            });
            _formKey.currentState?.reset();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: isActive ? AppTheme.goldGradient : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: AppTheme.goldSubtle,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTheme.nanum(
                fontSize: 15,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFFFDF3F6)
                    : AppTheme.textSecondary,
                shadows: isActive ? AppTheme.textShadowOnDark : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 전화번호 입력 포맷터: 01012345678 → 010-1234-5678
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i == 3 || i == 7) buffer.write('-');
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

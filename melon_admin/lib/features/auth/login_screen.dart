import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

// ─── Brand Logo SVGs ───
const _kakaoLogoSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 3C6.48 3 2 6.36 2 10.5c0 2.69 1.82 5.04 4.55 6.35l-.97 3.54c-.08.28.18.52.41.35l3.66-2.45c.77.12 1.57.17 2.38.17 5.52 0 10-3.33 10-7.46S17.52 3 12 3z" fill="#191600"/>'
    '</svg>';

const _naverLogoSvg =
    '<svg viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M13.56 10.07L6.28 0H0v20h6.44V9.93L13.72 20H20V0h-6.44v10.07z" fill="white"/>'
    '</svg>';

const _googleLogoSvg =
    '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M43.6 20.1H42V20H24v8h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 8 3l5.7-5.7C34 6.1 29.3 4 24 4 13 4 4 13 4 24s9 20 20 20 20-9 20-20c0-1.3-.1-2.7-.4-3.9z" fill="#FFC107"/>'
    '<path d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 8 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" fill="#FF3D00"/>'
    '<path d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2A11.9 11.9 0 0124 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z" fill="#4CAF50"/>'
    '<path d="M43.6 20.1H42V20H24v8h11.3a12 12 0 01-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.7-.4-3.9z" fill="#1976D2"/>'
    '</svg>';

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
                style: AdminTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.onAccent,
                ),
              ),
              backgroundColor: AdminTheme.info,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }

      if (mounted) {
        context.go('/');
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
        context.go('/');
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
        context.go('/');
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
        context.go('/');
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
                style: AdminTheme.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AdminTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 32,
                  right: 32,
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
                      const SizedBox(height: 40),

                      // --- Social login ---
                      _buildSocialButton(
                        label: '카카오로 계속하기',
                        color: const Color(0xFFFEE500),
                        textColor: const Color(0xFF191919),
                        logoWidget: SvgPicture.string(_kakaoLogoSvg,
                            width: 20, height: 20),
                        onTap: _signInWithKakao,
                      ),
                      const SizedBox(height: 10),
                      _buildSocialButton(
                        label: '네이버로 계속하기',
                        color: const Color(0xFF03C75A),
                        textColor: Colors.white,
                        logoWidget: SvgPicture.string(_naverLogoSvg,
                            width: 18, height: 18),
                        onTap: _signInWithNaver,
                      ),
                      const SizedBox(height: 10),
                      _buildSocialButton(
                        label: 'Google로 계속하기',
                        color: AdminTheme.surface,
                        textColor: AdminTheme.textPrimary,
                        logoWidget: SvgPicture.string(_googleLogoSvg,
                            width: 22, height: 22),
                        onTap: _signInWithGoogle,
                        border: true,
                      ),
                      const SizedBox(height: 28),

                      // --- Divider ---
                      _buildDivider(),
                      const SizedBox(height: 28),

                      // --- Email Field ---
                      _buildLabel('EMAIL'),
                      const SizedBox(height: 8),
                      _buildEmailField(),
                      const SizedBox(height: 24),

                      // --- Password Field ---
                      _buildLabel('PASSWORD'),
                      const SizedBox(height: 8),
                      _buildPasswordField(),
                      if (_isSignUp) ...[
                        const SizedBox(height: 14),
                        _buildAdminApprovalRequestBox(),
                      ],
                      const SizedBox(height: 32),

                      // --- Primary Action Button ---
                      _buildPrimaryButton(),
                      const SizedBox(height: 20),

                      // --- Toggle Sign Up / Sign In ---
                      _buildToggleRow(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
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
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: AdminTheme.goldGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AdminTheme.gold.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'M',
                style: AdminTheme.serif(
                  color: AdminTheme.onAccent,
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          ShaderMask(
            shaderCallback: (bounds) =>
                AdminTheme.goldGradient.createShader(bounds),
            child: Text(
              'MELON TICKET',
              style: AdminTheme.label(fontSize: 15, color: Colors.white)
                  .copyWith(letterSpacing: 3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ADMIN',
            style: AdminTheme.label(fontSize: 10, color: AdminTheme.sage)
                .copyWith(letterSpacing: 4),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Title
  // ──────────────────────────────────────────────

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          _isSignUp ? '새 계정 만들기' : '다시 만나서 반가워요',
          style: AdminTheme.serif(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AdminTheme.textPrimary,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          _isSignUp ? '관리자 계정을 만들어보세요' : '계정에 로그인해 주세요',
          style: AdminTheme.sans(
            fontSize: 14,
            color: AdminTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Social Login Button (Kakao, Naver)
  // ──────────────────────────────────────────────

  Widget _buildSocialButton({
    required String label,
    required Color color,
    required Color textColor,
    required Widget logoWidget,
    required VoidCallback onTap,
    bool border = false,
  }) {
    return PressableScale(
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: border
              ? Border.all(color: AdminTheme.border, width: 0.5)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(child: logoWidget)),
                  const Spacer(),
                  Text(
                    label,
                    style: AdminTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Divider
  // ──────────────────────────────────────────────

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(
            child: Divider(color: AdminTheme.border, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '또는 이메일로 계속',
            style: AdminTheme.sans(
              color: AdminTheme.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
        const Expanded(
            child: Divider(color: AdminTheme.border, thickness: 0.5)),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Field Label
  // ──────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: AdminTheme.label(fontSize: 10, color: AdminTheme.sage),
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
      style: AdminTheme.sans(
        fontSize: 15,
        color: AdminTheme.textPrimary,
      ),
      cursorColor: AdminTheme.gold,
      decoration: InputDecoration(
        hintText: 'email@example.com',
        hintStyle: AdminTheme.sans(fontSize: 14, color: AdminTheme.textTertiary),
        errorStyle: AdminTheme.sans(fontSize: 12, color: AdminTheme.error),
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
      style: AdminTheme.sans(
        fontSize: 15,
        color: AdminTheme.textPrimary,
      ),
      cursorColor: AdminTheme.gold,
      decoration: InputDecoration(
        hintText: '6자 이상 입력',
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AdminTheme.textTertiary,
            size: 20,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        hintStyle: AdminTheme.sans(fontSize: 14, color: AdminTheme.textTertiary),
        errorStyle: AdminTheme.sans(fontSize: 12, color: AdminTheme.error),
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
  //  Primary Action Button (ShimmerButton)
  // ──────────────────────────────────────────────

  Widget _buildPrimaryButton() {
    return ShimmerButton(
      text: _isSignUp ? '회원가입' : '이메일로 로그인',
      onPressed: _isLoading ? null : _submit,
      height: 52,
      borderRadius: 4,
    );
  }

  Widget _buildAdminApprovalRequestBox() {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: CheckboxListTile(
        value: _requestAdminApproval,
        onChanged: _isLoading
            ? null
            : (value) {
                setState(() => _requestAdminApproval = value ?? false);
              },
        activeColor: AdminTheme.gold,
        checkColor: AdminTheme.onAccent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          '티켓 어드민 승인 신청',
          style: AdminTheme.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          '가입 시 바로 관리자 권한이 부여되지 않으며 오너 승인 후 활성화됩니다.',
          style: AdminTheme.sans(
            fontSize: 11,
            color: AdminTheme.textTertiary,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Toggle Row (Sign Up / Sign In)
  // ──────────────────────────────────────────────

  Widget _buildToggleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUp ? '이미 계정이 있으신가요?' : '계정이 없으신가요?',
          style: AdminTheme.sans(
            color: AdminTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _isSignUp = !_isSignUp;
              _requestAdminApproval = false;
            });
            _formKey.currentState?.reset();
          },
          child: Text(
            _isSignUp ? '로그인' : '회원가입',
            style: AdminTheme.sans(
              color: AdminTheme.gold,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

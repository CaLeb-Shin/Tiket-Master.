import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/widgets/premium_effects.dart';

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
                        icon: Icons.chat_bubble_rounded,
                        onTap: _signInWithKakao,
                      ),
                      const SizedBox(height: 10),
                      _buildSocialButton(
                        label: '네이버로 계속하기',
                        color: const Color(0xFF03C75A),
                        textColor: Colors.white,
                        icon: Icons.north_east_rounded,
                        onTap: _signInWithNaver,
                      ),
                      const SizedBox(height: 10),
                      _buildGoogleButton(),
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AdminTheme.goldGradient,
              borderRadius: BorderRadius.circular(4),
              boxShadow: AdminShadows.elevated,
            ),
            child: Center(
              child: Text(
                'M',
                style: AdminTheme.serif(
                  color: AdminTheme.onAccent,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'MELON TICKET',
            style: AdminTheme.label(
              fontSize: 13,
              color: AdminTheme.gold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ADMIN',
            style: AdminTheme.label(
              fontSize: 9,
              color: AdminTheme.sage,
            ),
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
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
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
                  Icon(icon, size: 20, color: textColor),
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
                  const SizedBox(width: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Google Login Button
  // ──────────────────────────────────────────────

  Widget _buildGoogleButton() {
    return PressableScale(
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AdminTheme.border, width: 0.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _signInWithGoogle,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4285F4),
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Google로 계속하기',
                    style: AdminTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.textPrimary,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/services/auth_service.dart';

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

  Future<void> _signInAsGuest() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInAnonymously();
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        _showError('체험 로그인 실패: ${_parseErrorMessage(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

                  // --- Divider ---
                  _buildDivider(),
                  const SizedBox(height: 20),

                  // --- 소셜 로그인 버튼 ---
                  _buildSocialButton(
                    label: '카카오로 계속하기',
                    color: const Color(0xFFFEE500),
                    textColor: const Color(0xFF191600),
                    logoWidget: SvgPicture.string(_kakaoLogoSvg, width: 20, height: 20),
                    onTap: _signInWithKakao,
                  ),
                  const SizedBox(height: 10),
                  _buildSocialButton(
                    label: '네이버로 계속하기',
                    color: const Color(0xFF03C75A),
                    textColor: Colors.white,
                    logoWidget: SvgPicture.string(_naverLogoSvg, width: 18, height: 18),
                    onTap: _signInWithNaver,
                  ),
                  const SizedBox(height: 10),
                  _buildGoogleButton(),
                  const SizedBox(height: 20),

                  // --- 체험하기 (게스트) ---
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
  //  소셜 로그인 버튼 (카카오, 네이버)
  // ──────────────────────────────────────────────

  Widget _buildSocialButton({
    required String label,
    required Color color,
    required Color textColor,
    required Widget logoWidget,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(width: 24, height: 24, child: Center(child: logoWidget)),
                const Spacer(),
                Text(
                  label,
                  style: AppTheme.nanum(
                    fontSize: 15,
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
    );
  }

  // ──────────────────────────────────────────────
  //  Google Login Button
  // ──────────────────────────────────────────────

  Widget _buildGoogleButton() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _signInWithGoogle,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppTheme.goldSubtle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: SvgPicture.string(_googleLogoSvg, width: 24, height: 24),
                ),
                const Spacer(),
                Text(
                  'Google로 계속하기',
                  style: AppTheme.nanum(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 24),
              ],
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
        const Expanded(child: Divider(color: AppTheme.border, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '또는 소셜 계정으로 계속',
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

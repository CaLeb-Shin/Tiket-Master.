import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../services/functions_service.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  late final MobileScannerController _controller;
  bool _isProcessing = false;
  _ScanResultData? _lastResult;
  Timer? _resultDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _resultDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  //  QR Processing
  // ──────────────────────────────────────────────

  Future<void> _processQrCode(String qrData) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _lastResult = null;
    });

    try {
      final raw = qrData.trim();
      final authUser = ref.read(authStateProvider).valueOrNull;
      if (authUser == null) {
        throw const FormatException('스캐너 사용 전 로그인이 필요합니다');
      }

      // 권장 형식: ticketId:jwtToken
      final sepIndex = raw.indexOf(':');
      if (sepIndex <= 0 || sepIndex >= raw.length - 1) {
        throw const FormatException('지원하지 않는 QR 형식입니다');
      }

      final ticketId = raw.substring(0, sepIndex);
      final qrToken = raw.substring(sepIndex + 1);

      if (RegExp(r'^ticket:[^:]+:\d+$').hasMatch(raw)) {
        throw const FormatException('구버전 QR입니다. 티켓 앱을 최신 버전으로 업데이트해주세요');
      }

      final functionsService = ref.read(functionsServiceProvider);
      final result = await functionsService.verifyAndCheckIn(
        ticketId: ticketId,
        qrToken: qrToken,
        staffId: authUser.uid,
      );

      final success = result['success'] == true;
      final message =
          result['message'] as String? ?? (success ? '입장 성공' : '입장 실패');
      final seatInfo = result['seatInfo'] as String?;

      setState(() {
        _lastResult = _ScanResultData(
          isSuccess: success,
          title: success ? '입장 확인' : '입장 불가',
          message: message,
          seatInfo: seatInfo,
        );
      });
    } on FormatException catch (e) {
      setState(() {
        _lastResult = _ScanResultData(
          isSuccess: false,
          title: '인식 오류',
          message: e.message,
        );
      });
    } catch (e) {
      setState(() {
        _lastResult = _ScanResultData(
          isSuccess: false,
          title: '처리 실패',
          message: e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim(),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);

        // Auto-dismiss result after 3 seconds and resume scanning
        _resultDismissTimer?.cancel();
        _resultDismissTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _lastResult = null);
            _controller.start();
          }
        });
      }
    }
  }

  // ──────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Stack(
              children: [
                // Camera view
                _buildCameraView(),

                // Scan area overlay
                _buildScanOverlay(),

                // Instruction label
                _buildInstructionBadge(),

                // Processing indicator
                if (_isProcessing) _buildProcessingOverlay(),

                // Result overlay
                if (_lastResult != null && !_isProcessing)
                  _buildResultOverlay(_lastResult!),
              ],
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Header
  // ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 8,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary,
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              fixedSize: const Size(40, 40),
            ),
          ),
          const SizedBox(width: 12),

          // Title with gold accent
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFFFDF3F6),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '입장 스캐너',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Flash toggle
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, child) {
              final isOn = state.torchState == TorchState.on;
              return IconButton(
                onPressed: () => _controller.toggleTorch(),
                icon: Icon(
                  isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: isOn ? AppTheme.gold : AppTheme.textSecondary,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  fixedSize: const Size(40, 40),
                ),
              );
            },
          ),
          const SizedBox(width: 6),

          // Camera switch
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(
              Icons.cameraswitch_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              fixedSize: const Size(40, 40),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Camera View
  // ──────────────────────────────────────────────

  Widget _buildCameraView() {
    return ClipRRect(
      child: MobileScanner(
        controller: _controller,
        errorBuilder: (context, error, child) {
          return _buildCameraError(error);
        },
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          if (barcode?.rawValue != null && !_isProcessing) {
            _controller.stop();
            _processQrCode(barcode!.rawValue!);
          }
        },
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: const Icon(
                  Icons.videocam_off_rounded,
                  size: 40,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '카메라를 사용할 수 없습니다',
                style: GoogleFonts.notoSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '설정에서 카메라 권한을 허용해주세요',
                style: GoogleFonts.notoSans(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _controller.start(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  '다시 시도',
                  style: GoogleFonts.notoSans(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gold,
                  side: const BorderSide(color: AppTheme.gold, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Scan Overlay (Viewfinder)
  // ──────────────────────────────────────────────

  Widget _buildScanOverlay() {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 260,
          height: 260,
          child: CustomPaint(
            painter: _ViewfinderPainter(
              cornerColor: AppTheme.gold,
              borderColor: AppTheme.goldSubtle,
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Instruction Badge
  // ──────────────────────────────────────────────

  Widget _buildInstructionBadge() {
    return Positioned(
      top: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC0B0B0F),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.goldSubtle,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.qr_code_rounded,
                color: AppTheme.gold,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'QR 코드를 영역 안에 맞춰주세요',
                style: GoogleFonts.notoSans(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Processing Overlay
  // ──────────────────────────────────────────────

  Widget _buildProcessingOverlay() {
    return Container(
      color: const Color(0xAA0B0B0F),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppTheme.gold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '확인 중...',
                style: GoogleFonts.notoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Result Overlay
  // ──────────────────────────────────────────────

  Widget _buildResultOverlay(_ScanResultData result) {
    final color = result.isSuccess ? AppTheme.success : AppTheme.error;

    return GestureDetector(
      onTap: () {
        _resultDismissTimer?.cancel();
        setState(() => _lastResult = null);
        _controller.start();
      },
      child: Container(
        color: Color.lerp(const Color(0xFF0B0B0F), color, 0.08),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(40),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    result.isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 44,
                    color: color,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  result.title,
                  style: GoogleFonts.notoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),

                // Message
                Text(
                  result.message,
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Seat info
                if (result.seatInfo != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.event_seat_rounded,
                          color: AppTheme.gold,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          result.seatInfo!,
                          style: GoogleFonts.notoSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Next scan button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: result.isSuccess ? null : AppTheme.goldGradient,
                      color: result.isSuccess ? AppTheme.success : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _resultDismissTimer?.cancel();
                          setState(() => _lastResult = null);
                          _controller.start();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Text(
                            '다음 스캔',
                            style: GoogleFonts.notoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: result.isSuccess
                                  ? Colors.white
                                  : const Color(0xFFFDF3F6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Bottom Panel
  // ──────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.goldSubtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: AppTheme.gold,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '티켓 QR을 스캔하세요',
                  style: GoogleFonts.notoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '입장객의 QR 코드를 카메라에 비춰주세요',
                  style: GoogleFonts.notoSans(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Status indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _isProcessing
                  ? AppTheme.gold
                  : (_lastResult != null
                      ? (_lastResult!.isSuccess
                          ? AppTheme.success
                          : AppTheme.error)
                      : AppTheme.success),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isProcessing
                          ? AppTheme.gold
                          : (_lastResult != null
                              ? (_lastResult!.isSuccess
                                  ? AppTheme.success
                                  : AppTheme.error)
                              : AppTheme.success))
                      .withAlpha(100),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Scan Result Data Model (local)
// ──────────────────────────────────────────────

class _ScanResultData {
  final bool isSuccess;
  final String title;
  final String message;
  final String? seatInfo;

  const _ScanResultData({
    required this.isSuccess,
    required this.title,
    required this.message,
    this.seatInfo,
  });
}

// ──────────────────────────────────────────────
//  Viewfinder Painter
// ──────────────────────────────────────────────

class _ViewfinderPainter extends CustomPainter {
  final Color cornerColor;
  final Color borderColor;

  _ViewfinderPainter({
    required this.cornerColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cornerLength = 32.0;
    const cornerRadius = 16.0;
    const strokeWidth = 3.5;

    // Draw subtle border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final borderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(cornerRadius),
    );
    canvas.drawRRect(borderRect, borderPaint);

    // Draw gold corner lines
    final cornerPaint = Paint()
      ..color = cornerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    _drawCorner(
        canvas, cornerPaint, 0, 0, cornerLength, cornerRadius, true, true);
    // Top-right corner
    _drawCorner(canvas, cornerPaint, size.width, 0, cornerLength, cornerRadius,
        false, true);
    // Bottom-left corner
    _drawCorner(canvas, cornerPaint, 0, size.height, cornerLength, cornerRadius,
        true, false);
    // Bottom-right corner
    _drawCorner(canvas, cornerPaint, size.width, size.height, cornerLength,
        cornerRadius, false, false);
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double length,
    double radius,
    bool isLeft,
    bool isTop,
  ) {
    final path = Path();
    final dx = isLeft ? 1.0 : -1.0;
    final dy = isTop ? 1.0 : -1.0;

    // Horizontal line
    path.moveTo(x + dx * length, y);
    path.lineTo(x + dx * radius, y);

    // Arc
    path.arcToPoint(
      Offset(x, y + dy * radius),
      radius: Radius.circular(radius),
      clockwise: isLeft == isTop,
    );

    // Vertical line
    path.lineTo(x, y + dy * length);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) {
    return oldDelegate.cornerColor != cornerColor ||
        oldDelegate.borderColor != borderColor;
  }
}

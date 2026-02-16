import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 시스템 UI 설정 - 프리미엄 다크
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting('ko_KR', null);

  runApp(
    const ProviderScope(
      child: MelonTicketApp(),
    ),
  );
}

class MelonTicketApp extends ConsumerWidget {
  const MelonTicketApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '멜론티켓',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: router,
      builder: (context, child) {
        return _LaunchIntroOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class _LaunchIntroOverlay extends StatefulWidget {
  final Widget child;
  const _LaunchIntroOverlay({required this.child});

  @override
  State<_LaunchIntroOverlay> createState() => _LaunchIntroOverlayState();
}

class _LaunchIntroOverlayState extends State<_LaunchIntroOverlay>
    with SingleTickerProviderStateMixin {
  static const _completeAt = Duration(milliseconds: 1300);
  static const _totalDuration = Duration(milliseconds: 1700);

  late final AnimationController _introController;
  Timer? _completeTimer;
  Timer? _finishTimer;
  bool _showComplete = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: _completeAt,
    )..forward();

    _completeTimer = Timer(_completeAt, () {
      if (!mounted) return;
      setState(() => _showComplete = true);
      unawaited(_playConnectionTone());
    });

    _finishTimer = Timer(_totalDuration, () {
      if (!mounted) return;
      setState(() => _finished = true);
    });
  }

  Future<void> _playConnectionTone() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _completeTimer?.cancel();
    _finishTimer?.cancel();
    _introController.dispose();
    super.dispose();
  }

  _RhythmStage _stageForProgress(double progress) {
    if (progress < 0.25) return _RhythmStage.whole;
    if (progress < 0.5) return _RhythmStage.half;
    if (progress < 0.75) return _RhythmStage.quarter;
    return _RhythmStage.eighthPair;
  }

  String _stageLabel(_RhythmStage stage) {
    switch (stage) {
      case _RhythmStage.whole:
        return '온음표';
      case _RhythmStage.half:
        return '2분음표';
      case _RhythmStage.quarter:
        return '4분음표';
      case _RhythmStage.eighthPair:
        return '8분음표 x2';
    }
  }

  Widget _buildProgressRhythm(double progress, _RhythmStage stage) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surface.withOpacity(0.45),
              border: Border.all(
                color: AppTheme.border.withOpacity(0.6),
                width: 1.2,
              ),
            ),
          ),
          SizedBox(
            width: 118,
            height: 118,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              backgroundColor: AppTheme.card.withOpacity(0.9),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
              strokeCap: StrokeCap.round,
            ),
          ),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.goldGradient,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.gold.withOpacity(0.28),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: _RhythmGlyph(
                key: ValueKey(stage),
                stage: stage,
                color: AppTheme.onAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _finished ? 0 : 1,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF080609),
                  Color(0xFF130A11),
                  Color(0xFF220E18),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _introController,
                builder: (context, _) {
                  final rawProgress = _introController.value.clamp(0.0, 1.0);
                  final progress = Curves.easeOutCubic.transform(rawProgress);
                  final stage = _showComplete
                      ? _RhythmStage.eighthPair
                      : _stageForProgress(progress);
                  final pulseScale = _showComplete
                      ? 1.03
                      : 1 + (math.sin(rawProgress * math.pi * 4) * 0.02);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: pulseScale,
                        child: _buildProgressRhythm(progress, stage),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _showComplete ? '로딩 완료!' : '앱 로딩 중...',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _showComplete ? 1 : 0.78,
                        child: Text(
                          _showComplete
                              ? '띠링~'
                              : '${(progress * 100).round()}% · ${_stageLabel(stage)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _showComplete
                                        ? AppTheme.goldLight
                                        : AppTheme.textTertiary,
                                    fontWeight: _showComplete
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _RhythmStage {
  whole,
  half,
  quarter,
  eighthPair,
}

class _RhythmGlyph extends StatelessWidget {
  final _RhythmStage stage;
  final Color color;

  const _RhythmGlyph({
    super.key,
    required this.stage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(40),
      painter: _RhythmGlyphPainter(stage: stage, color: color),
    );
  }
}

class _RhythmGlyphPainter extends CustomPainter {
  final _RhythmStage stage;
  final Color color;

  const _RhythmGlyphPainter({
    required this.stage,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    Rect headRect(double cx, double cy) => Rect.fromCenter(
          center: Offset(cx, cy),
          width: size.width * 0.34,
          height: size.height * 0.24,
        );

    switch (stage) {
      case _RhythmStage.whole:
        canvas.drawOval(headRect(size.width * 0.5, size.height * 0.62), stroke);
        break;
      case _RhythmStage.half:
        final head = headRect(size.width * 0.48, size.height * 0.64);
        canvas.drawOval(head, stroke);
        canvas.drawLine(
          Offset(head.right - 1, head.center.dy),
          Offset(head.right - 1, size.height * 0.2),
          stroke,
        );
        break;
      case _RhythmStage.quarter:
        final head = headRect(size.width * 0.48, size.height * 0.64);
        canvas.drawOval(head, fill);
        canvas.drawLine(
          Offset(head.right - 1, head.center.dy),
          Offset(head.right - 1, size.height * 0.2),
          stroke,
        );
        break;
      case _RhythmStage.eighthPair:
        final headLeft = headRect(size.width * 0.34, size.height * 0.68);
        final headRight = headRect(size.width * 0.66, size.height * 0.68);
        canvas.drawOval(headLeft, fill);
        canvas.drawOval(headRight, fill);

        final leftStemX = headLeft.right - 1;
        final rightStemX = headRight.right - 1;
        final stemTop = size.height * 0.26;
        canvas.drawLine(
          Offset(leftStemX, headLeft.center.dy),
          Offset(leftStemX, stemTop),
          stroke,
        );
        canvas.drawLine(
          Offset(rightStemX, headRight.center.dy),
          Offset(rightStemX, stemTop + 2),
          stroke,
        );

        final beam = Path()
          ..moveTo(leftStemX, stemTop)
          ..lineTo(rightStemX, stemTop + 2)
          ..lineTo(rightStemX, stemTop + 10)
          ..lineTo(leftStemX, stemTop + 8)
          ..close();
        canvas.drawPath(beam, fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _RhythmGlyphPainter oldDelegate) {
    return oldDelegate.stage != stage || oldDelegate.color != color;
  }
}

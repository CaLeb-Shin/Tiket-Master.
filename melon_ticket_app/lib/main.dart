import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';

/// 백그라운드 메시지 핸들러 (앱 종료 상태)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    const ProviderScope(
      child: MelonTicketApp(),
    ),
  );
}

class MelonTicketApp extends ConsumerStatefulWidget {
  const MelonTicketApp({super.key});

  @override
  ConsumerState<MelonTicketApp> createState() => _MelonTicketAppState();
}

class _MelonTicketAppState extends ConsumerState<MelonTicketApp> {
  bool _ready = false;
  bool _showComplete = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      await Future.wait([
        Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ),
        initializeDateFormatting('ko_KR', null),
        Future<void>.delayed(const Duration(milliseconds: 680)),
      ]);

      // FCM 초기화 (Firebase init 이후)
      unawaited(ref.read(fcmServiceProvider).initialize());

      if (!mounted) return;
      setState(() => _showComplete = true);
      unawaited(_playConnectionTone());

      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _startupError = '초기화 실패: $e';
      });
    }
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
  Widget build(BuildContext context) {
    if (_ready) {
      final router = ref.watch(routerProvider);
      return MaterialApp.router(
        title: '멜론티켓',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      );
    }

    return MaterialApp(
      title: '멜론티켓',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _BootNoteSplash(
        showComplete: _showComplete,
        error: _startupError,
      ),
    );
  }
}

class _BootNoteSplash extends StatefulWidget {
  final bool showComplete;
  final String? error;

  const _BootNoteSplash({
    required this.showComplete,
    required this.error,
  });

  @override
  State<_BootNoteSplash> createState() => _BootNoteSplashState();
}

class _BootNoteSplashState extends State<_BootNoteSplash>
    with SingleTickerProviderStateMixin {
  static const _stages = <_RhythmStage>[
    _RhythmStage.whole,
    _RhythmStage.half,
    _RhythmStage.quarter,
    _RhythmStage.eighthPair,
  ];

  late final AnimationController _beatController;

  @override
  void initState() {
    super.initState();
    _beatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _BootNoteSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showComplete && _beatController.isAnimating) {
      _beatController.stop();
    } else if (!widget.showComplete && !_beatController.isAnimating) {
      _beatController.repeat();
    }
  }

  @override
  void dispose() {
    _beatController.dispose();
    super.dispose();
  }

  int _activeIndex() {
    if (widget.showComplete) {
      return _stages.length - 1;
    }
    final value = (_beatController.value * _stages.length).floor();
    return value.clamp(0, _stages.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
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
            animation: _beatController,
            builder: (context, _) {
              final active = _activeIndex();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_stages.length, (idx) {
                      final isActive = idx <= active;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        transform: Matrix4.identity()
                          ..translate(0.0, isActive ? -4.0 : 0.0),
                        child: _RhythmGlyph(
                          stage: _stages[idx],
                          color: isActive
                              ? AppTheme.gold
                              : AppTheme.textTertiary.withOpacity(0.35),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.showComplete ? '로딩 완료!' : '로딩 중...',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.showComplete ? '띠링~' : '딱 · 딱 · 딱 · 딱',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: widget.showComplete
                              ? AppTheme.goldLight
                              : AppTheme.textTertiary,
                          fontWeight: widget.showComplete
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 320,
                      child: Text(
                        widget.error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
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
    required this.stage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(34),
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
      ..strokeWidth = 2.5
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

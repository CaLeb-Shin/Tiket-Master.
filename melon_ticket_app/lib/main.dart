import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'app/router.dart';
import 'app/theme.dart';

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
  static const _totalDuration = Duration(milliseconds: 1250);
  static const _completeAt = Duration(milliseconds: 700);

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  Timer? _completeTimer;
  Timer? _finishTimer;
  bool _showComplete = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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
    _pulseController.dispose();
    super.dispose();
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
                colors: [Color(0xFF080609), Color(0xFF130A11), Color(0xFF220E18)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _pulseScale,
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppTheme.goldGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.gold.withOpacity(0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppTheme.onAccent,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _showComplete ? '접속 완료!' : '접속 준비 중...',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _showComplete ? 1 : 0.55,
                    child: Text(
                      _showComplete ? '띠롱' : '잠시만 기다려주세요',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _showComplete
                                ? AppTheme.goldLight
                                : AppTheme.textTertiary,
                            fontWeight:
                                _showComplete ? FontWeight.w700 : FontWeight.w400,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

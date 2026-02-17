import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:melon_core/melon_core.dart';

import 'app/router.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: MelonAdminApp(),
    ),
  );
}

class MelonAdminApp extends ConsumerStatefulWidget {
  const MelonAdminApp({super.key});

  @override
  ConsumerState<MelonAdminApp> createState() => _MelonAdminAppState();
}

class _MelonAdminAppState extends ConsumerState<MelonAdminApp> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await Future.wait([
        Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ),
        initializeDateFormatting('ko_KR', null),
      ]);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(
            child: _error != null
                ? Text('초기화 오류: $_error',
                    style: const TextStyle(color: AppTheme.error))
                : const CircularProgressIndicator(color: AppTheme.gold),
          ),
        ),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '멜론티켓 관리자',
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
}

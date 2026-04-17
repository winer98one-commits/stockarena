// 📄 lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // ✅ 플랫폼 체크용
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'widgets/app_shell.dart';
import 'services/trading_calendar_service.dart';

// ✅ Firebase Core
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'package:shared_preferences/shared_preferences.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await TradingCalendarService.init();

  // ✅ Android / iOS / Web 에서만 Firebase 초기화 (Auth 쓰기 전에 먼저!)
  if (kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase.initializeApp() 완료');
  } else {
    debugPrint('⚠️ 이 플랫폼에서는 Firebase를 초기화하지 않습니다.');
  }

  final prefs = await SharedPreferences.getInstance();

  // ✅ (선택) 이미 로그인 되어있으면 UID를 game_uid에 저장
  // ※ Firebase 초기화 이후에 접근해야 안전함
  if (!prefs.containsKey('game_uid')) {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await prefs.setString('game_uid', user.uid);
      }
    } catch (e) {
      debugPrint('⚠️ currentUser 확인 실패: $e');
    }
  }

  debugPrint('✅ .env 로드 완료: ${dotenv.env.isNotEmpty}');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StockNote',

      // ✅ 다국어 연결
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko'),
        Locale('en'),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) return const Locale('ko');

        for (final s in supportedLocales) {
          if (s.languageCode == locale.languageCode) return s;
        }
        return const Locale('ko');
      },

      theme: ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: Colors.white, // ✅ 모든 Scaffold 기본 바탕 흰색
        canvasColor: Colors.white,             // ✅ Material/Drawer 등 바탕
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.teal,          // ✅ 포인트 컬러는 유지
          backgroundColor: Colors.white,
          cardColor: Colors.white,
          accentColor: Colors.teal,
          brightness: Brightness.light,
        ),
      ),
      home: const AppShell(),
    );
  }

}

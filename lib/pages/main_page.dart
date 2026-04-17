
import 'dart:async';                               // ✅ 추가

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ 추가


import 'trade_log_form.dart';
import '../widgets/trade_mode_toggle.dart';

import '../services/stocknote_server_api.dart';
import 'login_page.dart';


import 'package:shared_preferences/shared_preferences.dart'; // ✅ 추가

import '../services/quote_cache_service.dart';







class MainPage extends StatefulWidget {
  final String? selectedSymbol;          // ✅ 선택된 종목 코드
  final String? selectedName;            // ✅ 선택된 종목 이름

  // ✅ 추가: 검색/선택 시 AppShell에 "현재 선택 종목"만 알려주는 콜백
  final ValueChanged<String>? onSymbolChanged;

  // ✅ 별 버튼 눌렀을 때만 즐겨찾기 추가
  final Function(String)? onAddFavorite;

  final VoidCallback? onToggleFavoriteSidebar;

  final TradeMode initialMode;
  final ValueChanged<TradeMode>? onModeChanged;

  const MainPage({
    super.key,
    this.selectedSymbol,
    this.selectedName,

    // ✅ 추가
    this.onSymbolChanged,

    this.onAddFavorite,
    this.onToggleFavoriteSidebar,
    this.initialMode = TradeMode.log,
    this.onModeChanged,
  });



  @override
  State<MainPage> createState() => MainPageState(); // ✅ 수정됨
}



class MainPageState extends State<MainPage> {
  final _symbolCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _selectedName;

  String? _selectedSymbol;
  double? _latestQuotePrice; // ✅ 5분 저장 현재가
// 📌 수정 2: 상단 모드 상태 추가
  TradeMode _mode = TradeMode.log;
// ✅ 추가: 뒤로가기 두 번 눌러야 종료할 때 사용하는 시간 저장 변수
  DateTime? _lastBackPressed;

  // 🔹 추가: Firebase 로그인 사용자 정보
  User? _currentUser;
  StreamSubscription<User?>? _authSub;

// ✅ 표시용: 닉네임/이메일/uid
  String? _appUid;
  String? _appNickname;
  String? _appEmail;

  // ✅ 추가: SharedPreferences에서 uid 읽어서 상태 반영
// ✅ 추가: SharedPreferences에서 uid 읽어서 상태 반영
  // - log/game 계좌를 분리해 쓰는 구조를 반영해서,
  //   현재 모드에 따라 표시할 uid 키를 자동 선택한다.
  // - (호환) 예전 키: 'uid'
  Future<void> _refreshAppUid() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ 추가: 표시용 닉네임/이메일
    final nick = (prefs.getString('nickname') ?? '').trim();
    final mail = (prefs.getString('email') ?? '').trim();

    // 1) 모드별 키 우선
    final logUid = (prefs.getString('log_uid') ?? '').trim();
    final gameUid = (prefs.getString('game_uid') ?? '').trim();

    // 2) 예전 호환 키
    final legacyUid = (prefs.getString('uid') ?? '').trim();

    String? picked;

    // ✅ 현재 모드 우선 표시
    if (_mode == TradeMode.log) {
      picked = logUid.isNotEmpty ? logUid : null;
      picked ??= gameUid.isNotEmpty ? gameUid : null;
    } else {
      picked = gameUid.isNotEmpty ? gameUid : null;
      picked ??= logUid.isNotEmpty ? logUid : null;
    }

    // 3) 아무 것도 없으면 legacy → firebase uid/email 순으로 fallback
    picked ??= legacyUid.isNotEmpty ? legacyUid : null;

    final fbUser = FirebaseAuth.instance.currentUser;
    picked ??= (fbUser?.uid != null && fbUser!.uid.trim().isNotEmpty)
        ? fbUser.uid
        : null;

    final fallbackEmail = (fbUser?.email != null && fbUser!.email!.trim().isNotEmpty)
        ? fbUser.email!.trim()
        : null;

    if (!mounted) return;
    setState(() {
      _appUid = picked;
      _appNickname = nick.isNotEmpty ? nick : null;
      _appEmail = mail.isNotEmpty ? mail : (fallbackEmail ?? null);
    });
  }




  // 🔹 LoginPage 와 동일하게, Firebase 를 사용하는 플랫폼인지 체크
  bool get _isSupportedPlatform {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ✅ [추가] 통화/환율 관련 설정 -------------------------
  // 1달러 = 1400원 가정 (원하면 숫자 조정 가능)
  static const double _krwPerUsd = 1400.0;

  // 현재 선택된 심볼이 한국 주식인지 여부 (.KS / .KQ)
  bool get _isKoreanStock {
    final s = _selectedSymbol ?? '';
    return s.endsWith('.KS') || s.endsWith('.KQ');
  }

  // 원화 → 달러 변환 (한국 주식만 변환, 나머지는 그대로)
  double? _toUsd(double? value) {
    if (value == null) return null;
    if (!_isKoreanStock) return value; // 미국/지수/코인 등은 그대로
    return value / _krwPerUsd;
  }
  // ---------------------------------------------------

  // 서버 조회용 심볼 정규화
  String _normalizeSymbolForServer(String rawSymbol) {
    final s = rawSymbol.trim().toUpperCase();
    if (s.isEmpty) return s;

    // 이미 거래소/시장 접미사가 있으면 그대로 사용
    if (s.contains('.')) return s;

    // 코인: BTC-USD, ETH-USD 같은 형식은 .CC 사용
    if (s.contains('-USD')) return '$s.CC';

    // 그 외 기본은 미국 주식
    return '$s.US';
  }

  @override
  void didUpdateWidget(covariant MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ [추가] AppShell(TopBar)에서 모드가 바뀌면 MainPage 로컬 모드도 동기화
    if (widget.initialMode != oldWidget.initialMode) {
      setState(() {
        _mode = widget.initialMode;
      });

      // ✅ 모드별 uid 표시도 함께 갱신 (게임/매매일지 uid 분리 구조 대응)
      _refreshAppUid();
    }

    final newSymbol = widget.selectedSymbol;
    final oldSymbol = oldWidget.selectedSymbol;

    // ✅ 탑바/앱쉘에서 선택 종목이 바뀌면 바로 로드
    if (newSymbol != null && newSymbol.isNotEmpty && newSymbol != oldSymbol) {
      _loadData(newSymbol, name: widget.selectedName);
    }
  }

  // ✅ 추가: 저장된 모드를 불러오는 부분
  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;

    // ✅ 추가: 앱(서버용) uid 한 번 읽어오기
    _refreshAppUid();

    // ✅ 처음부터 화면에 종목명/심볼은 잡아둠
    final initialSymbol = widget.selectedSymbol;
    final initialName = widget.selectedName;

    if (initialSymbol != null && initialSymbol.isNotEmpty) {
      _selectedSymbol = _normalizeSymbolForServer(initialSymbol);
      _selectedName = initialName ?? initialSymbol;
    }

    // 🔹 Firebase 로그인 정보 구독 (웹/모바일에서만)
    if (_isSupportedPlatform) {
      _currentUser = FirebaseAuth.instance.currentUser;
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (!mounted) return;
        setState(() {
          _currentUser = user;
        });
      });
    }

    // ✅ (추가) AppShell/TopBar에서 이미 선택된 종목이 있으면, 화면 뜬 직후 로드
    if (initialSymbol != null && initialSymbol.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadData(initialSymbol, name: initialName);
      });
    }
  }


  @override
  void dispose() {
    _authSub?.cancel();       // ✅ Firebase 구독 해제
    _symbolCtrl.dispose();    // ✅ TextEditingController 정리
    super.dispose();
  }

  /// 이메일에서 앞부분만 잘라 기본 이름으로 사용
  String _getNameFromEmail(String? email) {
    if (email == null || email.isEmpty) return '사용자';
    final parts = email.split('@');
    if (parts.isEmpty || parts.first.isEmpty) return email;
    return parts.first;
  }

  /// AppBar 에 표시할 이름
  String _getDisplayNameForAppBar() {
    final user = _currentUser;
    if (user == null) {
      return '로그인';
    }
    return user.displayName ?? _getNameFromEmail(user.email);
  }

  /// AppBar 에 표시할 작은 아바타
  Widget _buildUserAvatarSmall() {
    final user = _currentUser;

    // 로그인 X → 기본 사람 아이콘
    if (user == null) {
      return const Icon(Icons.person_outline);
    }

    // 1순위: 구글 프로필 사진
    if (user.photoURL != null) {
      return CircleAvatar(
        radius: 12,
        backgroundImage: NetworkImage(user.photoURL!),
      );
    }

    // 2순위: 이름/이메일 앞 글자
    final name = user.displayName ?? _getNameFromEmail(user.email);
    final initial = name.isNotEmpty ? name.characters.first : '사용자';

    return CircleAvatar(
      radius: 12,
      backgroundColor: Colors.white24,
      child: Text(
        initial,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }















  // ✅ 차트 데이터 로드
  // ✅ 차트 데이터 로드 (차트 캐시 + 현재가 캐시 적용)
  Future<void> _loadData(String symbol, {String? name}) async {
    FocusScope.of(context).unfocus();

    final rawSymbol = symbol.trim();
    final symbolForServer = _normalizeSymbolForServer(rawSymbol);

    // 🔥 같은 종목이고 현재 로딩 중이 아니면 재호출 안 함
    if (_selectedSymbol == symbolForServer && !_loading) {
      return;
    }

    debugPrint(
      '🔍 _loadData input: symbol="$symbol", name="$name", rawSymbol="$rawSymbol", symbolForServer="$symbolForServer"',
    );

    final isSymbolChanged = _selectedSymbol != symbolForServer;

    setState(() {
      _loading = true;
      _error = null;

      // 🔥 핵심 추가
      if (isSymbolChanged) {
        _latestQuotePrice = null;
      }

      _symbolCtrl.text = symbol;
      _selectedName = name ?? _selectedName ?? symbol;
      _selectedSymbol = symbolForServer;
    });

    if (widget.onSymbolChanged != null) {
      widget.onSymbolChanged!("$symbolForServer|${_selectedName ?? symbol}");
    }

    try {
      debugPrint('📡 MainPage 현재가 요청 시작: $symbolForServer');

      final latestPrice = await QuoteCacheService.getLatestQuote(
        symbol: symbolForServer,
      );

      if (!mounted) return;

      setState(() {
        _latestQuotePrice = latestPrice;
        if (latestPrice == null) {
          _error = '현재가를 불러오지 못했습니다.';
        }
      });

      debugPrint('✅ 현재가 반영 완료: $latestPrice');
    } catch (e, st) {
      debugPrint('❌ _loadData error: $e');
      debugPrint('❌ _loadData stack: $st');

      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint("✅ 현재가 로드 완료");
    }
  }






  // ✅ 전체 UI 구성
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 🔹 안드로이드 하드웨어 뒤로가기 제어
      onWillPop: () async {
        // 1) 스택에 이전 페이지가 있으면 그냥 pop
        if (Navigator.of(context).canPop()) {
          return true;
        }

        // 2) MainPage가 루트일 때 → 두 번 눌러야 종료
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('뒤로가기를 한 번 더 누르면 앱이 종료됩니다.'),
              duration: Duration(seconds: 2),
            ),
          );

          return false; // 첫 번째 뒤로 → 종료하지 않음
        }

        // 2초 안에 두 번째 뒤로 → 종료 허용
        return true;
      },
      child: Scaffold(

        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),

                if (_selectedSymbol != null && _selectedSymbol!.isNotEmpty) ...[
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!),
                    ),

                  TradeLogForm(
                    key: ValueKey('${_selectedSymbol}_${_mode.name}'),
                    mode: _mode,
                    currentPrice: _toUsd(_latestQuotePrice),
                    symbol: _selectedSymbol,
                    companyName: _selectedName,
                    onDateChanged: null,
                    onRefreshPrice: () async {
                      final rawSymbol = _selectedSymbol ?? '';
                      if (rawSymbol.isEmpty) return null;

                      final latestPrice = await QuoteCacheService.refreshQuote(
                        symbol: rawSymbol,
                      );

                      if (mounted) {
                        setState(() {
                          _latestQuotePrice = latestPrice;
                        });
                      }

                      if (latestPrice == null) {
                        return null;
                      }

                      return _toUsd(latestPrice);
                    },
                    selectedDateHigh: null,
                    selectedDateLow: null,
                  ),
                ] else
                  const Center(
                    child: Text('종목을 먼저 선택해주세요.'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // ✅ MainPageState 안에 추가
  Future<void> loadFromTopBar(String symbol, String name) async {
    await loadFromOutside(symbol, name: name);
  }

  // 🔹 외부 호출용 함수
  Future<void> loadFromOutside(String symbol, {String? name}) async {
    await _loadData(symbol, name: name);


  }
}

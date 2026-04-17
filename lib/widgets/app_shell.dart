import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/favorite_sidebar.dart';
import '../pages/main_page.dart';
import '../pages/trade_log_page.dart';
import '../pages/profit_overview_page.dart';
import '../pages/ranking_page.dart';
import '../widgets/trade_mode_toggle.dart';
import '../pages/login_page.dart';
import '../pages/discussion_page.dart';
import '../l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../widgets/top_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  String? _selectedSymbol;
  String? _selectedName;
  String? _topUid; // ✅ 상단바 표시용 uid
  // ✅ (변경) 이제 _favorites는 "현재 선택된 폴더의 리스트"로만 쓰고,
  // 실제 저장은 _favoritesByFolder 에 폴더별로 저장한다.
  List<String> _favorites = [];

  final List<String> _folders = ['기본'];
  String _selectedFolder = '기본';

  // ✅ 추가: 폴더별 즐겨찾기 저장소
  final Map<String, List<String>> _favoritesByFolder = {
    '기본': <String>[],
  };


  bool _isSidebarOpen = false;

  // ✅ 매매일지 / 투자 게임 현재 모드
  TradeMode _tradeMode = TradeMode.log;

  final GlobalKey<MainPageState> _mainPageKey = GlobalKey<MainPageState>();


  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();

    // ✅ 앱 시작 직후 1회 시도
    _syncUidFromFirebase();

    // ✅ 중요: 재시작 시 currentUser가 늦게 복원되는 경우를 대비해 구독
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _syncUidFromFirebase(); // 유저 살아나는 순간 prefs를 다시 덮어씀
      }
    });

    _loadFavorites();
    _loadTradeMode(); // ✅ 저장된 매매 모드(log/game) 불러오기
    _loadLastAppState(); // ✅ 마지막 페이지/종목 복원
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }


  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ (추가) 구버전 즐겨찾기(폴더 없던 시절) 읽기
    final legacyFavorites = prefs.getStringList('favorites') ?? <String>[];

    // 1) 폴더 목록 로드 (없으면 기본)
    final savedFolders = prefs.getStringList('favorite_folders');
    if (savedFolders != null && savedFolders.isNotEmpty) {
      _folders
        ..clear()
        ..addAll(savedFolders);
    } else {
      // ✅ (추가) 폴더 목록 자체가 없으면 기본 폴더 보장
      if (_folders.isEmpty) _folders.add('기본');
    }

    // ✅ (추가) 혹시 기본 폴더가 목록에 없으면 강제로 추가
    if (!_folders.contains('기본')) {
      _folders.insert(0, '기본');
    }

    // 2) 선택 폴더 로드 (없으면 첫 폴더)
    final savedSelected = prefs.getString('favorite_selected_folder');
    if (savedSelected != null && _folders.contains(savedSelected)) {
      _selectedFolder = savedSelected;
    } else {
      _selectedFolder = _folders.isNotEmpty ? _folders.first : '기본';
      if (_folders.isEmpty) _folders.add('기본');
    }

    // 3) 폴더별 즐겨찾기 로드
    _favoritesByFolder.clear();
    for (final f in _folders) {
      final key = 'favorites_by_folder_$f';
      _favoritesByFolder[f] = prefs.getStringList(key) ?? <String>[];
    }

    // ✅ (추가) 마이그레이션: 폴더 방식 데이터가 비어있고,
    // 구버전 favorites에 데이터가 있으면 "기본" 폴더로 옮겨 담기
    final basicList = _favoritesByFolder['기본'] ?? <String>[];
    final hasFolderData = _favoritesByFolder.values.any((list) => list.isNotEmpty);

    if (!hasFolderData && legacyFavorites.isNotEmpty) {
      _favoritesByFolder['기본'] = List<String>.from(legacyFavorites);

      // ✅ 마이그레이션 저장 (한 번만 저장되게 폴더키로 저장)
      await prefs.setStringList('favorite_folders', _folders);
      await prefs.setString('favorite_selected_folder', _selectedFolder);
      await prefs.setStringList('favorites_by_folder_기본', _favoritesByFolder['기본']!);
    } else {
      // ✅ (추가) 기본 폴더가 null이면 안전하게 초기화
      _favoritesByFolder['기본'] = basicList;
    }

    // 4) 현재 폴더 즐겨찾기를 화면에 뿌릴 _favorites에 연결
    setState(() {
      _favorites = List<String>.from(_favoritesByFolder[_selectedFolder] ?? <String>[]);
    });
  }


  // ✅ 추가: 마지막에 사용한 매매 모드(log / game) 불러오기
  Future<void> _loadTradeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('global_trade_mode');

    setState(() {
      _tradeMode =
      (value == 'game') ? TradeMode.game : TradeMode.log; // 기본은 log
    });
  }

  Future<void> _syncUidFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();

    // ✅ 앱 전체에서 UID를 읽는 키가 여러 개일 수 있어서 안전하게 같이 저장
    await prefs.setString('uid', user.uid);
    await prefs.setString('user_uid', user.uid);
    await prefs.setString('firebase_uid', user.uid);

    // ✅ 상단바 표시용 (화면에도 반영)
    if (mounted) {
      setState(() {
        _topUid = user.uid;
      });
    }

    // 필요하면 이메일/닉네임도 같이 저장 가능
    if (user.email != null) {
      await prefs.setString('email', user.email!);
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ 폴더 목록/선택 폴더 저장
    await prefs.setStringList('favorite_folders', _folders);
    await prefs.setString('favorite_selected_folder', _selectedFolder);

    // ✅ 폴더별 즐겨찾기 저장
    for (final f in _folders) {
      final key = 'favorites_by_folder_$f';
      final list = _favoritesByFolder[f] ?? <String>[];
      await prefs.setStringList(key, list);
    }

    // ✅ 호환: 혹시 다른 곳이 아직 'favorites'를 보더라도 최소한 현재 폴더값 저장
    await prefs.setStringList('favorites', _favorites);
  }

  Future<void> _loadLastAppState() async {
    final prefs = await SharedPreferences.getInstance();

    final savedIndex = prefs.getInt('last_selected_index');
    final savedSymbol = prefs.getString('last_symbol');
    final savedName = prefs.getString('last_name');

    if (!mounted) return;

    setState(() {
      if (savedIndex != null && savedIndex >= 0 && savedIndex <= 4) {
        _selectedIndex = savedIndex;
      }
      _selectedSymbol = savedSymbol;
      _selectedName = savedName;
    });
  }

  Future<void> _saveLastAppState() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('last_selected_index', _selectedIndex);

    if (_selectedSymbol != null && _selectedSymbol!.isNotEmpty) {
      await prefs.setString('last_symbol', _selectedSymbol!);
    } else {
      await prefs.remove('last_symbol');
    }

    if (_selectedName != null && _selectedName!.isNotEmpty) {
      await prefs.setString('last_name', _selectedName!);
    } else {
      await prefs.remove('last_name');
    }
  }


  void _onSymbolChanged(String data) {
    final parts = data.split("|");
    final symbol = parts.first;
    final name = parts.length > 1 ? parts[1] : symbol;

    setState(() {
      _selectedSymbol = symbol;
      _selectedName = name;
    });

    unawaited(_saveLastAppState());
  }

  void _onAddFavorite(String input) {
    // ✅ input이 "TQQQ|US|ProShares..."처럼 올 수 있으니:
    // 마지막 조각을 name, 그 이전을 전부 symbol로 복원
    final parts = input.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    String symbol;
    String? passedName;

    if (parts.isEmpty) return;

    if (parts.length >= 2) {
      passedName = parts.last;
      symbol = parts.sublist(0, parts.length - 1).join('|'); // ✅ 심볼 복원 (TQQQ|US)
    } else {
      symbol = parts.first;
      passedName = null;
    }

    final currentList = _favoritesByFolder[_selectedFolder] ?? <String>[];

    // ✅ 이미 있나? (괄호 안 심볼로도 체크)
    final exists = currentList.any((item) {
      final m = RegExp(r'\(([^)]+)\)\s*$').firstMatch(item);
      final inside = m?.group(1)?.trim();
      return (inside != null && inside.isNotEmpty) ? inside == symbol : item.startsWith(symbol);
    });

    if (!exists) {
      final name = passedName ?? _selectedName ?? symbol;

      // 저장 포맷은 기존 유지: "SYMBOL|NAME (SYMBOL)"
      final fullName = "$symbol|$name ($symbol)";

      setState(() {
        currentList.add(fullName);
        _favoritesByFolder[_selectedFolder] = currentList;
        _favorites = List<String>.from(currentList);
      });

      _saveFavorites();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⭐ $name ($symbol) 즐겨찾기에 추가됨')),
          );
        }
      });
    }
  }




  void _onRemoveFavorite(String symbol) {
    final currentList = _favoritesByFolder[_selectedFolder] ?? <String>[];

    setState(() {
      currentList.removeWhere((item) => item.startsWith(symbol));
      _favoritesByFolder[_selectedFolder] = currentList;
      _favorites = List<String>.from(currentList);
    });

    _saveFavorites();
  }



  void _onFavoriteSelect(String symbol, String name) async {
    // ✅ favorites 항목은 "SYMBOL|NAME (SYMBOL)" 형태인데,
    // SYMBOL 자체에 "|"가 들어갈 수 있으므로 (예: TQQQ|US) split('|')는 위험함.
    final match = _favorites.firstWhere(
          (item) {
        // (1) 괄호 안 심볼로 매칭 우선
        final m = RegExp(r'\(([^)]+)\)\s*$').firstMatch(item);
        final inside = m?.group(1)?.trim();
        if (inside != null && inside.isNotEmpty) {
          return inside == symbol;
        }

        // (2) fallback: startsWith
        return item.startsWith(symbol);
      },
      orElse: () => symbol,
    );

    // ✅ 심볼 복구: "이름 (심볼)" 형태면 괄호 안 심볼을 우선 사용
    String symbolOnly = symbol.trim();
    String fullName = name.trim();

    final m2 = RegExp(r'\(([^)]+)\)\s*$').firstMatch(match);
    final inside2 = m2?.group(1)?.trim();
    if (inside2 != null && inside2.isNotEmpty) {
      symbolOnly = inside2;
    }

    // ✅ 이름 복구: 첫 번째 "|"로 자르면 깨질 수 있으니,
    // "첫 파이프 이후 전부"를 이름으로 취급 (AAPL|Apple (AAPL) → Apple (AAPL))
    if (match.contains('|')) {
      final idx = match.indexOf('|');
      if (idx >= 0 && idx < match.length - 1) {
        fullName = match.substring(idx + 1).trim();
      }
    }

    debugPrint("⭐ 즐겨찾기 클릭됨: $symbolOnly - $fullName");

    setState(() {
      _selectedSymbol = symbolOnly;
      _selectedName = fullName;
    });

    unawaited(_saveLastAppState());

    // ✅ 메인(검색) 탭이면 MainPage 내부 로직으로 반영
    if (_selectedIndex == 0) {
      _mainPageKey.currentState?.loadFromOutside(symbolOnly, name: fullName);
      return;
    }
  }




  void _onTabTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    unawaited(_saveLastAppState());
  }


// ✅ TopBar에서 모드 변경 시: AppShell + SharedPreferences 저장까지
  Future<void> _setTradeModeFromTopBar(TradeMode mode) async {
    // ✅ 랭킹(3), 토론(4)은 투자게임 고정: TopBar 눌러도 전역 모드 변경 X
    if (_selectedIndex == 3 || _selectedIndex == 4) return;

    setState(() => _tradeMode = mode);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'global_trade_mode',
      mode == TradeMode.game ? 'game' : 'log',
    );
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('앱 종료'),
          content: const Text('앱을 종료하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('종료'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }


  @override
  Widget build(BuildContext context) {
    final pages = [
      MainPage(
        key: _mainPageKey,
        selectedSymbol: _selectedSymbol,
        selectedName: _selectedName,

        // ✅ 추가: 검색/선택 시에는 선택만 갱신
        onSymbolChanged: _onSymbolChanged,

        // ✅ 별 버튼 눌렀을 때만 즐겨찾기 추가
        onAddFavorite: (symbolOrSymbolName) {
          _onAddFavorite(symbolOrSymbolName);
        },

        onToggleFavoriteSidebar: () {
          setState(() {
            _isSidebarOpen = !_isSidebarOpen;
          });
        },
        initialMode: _tradeMode,
        onModeChanged: (mode) async {
          setState(() => _tradeMode = mode);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'global_trade_mode',
            mode == TradeMode.game ? 'game' : 'log',
          );
        },
      ),
      TradeLogPage(
        key: ValueKey(_selectedSymbol),
        initialSymbol: _selectedSymbol ?? 'AAPL',
        initialName: _selectedName ?? 'Apple Inc.',
        favorites: _favorites,
        folders: _folders,

        // ✅ [추가] 거래내역 페이지에서도 사이드바 열기/닫기
        onToggleFavoriteSidebar: () {
          setState(() {
            _isSidebarOpen = !_isSidebarOpen;
          });
        },

        initialMode: _tradeMode,
        onModeChanged: (mode) async {
          setState(() => _tradeMode = mode);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'global_trade_mode',
            mode == TradeMode.game ? 'game' : 'log',
          );
        },
      ),
      ProfitOverviewPage(
        key: ValueKey('profit_${_tradeMode.name}'), // ✅ 모드 바뀌면 페이지 재생성

        // ✅ 수익률 페이지에서 종목 클릭 시 매매일지 탭으로 이동
        onSymbolTap: (symbol, name) {
          setState(() {
            _selectedSymbol = symbol;
            _selectedName = name;
            _selectedIndex = 1; // 매매일지 탭으로 변경
          });

          unawaited(_saveLastAppState());
        },

        // ✅ 추가: 현재 전역 모드 전달
        initialMode: _tradeMode,

        // ✅ 추가: 이 페이지에서 모드 바꾸면 AppShell + 저장까지
        onModeChanged: (mode) async {
          setState(() => _tradeMode = mode);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'global_trade_mode',
            mode == TradeMode.game ? 'game' : 'log',
          );
        },
      ),
      RankingPage(
        key: ValueKey('ranking_${_selectedSymbol ?? ""}_game'),

        selectedSymbol: _selectedSymbol,
        selectedName: _selectedName,

        onToggleFavoriteSidebar: () {
          setState(() {
            _isSidebarOpen = !_isSidebarOpen;
          });
        },

        onAddFavorite: (symbolOrSymbolName) {
          _onAddFavorite(symbolOrSymbolName);
        },

        // ✅ 랭킹은 무조건 투자게임
        initialMode: TradeMode.game,

        // ✅ 랭킹에서 모드 변경 금지
        onModeChanged: null,
      ),
      DiscussionPage(
        key: ValueKey('discussion_${_selectedSymbol ?? ''}'),
        symbolRaw: _selectedSymbol ?? 'AAPL.US',
        selectedSymbol: _selectedSymbol,
        selectedName: _selectedName,
        onToggleFavoriteSidebar: () {
          setState(() {
            _isSidebarOpen = !_isSidebarOpen;
          });
        },
        onAddFavorite: (symbolOrSymbolName) {
          _onAddFavorite(symbolOrSymbolName);
        },
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await _confirmExit();
        if (!mounted) return;

        if (shouldExit) {
          await SystemNavigator.pop();
        }
      },
        child: Scaffold(
          backgroundColor: Colors.white, // ✅ 추가: 전체 페이지 바탕 흰색 고정
          body: Column(
        children: [
          // ✅ 공통 상단바 (별도 위젯)

          SafeArea(
            bottom: false,
            child: TopBar(
              activeMode: (_selectedIndex == 3 || _selectedIndex == 4)
                  ? 'game'
                  : (_tradeMode == TradeMode.game ? 'game' : 'log'),
              uid: _topUid,
              onMenuTap: () {
                setState(() {
                  _isSidebarOpen = !_isSidebarOpen;
                });
              },
              onLogTap: () async {
                await _setTradeModeFromTopBar(TradeMode.log);
              },
              onGameTap: () async {
                await _setTradeModeFromTopBar(TradeMode.game);
              },

              // ✅ TopBar 검색(모달)에서 종목 선택 → AppShell 선택값 갱신 + 메인(차트)로 이동
// ✅ TopBar 검색(모달)에서 종목 선택 → "현재 페이지 유지" + "종목만 변경"
              onSymbolSelected: (symbol, name) {
                setState(() {
                  _selectedSymbol = symbol;
                  _selectedName = name;
                  // ✅ _selectedIndex 변경하지 않음 (페이지 이동 금지)
                });

                unawaited(_saveLastAppState());

                // ✅ 별도 호출 불필요:
                // - MainPage는 didUpdateWidget에서 selectedSymbol 변경을 감지해 자동 로드
                // - TradeLogPage / DiscussionPage는 key가 심볼 기반이라 자동 재생성
                // - RankingPage도 selectedSymbol 변경으로 표시 갱신(현재 코드 구조상)
              },

              // ✅ 검색칸 힌트(현재 선택 종목명)
              searchHint: _selectedName ?? '검색',

              // ✅ 별 버튼: 현재 종목 즐겨찾기 추가
              onStarTap: () {
                final symbol = _selectedSymbol;
                final name = _selectedName ?? symbol;

                if (symbol == null || symbol.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('먼저 종목을 선택하세요.')),
                  );
                  return;
                }

                _onAddFavorite('$symbol|${name ?? symbol}');
              },
            ),
          ),

          // ✅ 기존 Stack(페이지/사이드바) 영역
          Expanded(
            child: Stack(
              children: [
                // 메인 페이지
                Positioned.fill(
                  child: pages[_selectedIndex],
                ),

                // 사이드바 열려 있을 때만 오버레이 + 사이드바 표시
                if (_isSidebarOpen) ...[
                  // ⚫ 반투명 배경 – 바깥 클릭 시 닫힘
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSidebarOpen = false;
                        });
                      },
                      child: Container(
                        color: Colors.black.withOpacity(0.25),
                      ),
                    ),
                  ),

                  // ⭐ 실제 즐겨찾기 사이드바
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 300,
                    child: Material(
                      elevation: 12,
                      color: Colors.white,
                      child: FavoriteSidebar(
                        favorites: _favorites,
                        folders: _folders,
                        onAddFolder: (name) {
                          final n = name.trim();
                          if (n.isEmpty) return;
                          if (_folders.contains(n)) return;

                          setState(() {
                            _folders.add(n);
                            _favoritesByFolder[n] = <String>[];
                            _selectedFolder = n;
                            _favorites = <String>[];
                          });

                          _saveFavorites();
                        },
                        onSelectFolder: (folder) {
                          setState(() {
                            _selectedFolder = folder;
                            _favorites = List<String>.from(
                              _favoritesByFolder[folder] ?? <String>[],
                            );
                          });
                          _saveFavorites();
                        },
                        onMoveToFolder: (symbol, name, targetFolder) {
                          final fromFolder = _selectedFolder;

                          if (fromFolder == targetFolder) return;

                          final fromList =
                              _favoritesByFolder[fromFolder] ?? <String>[];
                          final toList =
                              _favoritesByFolder[targetFolder] ?? <String>[];

                          String? movingItem;
                          for (final item in fromList) {
                            if (item.startsWith(symbol)) {
                              movingItem = item;
                              break;
                            }
                          }

                          movingItem ??= '$symbol|$name ($symbol)';

                          setState(() {
                            fromList.removeWhere((it) => it.startsWith(symbol));
                            _favoritesByFolder[fromFolder] = fromList;

                            final exists =
                            toList.any((it) => it.startsWith(symbol));
                            if (!exists) {
                              toList.add(movingItem!);
                            }
                            _favoritesByFolder[targetFolder] = toList;

                            _favorites = List<String>.from(
                              _favoritesByFolder[_selectedFolder] ??
                                  <String>[],
                            );
                          });

                          _saveFavorites();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('📁 $symbol → $targetFolder 이동'),
                              ),
                            );
                          }
                        },
                        onSelect: (symbol, name) {
                          _onFavoriteSelect(symbol, name);
                          setState(() => _isSidebarOpen = false);
                        },
                        onRemove: _onRemoveFavorite,
                        onAdd: () {
                          if (_selectedSymbol != null) {
                            _onAddFavorite(_selectedSymbol!);
                          }
                        },
                        onToggleSidebar: () {
                          setState(() {
                            _isSidebarOpen = false;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),

          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onTabTap,
            backgroundColor: Colors.white,
            indicatorColor: Colors.black, // ✅ 선택시 타원형(캡슐) 배경: 검정
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.swap_horiz),
                selectedIcon: const Icon(Icons.swap_horiz, color: Colors.white), // ✅ 선택 아이콘 흰색
                label: '매매',
              ),
              NavigationDestination(
                icon: const Icon(Icons.list),
                selectedIcon: const Icon(Icons.list, color: Colors.white),
                label: AppLocalizations.of(context)!.tradeHistory,
              ),
              NavigationDestination(
                icon: const Icon(Icons.show_chart),
                selectedIcon: const Icon(Icons.show_chart, color: Colors.white),
                label: AppLocalizations.of(context)!.profit,
              ),
              NavigationDestination(
                icon: const Icon(Icons.leaderboard),
                selectedIcon: const Icon(Icons.leaderboard, color: Colors.white),
                label: AppLocalizations.of(context)!.ranking,
              ),
              NavigationDestination(
                icon: const Icon(Icons.forum),
                selectedIcon: const Icon(Icons.forum, color: Colors.white),
                label: AppLocalizations.of(context)!.discussion,
              ),
            ],
          ),
        ),
    );
  }
}

class _SimpleCenterPage extends StatelessWidget {
  final String title;
  const _SimpleCenterPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );


  }


}

// 📄 lib/widgets/top_bar.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'kospi_autocomplete.dart';
import '../pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TopBar extends StatefulWidget {
  final String activeMode; // "log" 또는 "game"
  final VoidCallback? onMenuTap;
  final VoidCallback? onLogTap;
  final VoidCallback? onGameTap;

  // 구버전 호환(지금은 TopBar에서 직접 KospiAutocomplete를 쓰므로 거의 안 씀)
  final VoidCallback? onSearchTap;

  // ✅ 검색에서 종목 선택되면 부모(AppShell)로 전달
  final void Function(String symbol, String name)? onSymbolSelected;

  // 즐겨찾기 클릭(부모 콜백)
  final VoidCallback? onStarTap;

  // uid 표시
  final String? uid;

  // 검색 힌트(현재 선택 종목명)
  final String searchHint;

  const TopBar({
    super.key,
    required this.activeMode,
    this.onMenuTap,
    this.onLogTap,
    this.onGameTap,
    this.onSearchTap,
    this.onSymbolSelected,
    this.onStarTap,
    this.uid,
    this.searchHint = '검색',
  });

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  // ⭐ 검정 별을 "잠깐"만 보여주기 위한 상태
  bool _isFavorite = false;

  final GlobalKey _modeTabKey = GlobalKey();
  Rect? _modeTabRect;

  Timer? _favoriteTimer;
  static const Duration _favoriteHold = Duration(seconds: 1); // ✅ 유지 시간(원하면 3~5로 변경)

  // ✅ 아이콘 버튼을 "더 붙게" 만드는 공통 옵션
  static const EdgeInsets _iconPad = EdgeInsets.zero;
  static const BoxConstraints _iconCons =
  BoxConstraints(minWidth: 30, minHeight: 30); // 너무 줄이면 탭하기 힘들어서 30 권장
  static const VisualDensity _dense = VisualDensity(horizontal: -4, vertical: -4);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateModeTabRect();
      _showModeGuideIfNeeded();
    });
  }

  Future<void> _showModeGuideIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_mode_guide') ?? false;
    if (seen) return;
    if (!mounted) return;

    await _showModeGuideOverlay();

    await prefs.setBool('seen_mode_guide', true);
  }

  Future<void> _showModeGuideOverlay() async {
    _updateModeTabRect();
    final rect = _modeTabRect;
    if (rect == null) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'mode_guide',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, a1, a2) {
        final screen = MediaQuery.of(ctx).size;

        final double holeLeft = rect.left;
        final double holeTop = rect.top;
        final double holeWidth = rect.width;
        final double holeHeight = rect.height;

        final bool showGuideBelow = holeTop + holeHeight + 210 < screen.height;
        final double guideTop =
        showGuideBelow ? (holeTop + holeHeight + 16) : (holeTop - 190);

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: holeTop,
                child: Container(color: Colors.black54),
              ),
              Positioned(
                left: 0,
                top: holeTop + holeHeight,
                right: 0,
                bottom: 0,
                child: Container(color: Colors.black54),
              ),
              Positioned(
                left: 0,
                top: holeTop,
                width: holeLeft,
                height: holeHeight,
                child: Container(color: Colors.black54),
              ),
              Positioned(
                left: holeLeft + holeWidth,
                top: holeTop,
                right: 0,
                height: holeHeight,
                child: Container(color: Colors.black54),
              ),

              Positioned(
                left: holeLeft,
                top: holeTop,
                width: holeWidth,
                height: holeHeight,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.white24,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 20,
                top: guideTop,
                right: 20,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 10,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '여기서 모드를 선택하세요',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111111),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '기록: 내가 한 거래를 저장합니다.\n'
                              '과거 날짜도 입력할 수 있어 매매일지 정리에 사용합니다.\n\n'
                              '게임: 가상 돈으로 투자 연습을 합니다.\n'
                              '현재가 기준으로 거래하고 결과는 순위에 반영됩니다.\n\n'
                              '먼저 기록 또는 게임을 눌러 원하는 모드를 선택해 주세요.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.55,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('확인'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, anim, a2, child) {
        return FadeTransition(
          opacity: anim,
          child: child,
        );
      },
    );
  }

  void _updateModeTabRect() {
    final ctx = _modeTabKey.currentContext;
    if (ctx == null) return;

    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _modeTabRect = Rect.fromLTWH(
      offset.dx - 8,
      offset.dy - 6,
      size.width + 16,
      size.height + 12,
    );
  }


  @override
  void dispose() {
    _favoriteTimer?.cancel();
    super.dispose();
  }

  // ✅ OFF: 가운데 빈 별(테두리) / ON: 전체 검정 별
  Widget _starIcon() {
    return Icon(
      _isFavorite ? Icons.star : Icons.star_border,
      color: Colors.black87,
    );
  }
  @override
  Widget build(BuildContext context) {
    // ✅ 폰트 규격: 18 / 16 / 14 / 12
    const double _nameFont = 20;   // 종목명
    const double _symbolFont = 18; // 심볼
    const double _tabFont = 16;    // 매매일지/투자게임

    // ✅ 탑바 압축(약 72 높이 체감): 상/하 패딩과 간격 축소
    const double _gapMenuToName = 8;
    const double _gapActionIcons = 4;
    const double _gapRows = 2; // 탭 위 여백 줄여서 한 화면에 더 들어오게

    final String raw = widget.searchHint.trim();

// ✅ 기본 표시 이름
    String name = raw.isEmpty ? '종목명' : raw;

// ✅ (1) "Apple Inc (AAPL)" 형태면 괄호 안 코드 제거하고 이름만
    final m1 = RegExp(r'^(.*)\(([^)]+)\)\s*$').firstMatch(raw);
    if (m1 != null) {
      name = m1.group(1)!.trim();
    } else {
      // ✅ (2) "Apple Inc AAPL" 형태면 마지막 토큰이 코드일 가능성이 높으니 제거
      final parts = raw.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        name = parts.sublist(0, parts.length - 1).join(' ').trim();
      }
    }

    Future<void> _openSearchDialog() async {
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'search',
        barrierColor: Colors.black.withOpacity(0.35),
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (ctx, a1, a2) {
          return SafeArea(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(color: Colors.transparent),
                ),
                Positioned(
                  top: 2,
                  left: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white,
                    elevation: 10,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: KospiAutocomplete(
                        onSelected: (s, n) {
                          Navigator.pop(ctx);
                          widget.onSymbolSelected?.call(s, n);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        transitionBuilder: (ctx, anim, a2, child) {
          final offset = Tween<Offset>(
            begin: const Offset(0, -0.03),
            end: Offset.zero,
          ).animate(anim);
          return SlideTransition(
            position: offset,
            child: FadeTransition(opacity: anim, child: child),
          );
        },
      );
    }

    return Container(
      // ✅ 요청: 배경 흰색
      color: Colors.white,

      // ✅ 상단 영역 압축: 좌우 8, 상단 4, 하단 0
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),

      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1줄
          Row(
            children: [
              // ✅ 아이콘 터치영역 확보(구석 클릭 어려움 해결)
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: const Icon(Icons.menu, color: Colors.black87, size: 22),
                  onPressed: widget.onMenuTap,
                  tooltip: '메뉴',
                ),
              ),

              const SizedBox(width: _gapMenuToName),

              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: _nameFont,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111111),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: const Icon(Icons.search, color: Colors.black87, size: 22),
                  onPressed: () async {
                    if (widget.onSearchTap != null) {
                      widget.onSearchTap!();
                    } else {
                      await _openSearchDialog();
                    }
                  },
                  tooltip: '검색',
                ),
              ),
              const SizedBox(width: _gapActionIcons),

              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(
                    _isFavorite ? Icons.star : Icons.star_border,
                    color: Colors.black87,
                    size: 22,
                  ),
                  onPressed: () {
                    if (_isFavorite) {
                      _favoriteTimer?.cancel();
                      setState(() => _isFavorite = false);
                      return;
                    }

                    setState(() => _isFavorite = true);
                    widget.onStarTap?.call();

                    _favoriteTimer?.cancel();
                    _favoriteTimer = Timer(_favoriteHold, () {
                      if (!mounted) return;
                      setState(() => _isFavorite = false);
                    });
                  },
                  tooltip: '즐겨찾기',
                ),
              ),
              const SizedBox(width: _gapActionIcons),

              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  tooltip: '로그인',
                  icon: const Icon(Icons.person, color: Colors.black87, size: 22),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                ),
              ),
            ],
          ),

          SizedBox(height: _gapRows),

          // 2줄: 탭
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  key: _modeTabKey,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _buildTab(
                      label: '기록',
                      selected: widget.activeMode == 'log',
                      onTap: widget.onLogTap,
                      fontSize: _tabFont,
                    ),
                    const SizedBox(width: 16),
                    _buildTab(
                      label: '게임',
                      selected: widget.activeMode == 'game',
                      onTap: widget.onGameTap,
                      fontSize: _tabFont,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFEEEEEE),
                ),
              ],
            ),
          ),

          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFEEEEEE),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required bool selected,
    VoidCallback? onTap,
    double fontSize = 14,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF111111) : const Color(0xFF888888),
                fontSize: fontSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 2,
              width: 56,
              color: selected ? const Color(0xFF111111) : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
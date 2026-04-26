// 📄 lib/pages/ranking_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';


import '../widgets/trade_mode_toggle.dart';

import 'trade_log_page.dart';


class RankingPage extends StatefulWidget {
  // ✅ AppShell에서 내려주는 현재 선택 종목 (즐겨찾기 클릭 시 갱신)
  final String? selectedSymbol;
  final String? selectedName;

  // ✅ 메인 페이지와 동일하게 AppShell 콜백들을 받아서 사용
  final VoidCallback? onToggleFavoriteSidebar;
  final Function(String)? onAddFavorite;

  final TradeMode initialMode;
  final ValueChanged<TradeMode>? onModeChanged;

  const RankingPage({
    super.key,
    this.selectedSymbol,
    this.selectedName,
    this.onToggleFavoriteSidebar,
    this.onAddFavorite,
    this.initialMode = TradeMode.log,
    this.onModeChanged,
  });

  @override
  State<RankingPage> createState() => _RankingPageState();
}




class _RankingPageState extends State<RankingPage> {
  TradeMode _mode = TradeMode.log;
  static const String _serverBaseUrl = "https://api.stockarena.co.kr";


  String? _selectedSymbol;
  String? _selectedName;

  bool _loadingRank = false;
  String? _rankError;

  List<_RankRow> _rows = [];

  @override
  void initState() {
    super.initState();

    // ✅ 랭킹은 투자게임 고정
    _mode = TradeMode.game;

    // ✅ AppShell에서 내려준 선택 종목을 내부 상태로 반영
    _selectedSymbol = widget.selectedSymbol;
    _selectedName = widget.selectedName;

    // ✅ 선택 종목이 있으면 바로 랭킹 로딩
    if (_selectedSymbol != null) {
      _loadRanking(_selectedSymbol!);
    }
  }


  @override
  void didUpdateWidget(covariant RankingPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newSymbol = widget.selectedSymbol;
    if (newSymbol != null && newSymbol != oldWidget.selectedSymbol) {
      setState(() {
        _selectedSymbol = newSymbol;
        _selectedName = widget.selectedName;
        _rankError = null;
      });

      // ✅ 투자게임 고정이므로 항상 로딩
      _loadRanking(newSymbol);
    }
  }




  // ✅ 즐겨찾기(사이드바) 열기: 콜백 있으면 콜백, 없으면 Drawer 시도, 둘 다 없으면 안내
  void _openFavoriteSidebar() {
    // 1) AppShell 콜백이 연결되어 있으면 그걸 사용
    final cb = widget.onToggleFavoriteSidebar;
    if (cb != null) {
      cb();
      return;
    }

    // 2) 혹시 Drawer를 쓰는 구조면 Drawer 열기 시도
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.hasDrawer) {
      scaffold.openDrawer();
      return;
    }

    // 3) 둘 다 아니면 안내
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('즐겨찾기 메뉴 연결이 안 되어 있습니다. (콜백 전달 필요)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onSelectedSymbol(String symbol, String name) async {
    setState(() {
      _selectedSymbol = symbol;
      _selectedName = name;
      _rankError = null;
    });

    // ✅ 투자게임 고정이므로 항상 로딩
    await _loadRanking(symbol);
  }


  void _onAddFavoritePressed() {
    final symbol = _selectedSymbol;
    final name = _selectedName;

    if (symbol == null || symbol.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('종목을 먼저 선택한 뒤 즐겨찾기에 추가하세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // ✅ 메인 페이지와 동일 포맷: "SYMBOL|NAME"
    widget.onAddFavorite?.call("$symbol|${name ?? symbol}");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('즐겨찾기에 추가했습니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadRanking(String symbol) async {
    setState(() {
      _loadingRank = true;
      _rankError = null;
      _rows = [];
    });

    try {
      final sym = symbol.trim().toUpperCase();
      if (sym.isEmpty) {
        throw Exception('symbol is empty');
      }

      final uri = Uri.parse('$_serverBaseUrl/game/ranking').replace(
        queryParameters: {
          'symbol': sym,
          'mode': 'game',
          'limit': '50',
        },
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('서버 오류: ${res.statusCode} ${res.body}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final List<dynamic> rows = (body['rows'] as List<dynamic>?) ?? [];

      final parsed = <_RankRow>[];
      for (final x in rows) {
        final m = Map<String, dynamic>.from(x as Map);
        parsed.add(
          _RankRow(
            rank: (m['rank'] as num?)?.toInt() ?? 0,
            uidRaw: (m['uid'] ?? '').toString().trim(),
            uidMasked: (m['uid_masked'] ?? '').toString(),
            nickname: (m['nickname'] ?? '').toString(),
            profit: (m['profit'] as num?)?.toDouble() ?? 0.0,
            profitRate: (m['profit_rate'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }

      // ✅ 중복 방지 + 순위 정렬 (UID 기준으로 1개만 남김)
      parsed.sort((a, b) => a.rank.compareTo(b.rank));
      final seen = <String>{};
      final unique = <_RankRow>[];
      for (final r in parsed) {
        final key = r.uidRaw;
        if (key.isEmpty) continue;
        if (seen.add(key)) unique.add(r);
      }

      setState(() {
        _rows = unique;
        _rankError = unique.isEmpty ? '랭킹 데이터가 없습니다.' : null;
      });
    } catch (e) {
      setState(() => _rankError = '랭킹 데이터를 불러오지 못했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingRank = false);
      }
    }
  }

  // ⭐ 플레이스토어 등록 후 이 링크만 교체하면 됨
  static const String _storeUrl = '[플레이스토어 링크]';

  // ⭐ 랭킹 공유
  Future<void> _shareRank(_RankRow r) async {
    final stockName = (_selectedName != null && _selectedName!.trim().isNotEmpty)
        ? _selectedName!.trim()
        : (_selectedSymbol ?? '').trim();

    final profitText =
    r.profit >= 0 ? '+${r.profit.toStringAsFixed(2)}' : r.profit.toStringAsFixed(2);

    final text = '''
${r.displayName}
$stockName
랭킹 ${r.rank}위
수익 $profitText

가상투자 기록
$_storeUrl
''';

    await Share.share(text);
  }




  Widget _buildBody() {
    // ✅ 종목 선택 전
    if (_selectedSymbol == null) {
      return const Center(
        child: Text(
          '검색 후 종목을 선택하세요.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // ✅ 로딩
    if (_loadingRank) {
      return const Center(child: Text('데이터 불러오는 중...'));
    }

    // ✅ 에러
    if (_rankError != null) {
      return Center(
        child: Text(
          _rankError!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    // ✅ 결과
    if (_rows.isEmpty) {
      return const Center(
        child: Text(
          '랭킹 데이터가 없습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _rows[i];

        return ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),

          leading: CircleAvatar(
            radius: 18,
            child: Text(
              '${r.rank}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), // S=14
            ),
          ),

          title: Text(
            r.displayName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), // M=16
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r.profit >= 0 ? '+${r.profit.toStringAsFixed(2)}' : r.profit.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 14, // M=16
                  fontWeight: FontWeight.w700,
                  color: r.profit >= 0 ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '내 성과 공유',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.share_outlined, size: 18),
                onPressed: () => _shareRank(r),
              ),
            ],
          ),

          onTap: () {
            if (_selectedSymbol == null || _selectedSymbol!.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('먼저 종목을 선택하세요.')),
              );
              return;
            }

            if (r.uidRaw.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('UID가 비어있어 조회할 수 없습니다.')),
              );
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TradeLogPage(
                  initialSymbol: _selectedSymbol!,
                  initialName: (_selectedName != null && _selectedName!.trim().isNotEmpty)
                      ? _selectedName!
                      : _selectedSymbol!,
                  currentPrice: null,
                  favorites: const [],
                  folders: const [],
                  overrideUid: r.uidRaw,
                  initialMode: TradeMode.game,
                ),
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

}

class _RankRow {
  final int rank;

  // ✅ 서버 조회용 raw uid
  final String uidRaw;

  // ✅ 화면 표시용 마스킹 uid
  final String uidMasked;

  // ✅ 닉네임(있으면 우선 표시)
  final String nickname;

  final double profit;
  final double profitRate;

  _RankRow({
    required this.rank,
    required this.uidRaw,
    required this.uidMasked,
    required this.nickname,
    required this.profit,
    required this.profitRate,
  });

  String get displayName {
    final n = nickname.trim();
    if (n.isNotEmpty) return n;

    final m = uidMasked.trim();
    if (m.isNotEmpty) return m;

    return uidRaw;
  }
}


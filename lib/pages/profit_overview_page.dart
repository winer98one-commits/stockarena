// 📄 lib/pages/profit_overview_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/profit_timeline_service.dart';

import '../widgets/trade_mode_toggle.dart';

import 'package:http/http.dart' as http;
import '../services/stocknote_server_api.dart';
import '../l10n/app_localizations.dart';
import '../utils/symbol_resolver.dart';



class ProfitOverviewPage extends StatefulWidget {
  // ✅ 종목 클릭 시 부모에게 알리는 콜백
  final void Function(String symbol, String name)? onSymbolTap;

  // ✅ 추가: AppShell에서 넘겨주는 현재 모드
  final TradeMode initialMode;

  // ✅ 추가: 이 페이지에서 모드가 바뀔 때 AppShell에 알려줄 콜백
  final ValueChanged<TradeMode>? onModeChanged;

  const ProfitOverviewPage({
    super.key,
    this.onSymbolTap,
    this.initialMode = TradeMode.log,   // 기본값: 매매일지
    this.onModeChanged,
  });

  @override
  State<ProfitOverviewPage> createState() => _ProfitOverviewPageState();
}


class _ProfitOverviewPageState extends State<ProfitOverviewPage> {
  bool _loading = true;

  double _totalInvest = 0;        // 초기 투자금
  double _totalProfit = 0;        // 총 수익금
  double _totalProfitRate = 0;    // 총 수익률 (%)
  double _currentEquity = 0;      // 현재 남은 금액(전체 자산)

  List<_SymbolSummary> _symbolSummaries = [];

  // ✅ 종목 수동 정렬 순서 저장용
  List<String> _manualSymbolOrder = [];

  // 수익 타임라인 데이터
  List<ProfitPoint> _timeline = [];

  // ✅ 상단 매매일지 / 투자 게임 토글 상태
  // ✅ 상단 매매일지 / 투자 게임 토글 상태
  late TradeMode _mode;

  // ✅ 종목 위치 변경 모드 ON/OFF
  bool _isReorderMode = false;

  final NumberFormat _currency =
  NumberFormat.currency(locale: 'en_US', symbol: r'$');


  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;  // ✅ AppShell에서 받은 모드로 시작
    _loadManualOrder().then((_) {
      _loadData();
    });
  }

  @override
  void didUpdateWidget(covariant ProfitOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ AppShell(TopBar)에서 모드가 바뀌면 여기로 들어옴
    if (oldWidget.initialMode != widget.initialMode) {
      setState(() {
        _mode = widget.initialMode;
        _loading = true;
      });
      _loadData();
    }
  }

  Future<void> _loadManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final key = (_mode == TradeMode.log)
        ? 'profit_manual_order_log'
        : 'profit_manual_order_game';

    _manualSymbolOrder = prefs.getStringList(key) ?? [];
  }

  Future<void> _saveManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final key = (_mode == TradeMode.log)
        ? 'profit_manual_order_log'
        : 'profit_manual_order_game';

    await prefs.setStringList(key, _manualSymbolOrder);
  }

  void _applyManualOrder(List<_SymbolSummary> summaries) {
    if (_manualSymbolOrder.isEmpty) return;

    final orderMap = <String, int>{};
    for (int i = 0; i < _manualSymbolOrder.length; i++) {
      orderMap[_manualSymbolOrder[i]] = i;
    }

    summaries.sort((a, b) {
      final ai = orderMap[a.symbol];
      final bi = orderMap[b.symbol];

      if (ai == null && bi == null) {
        return b.profitRate.compareTo(a.profitRate);
      }
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });

    // 새로 생긴 종목이 있으면 뒤에 자동 추가
    final currentSymbols = summaries.map((e) => e.symbol).toList();
    _manualSymbolOrder = [
      ..._manualSymbolOrder.where(currentSymbols.contains),
      ...currentSymbols.where((s) => !_manualSymbolOrder.contains(s)),
    ];
  }

  Future<void> _moveSymbolUp(int index) async {
    if (index <= 0) return;

    setState(() {
      final item = _symbolSummaries.removeAt(index);
      _symbolSummaries.insert(index - 1, item);
      _manualSymbolOrder = _symbolSummaries.map((e) => e.symbol).toList();
    });

    await _saveManualOrder();
  }

  Future<void> _moveSymbolDown(int index) async {
    if (index >= _symbolSummaries.length - 1) return;

    setState(() {
      final item = _symbolSummaries.removeAt(index);
      _symbolSummaries.insert(index + 1, item);
      _manualSymbolOrder = _symbolSummaries.map((e) => e.symbol).toList();
    });

    await _saveManualOrder();
  }


  // ======================
  //   데이터 로드 & 계산
  // ======================
  // ======================
  //   데이터 로드 (서버)
  // ======================
  Future<void> _loadData() async {
    debugPrint('🔥 ProfitOverview API CALL');
    final prefs = await SharedPreferences.getInstance();

    // ✅ 모드별 UID 분리
    final String uid = (_mode == TradeMode.log)
        ? (prefs.getString("uid") ?? "guest_local")
        : (prefs.getString("game_uid") ?? prefs.getString("uid") ?? "guest_local");

    final modeStr = (_mode == TradeMode.log) ? "log" : "game";
    debugPrint('🧩 ProfitOverview UID=$uid / mode=$modeStr');

    try {
      final uri = Uri.parse('${StocknoteServerApi.baseUrl}/profit/overview')
          .replace(queryParameters: {
        'uid': uid,
        'mode': modeStr,
      });
      debugPrint('🌐 ProfitOverview REQUEST = $uri');

      final res = await http.get(uri);
      debugPrint('📥 ProfitOverview RES = ${res.statusCode} / ${res.body}');

      if (res.statusCode != 200) {
        throw Exception('profit/overview 실패: ${res.statusCode} ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('profit/overview 응답 형식 오류: $decoded');
      }

      // ----------------------------
      // 공용 변환기
      // ----------------------------
      double toD(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      int toI(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? 0;
      }

      // ----------------------------
      // 1) 총 요약 값 (여러 키 허용)
      // ----------------------------
      final totalInvest = toD(decoded['total_invest'] ?? decoded['initial_invest'] ?? decoded['init_invest']);
      final totalProfit = toD(decoded['total_profit'] ?? decoded['pnl'] ?? decoded['total_pnl']);
      final totalProfitRate = toD(decoded['total_profit_rate'] ?? decoded['profit_rate'] ?? decoded['total_rate']);
      final currentEquity = toD(decoded['current_equity'] ?? decoded['equity'] ?? decoded['total_equity']);

      // ----------------------------
      // 2) 종목별 요약 리스트 (키/필드명 유연 처리)
      // ----------------------------
      final List<_SymbolSummary> summaries = [];

      dynamic rawSymbols =
          decoded['symbols'] ??
              decoded['symbol_summaries'] ??
              decoded['positions'] ??
              decoded['items'];

      // 서버가 { "AAPL.US": {...}, "TSLA.US": {...} } 형태로 주는 경우도 대응
      if (rawSymbols is Map) {
        rawSymbols = rawSymbols.entries.map((e) {
          final v = e.value;
          if (v is Map) {
            return <String, dynamic>{
              'symbol': e.key.toString(),
              ...v.map((k, vv) => MapEntry(k.toString(), vv)),
            };
          }
          return <String, dynamic>{'symbol': e.key.toString(), 'value': v};
        }).toList();
      }

      if (rawSymbols is List) {
        for (final e in rawSymbols) {
          if (e is! Map) continue;
          final m = e.map((k, v) => MapEntry(k.toString(), v));

          final symbol = (m['symbol'] ?? m['code'] ?? m['ticker'] ?? '').toString();
          if (symbol.isEmpty) continue;

          final rawName = (m['name'] ?? m['company_name'] ?? m['companyName'] ?? '').toString();
          final name = _resolveSymbolName(prefs, symbol, rawName);

          // ✅ invest 키 확장 + (없으면) avg_price*quantity 로 보정
          double invest = toD(
            m['invest'] ??
                m['invested'] ??
                m['total_invest'] ??
                m['position_invest'] ??
                m['opened_invest'] ??
                m['net_invest'] ??
                m['cost'] ??
                m['cost_basis'] ??
                m['total_buy'] ??
                m['buy_amount'] ??
                m['invest_amount'],
          );

          // avg_price/quantity 만 내려오는 경우 대응
          if (invest == 0.0) {
            final qty = toD(m['quantity'] ?? m['qty'] ?? m['position_qty']);
            final avg = toD(m['avg_price'] ?? m['avgPrice'] ?? m['average_price']);
            if (qty != 0.0 && avg != 0.0) {
              invest = qty * avg;
            }
          }

          // ✅ profit 키 확장 (서버마다 이름이 다름)
          // ✅ profit 계산 규칙:
          // 1) total_pnl / profit / pnl 같은 "합계"가 있으면 그걸 사용
          // 2) 없으면 eval_pnl + realized_pnl 합산 (둘 다 내려오는 케이스 대응)
          // 3) 그 외는 기존 후보 키들 순서대로
          double profit = 0.0;

          final totalPnlCandidate =
              m['total_pnl'] ??
                  m['total_profit'] ??
                  m['profit'] ??
                  m['pnl'] ??
                  m['profit_amount'] ??
                  m['sum_profit'];

          if (totalPnlCandidate != null) {
            profit = toD(totalPnlCandidate);
          } else {
            final evalPnl = toD(m['eval_pnl']);
            final realizedPnl = toD(m['realized_pnl'] ?? m['realized'] ?? m['realizedProfit']);

            // 둘 중 하나라도 있으면 합산
            if (m.containsKey('eval_pnl') || m.containsKey('realized_pnl') || m.containsKey('realized')) {
              profit = evalPnl + realizedPnl;
            }
          }


          // ✅ profitRate 키 확장
          final profitRate = toD(
            m['profit_rate'] ??
                m['profitRate'] ??
                m['rate'] ??
                m['total_profit_rate'] ??
                m['profit_pct'] ??
                m['profitPercent'] ??
                m['pct'],
          );


          final trades = toI(
            m['trades'] ??
                m['trade_count'] ??
                m['count'],
          );

          summaries.add(
            _SymbolSummary(
              symbol: symbol,
              name: name,
              invest: invest,
              profit: profit,
              profitRate: profitRate,
              trades: trades,
            ),
          );
        }
      }

      summaries.sort((a, b) => b.profitRate.compareTo(a.profitRate));
      _applyManualOrder(summaries);
      debugPrint('✅ ProfitOverview symbols parsed: ${summaries.length}');

      // ----------------------------
      // 3) 타임라인(차트용) 파싱 (기존 유지)
      // ----------------------------
      final List<ProfitPoint> timeline = [];
      final rawTimeline = decoded['timeline'];

      if (rawTimeline is List) {
        for (final e in rawTimeline) {
          if (e is! Map<String, dynamic>) continue;

          final dateStr = (e['date'] ?? '').toString();
          if (dateStr.isEmpty) continue;

          final totalEq = toD(e['total_equity']);

          final Map<String, double> symbolEquity = {};
          final se = e['symbol_equity'];
          if (se is Map) {
            for (final entry in se.entries) {
              final k = entry.key.toString();
              symbolEquity[k] = toD(entry.value);
            }
          }

          timeline.add(
            ProfitPoint(
              date: DateTime.parse(dateStr),
              totalEquity: totalEq,
              totalGrowth: 0.0,
              symbolEquity: symbolEquity,
              symbolGrowth: const {},
            ),
          );
        }
      }

      setState(() {
        _totalInvest = totalInvest;
        _totalProfit = totalProfit;
        _totalProfitRate = totalProfitRate;
        _currentEquity = currentEquity;

        _symbolSummaries = summaries;
        _timeline = timeline;

        _loading = false;
      });
    } catch (e) {
      setState(() {
        _totalInvest = 0;
        _totalProfit = 0;
        _totalProfitRate = 0;
        _currentEquity = 0;
        _symbolSummaries = [];
        _timeline = [];
        _loading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.profitLoadFail(e.toString()),
          ),
        ),
      );

    }
  }




  // ======================
  //   특정 종목 전체 삭제
  // ======================
  Future<void> _confirmDeleteSymbol(_SymbolSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('종목 삭제'),
        content: Text(
          '"${s.name}" 종목의 수익 요약과\n'
              '모든 매매 기록을 삭제합니다.\n\n'
              '계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteSymbolData(s.symbol);
    }
  }

  Future<void> _deleteSymbolData(String symbol) async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ 네 파일의 _loadData()와 동일한 UID 규칙 (중요)
    final String uid = (_mode == TradeMode.log)
        ? (prefs.getString("uid") ?? "guest_local")
        : (prefs.getString("game_uid") ?? prefs.getString("uid") ?? "guest_local");

    final modeStr = (_mode == TradeMode.log) ? "log" : "game";

    // -----------------------
    // 1) 투자게임: 서버 데이터 삭제
    // -----------------------
    if (_mode == TradeMode.game) {
      String _normSym(String s) {
        final v = s.trim().toUpperCase();
        final i = v.indexOf('.');
        return (i >= 0) ? v.substring(0, i) : v; // AAPL.US -> AAPL
      }

      final targetSym = _normSym(symbol);

      try {
        // 1) 거래 목록 조회
        final tradesUri = Uri.parse('${StocknoteServerApi.baseUrl}/game/trades')
            .replace(queryParameters: {
          'uid': uid,
          'mode': modeStr,   // "game"
          'limit': '5000',
        });

        final tradesRes = await http.get(tradesUri);
        if (tradesRes.statusCode != 200) {
          throw Exception('game/trades 실패: ${tradesRes.statusCode} ${tradesRes.body}');
        }

        final decoded = jsonDecode(tradesRes.body);

        // 서버 응답 형태 방어: { "trades": [...] } 또는 그냥 [...]
        final List<dynamic> trades = (decoded is List)
            ? decoded
            : (decoded is Map && decoded['trades'] is List)
            ? (decoded['trades'] as List)
            : <dynamic>[];

        // 2) 해당 종목의 trade_id만 수집
        final ids = <int>[];
        for (final t in trades) {
          if (t is! Map) continue;
          final tSymbol = (t['symbol'] ?? '').toString();
          if (_normSym(tSymbol) != targetSym) continue;

          final idVal = t['id'];
          final int? id = (idVal is int) ? idVal : int.tryParse(idVal.toString());
          if (id != null) ids.add(id);
        }

        if (ids.isEmpty) {
          await _loadData();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('서버에 "$symbol" 거래가 없습니다. 새로고침했습니다.')),
          );
          return;
        }

        // 3) id별 삭제
        int okCount = 0;
        for (final tradeId in ids) {
          final delUri = Uri.parse('${StocknoteServerApi.baseUrl}/game/trade/delete');
          final delRes = await http.post(
            delUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'trade_id': tradeId,
              'uid': uid,
              'mode': modeStr, // "game"
            }),
          );
          if (delRes.statusCode == 200) okCount++;
        }

        // 4) 새로고침
        await _loadData();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$symbol" 삭제 완료: $okCount / ${ids.length}건')),
        );
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
        return;
      }
    }

    // -----------------------
    // 2) 매매일지: 기존 로컬 삭제 유지
    // -----------------------
    final bool isLog = true;

    final String symbolsKey   = isLog ? 'summary_symbols'        : 'game_summary_symbols';
    final String investPrefix = isLog ? 'summary_invest_'        : 'game_summary_invest_';
    final String profitPrefix = isLog ? 'summary_profit_'        : 'game_summary_profit_';
    final String ratePrefix   = isLog ? 'summary_profit_rate_'   : 'game_summary_profit_rate_';
    final String tradesPrefix = isLog ? 'summary_trades_'        : 'game_summary_trades_';
    final String namePrefix   = isLog ? 'summary_name_'          : 'game_summary_name_';
    final String logKey       = isLog ? 'trade_logs'             : 'game_trade_logs';

    final symbols = prefs.getStringList(symbolsKey) ?? [];
    symbols.removeWhere((sym) => sym == symbol);
    await prefs.setStringList(symbolsKey, symbols);

    await prefs.remove('$investPrefix$symbol');
    await prefs.remove('$profitPrefix$symbol');
    await prefs.remove('$ratePrefix$symbol');
    await prefs.remove('$tradesPrefix$symbol');
    await prefs.remove('$namePrefix$symbol');

    final List<String> savedLogs = prefs.getStringList(logKey) ?? [];
    final List<String> updatedLogs = [];

    for (final raw in savedLogs) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if ((m['symbol'] ?? '') == symbol) continue;
        updatedLogs.add(raw);
      } catch (_) {
        updatedLogs.add(raw);
      }
    }
    await prefs.setStringList(logKey, updatedLogs);

    await _loadData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$symbol" 종목 데이터가 삭제되었습니다.')),
    );
  }


  // ======================
  //   포맷 / 색상 헬퍼
  // ======================
  String _fmtMoney(double v) =>
      NumberFormat('#,##0', 'en_US').format(v);

  String _fmtRate(double v) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(2)}%';
  }

  Color _profitColor(double v) {
    if (v > 0) return Colors.redAccent;
    if (v < 0) return Colors.blueAccent;
    return Colors.grey;
  }
  String _resolveSymbolName(SharedPreferences prefs, String symbol, String rawName) {
    String clean(String s) => s.trim();

    String normSym(String s) {
      final v = s.trim().toUpperCase();
      final i = v.indexOf('.');
      return (i >= 0) ? v.substring(0, i) : v; // AAPL.US -> AAPL
    }

    final sym = symbol.trim();
    final symUpper = sym.toUpperCase();
    final ns = normSym(sym);

    // 1) 서버가 name을 주면 그대로 사용 (+ 캐시 저장)
    final rn = clean(rawName);
    if (rn.isNotEmpty && rn.toUpperCase() != symUpper) {
      // 캐시(다음부터는 서버가 name 없어도 이름 표시)
      prefs.setString('symbol_name_$sym', rn);
      prefs.setString('symbol_name_$ns', rn);
      return rn;
    }

    // 2) 로컬 저장(prefs) 우선
    final savedExact = prefs.getString('symbol_name_$sym');
    if (savedExact != null && clean(savedExact).isNotEmpty) {
      return clean(savedExact);
    }

    final savedNorm = prefs.getString('symbol_name_$ns');
    if (savedNorm != null && clean(savedNorm).isNotEmpty) {
      return clean(savedNorm);
    }

    // 3) ✅ 로컬 종목맵(symbol_resolver)에서 “심볼로” 이름 찾기
    // searchLocalStocks()가 Map 리스트를 주는 구조라서 심볼 exact/정규화 둘 다 매칭
    try {
      final candidates = searchLocalStocks(ns);
      for (final r in candidates) {
        final rs = (r['symbol'] ?? '').toString().trim();
        final rn2 = (r['name'] ?? '').toString().trim();
        if (rn2.isEmpty) continue;

        final rsUpper = rs.toUpperCase();
        final rsNorm = normSym(rs);

        if (rsUpper == symUpper || rsNorm == ns) {
          // ✅ 찾았으면 캐시 저장
          prefs.setString('symbol_name_$sym', rn2);
          prefs.setString('symbol_name_$ns', rn2);
          return rn2;
        }
      }
    } catch (_) {
      // symbol_resolver가 없거나 예외여도 앱 죽지 않게 무시
    }

    // 4) 결국 없으면 symbol 폴백
    return sym;
  }

  // ✅ 추가: 차트와 같은 팔레트(ProfitTimelineChart와 동일 순서)
  static const List<Color> _palette = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.brown,
    Colors.teal,
  ];

  // ✅ 추가: 현재 리스트(_symbolSummaries) 순서 기준으로 심볼 색 결정
  Color _colorForSymbol(String symbol) {
    final idx = _symbolSummaries.indexWhere((s) => s.symbol == symbol);
    if (idx < 0) return Colors.grey;
    return _palette[idx % _palette.length];
  }


  // ======================
  //   빌드
  // ======================
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 8),

          // ✅ 정렬 모드 스위치 바
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  _mode == TradeMode.game ? '투자 게임 종목 정렬' : '매매일지 종목 정렬',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isReorderMode = !_isReorderMode;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isReorderMode ? Colors.black : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isReorderMode ? Icons.lock_open : Icons.swap_vert,
                          size: 16,
                          color: _isReorderMode ? Colors.white : Colors.black87,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isReorderMode ? '이동중' : '고정',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isReorderMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 종목 리스트
          Expanded(
            child: ListView.builder(
              itemCount: _symbolSummaries.length,
              itemBuilder: (context, index) {
                final s = _symbolSummaries[index];
                return _buildSymbolTile(s, index);
              },
            ),
          ),
        ],
      ),
    );
  }



// 총 수익 요약 카드 (한 줄)
// 총 수익 요약 (라인/그림자 없는 한 줄)
  Widget _buildTotalCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final t = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        // ✅ Card 제거: 그림자/테두리로 생기는 라인(수직/수평 느낌) 방지
        decoration: BoxDecoration(
          color: Colors.transparent, // 배경도 필요하면 Colors.white로 변경 가능
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text(
              t.totalProfitSummary,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),

            Expanded(
              child: isMobile
                  ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      '${t.initial} ${_fmtMoney(_totalInvest)}   ',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '${t.current} ${_fmtMoney(_currentEquity)}   ',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _fmtRate(_totalProfitRate),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _profitColor(_totalProfitRate),
                      ),
                    ),
                  ],
                ),
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${t.initial} ${_fmtMoney(_totalInvest)}   ',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${t.current} ${_fmtMoney(_currentEquity)}   ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _fmtRate(_totalProfitRate),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _profitColor(_totalProfitRate),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildSymbolTile(_SymbolSummary s, int index) {
    final symColor = _colorForSymbol(s.symbol);

    final displayName = (s.name.trim().isNotEmpty) ? s.name.trim() : s.symbol;

    final profitText = _fmtMoney(s.profit);
    final profitColor = _profitColor(s.profit);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        onTap: _isReorderMode
            ? null
            : () {
          if (widget.onSymbolTap != null) {
            widget.onSymbolTap!(s.symbol, s.name);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: symColor,
                child: Text(
                  displayName.isNotEmpty ? displayName[0] : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _isReorderMode ? Colors.grey.shade700 : Colors.black,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(width: 6),

              if (_isReorderMode) ...[
                Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 20,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.keyboard_arrow_up,
                          size: 18,
                          color: index == 0 ? Colors.grey.shade400 : Colors.black,
                        ),
                        onPressed: index == 0 ? null : () => _moveSymbolUp(index),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 20,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: index == _symbolSummaries.length - 1
                              ? Colors.grey.shade400
                              : Colors.black,
                        ),
                        onPressed: index == _symbolSummaries.length - 1
                            ? null
                            : () => _moveSymbolDown(index),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '수익 $profitText',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: profitColor,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '거래 ${s.trades}회',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


} // ✅ 이 줄 추가: _ProfitOverviewPageState 끝

// 심볼 한 개 요약 정보
class _SymbolSummary {
  final String symbol;
  final String name;
  final double invest;
  final double profit;
  final double profitRate;
  final int trades;

  _SymbolSummary({
    required this.symbol,
    required this.name,
    required this.invest,
    required this.profit,
    required this.profitRate,
    required this.trades,
  });
}

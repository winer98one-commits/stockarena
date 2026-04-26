// 📄 lib/pages/trade_log_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;          // ✅ 추가: 서버 호출용

import '../widgets/candle_chart.dart';

import '../pages/favorite_sidebar.dart';
import 'trade_log_summary.dart';
import '../widgets/trade_mode_toggle.dart';
import 'trade_debug_panel.dart';
import '../services/game_server_api.dart'; // ✅ 추가
import '../services/trade_calc_service.dart'; // ✅ 추가
import '../services/chart_cache_service.dart'; // ✅ 추가
import '../src/model/candle.dart'; // ✅ 추가
import 'package:firebase_auth/firebase_auth.dart';


class TradeLogPage extends StatefulWidget {
  final String initialSymbol;
  final String initialName;
  final double? currentPrice;
  final List<String> favorites;
  final List<String> folders;

  // ✅ 추가: 랭킹에서 클릭한 "타인 uid"로 조회할 때 사용
  final String? overrideUid;

  // ✅ [추가] AppShell 사이드바 열기 콜백
  final VoidCallback? onToggleFavoriteSidebar;

  // ✅ 새로 추가: 처음 열릴 때 모드
  final TradeMode initialMode;

  // ✅ 추가: 이 페이지에서 모드가 바뀔 때 AppShell에 알려줄 콜백
  final ValueChanged<TradeMode>? onModeChanged;

  const TradeLogPage({
    super.key,
    required this.initialSymbol,
    required this.initialName,
    this.currentPrice,
    required this.favorites,
    required this.folders,

    // ✅ 추가
    this.overrideUid,

    this.onToggleFavoriteSidebar, // ✅ [추가]
    this.initialMode = TradeMode.log, // 기본값: 매매일지
    this.onModeChanged,
  });

  @override
  State<TradeLogPage> createState() => _TradeLogPageState();
}


class _TradeLogPageState extends State<TradeLogPage> {
  String _selectedSymbol = '';
  String _selectedName = '';
  double? _currentPrice;
  double? _avgPrice;
  double? _profit;
  double? _profitRate;

  // ✅ 추가: 현재 화면이 조회 중인 UID(랭킹에서 클릭한 UID 포함)
  String? _activeUid;

  // ✅ 랭킹에서 넘어온 타인 UID 조회는 읽기 전용
  bool get _isReadOnlyOtherUid {
    final forced = widget.overrideUid;
    return forced != null && forced.trim().isNotEmpty;
  }

  List<Map<String, dynamic>> _logs = [];
  List<Candle> _candles = []; // ✅ 차트 데이터
  bool _chartLoading = false; // ✅ 차트 로딩 상태



  // ✅ 현재 모드 (매매일지 / 투자 게임)
  late TradeMode _mode;   // 🔹 late 로 변경

  // ✅ 서버 관련 설정 & 상태 (종목 요약)
  static const String _serverBaseUrl = "https://api.stockarena.co.kr";
  Map<String, dynamic>? _serverSymbolSummary;   // 서버에서 받은 종목 요약
  bool _serverSummaryLoading = false;           // 로딩 중 표시
  String? _serverSummaryError;                 // 에러 메시지 저장

  // 테스트용 UID (나중에 로그인 UID로 교체)
  String? _uid;

  Future<void> _clearLocalTradeLogsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('cleared_local_trade_logs_once') ?? false;
    if (done) return;

    await prefs.remove('trade_logs');
    await prefs.remove('game_trade_logs');

    await prefs.setBool('cleared_local_trade_logs_once', true);

    debugPrint('[CLEAR LOCAL] trade_logs / game_trade_logs removed once');
  }


  @override
  void didUpdateWidget(covariant TradeLogPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ AppShell(TopBar)에서 모드가 바뀌면 TradeLogPage 로컬 모드도 동기화
    if (widget.initialMode != oldWidget.initialMode) {
      setState(() {
        _mode = widget.initialMode;

        _currentPrice = null;
        _avgPrice = null;
        _profit = null;
        _profitRate = null;
        _logs = [];

        // 모드 바뀌면 서버 요약도 리셋
        _serverSymbolSummary = null;
        _serverSummaryError = null;
        _serverSummaryLoading = false;
      });

      // ✅ 모드 바뀐 직후 로그 다시 로드
      Future.microtask(() async {
        if (!mounted) return;
        await _loadLogs();
      });
    }

    // ✅ 선택 종목이 바뀌면(즐겨찾기/검색/탑바 선택 등) 페이지도 동기화
    if (widget.initialSymbol != oldWidget.initialSymbol ||
        widget.initialName != oldWidget.initialName) {
      setState(() {
        _selectedSymbol = widget.initialSymbol;
        _selectedName = widget.initialName;
        _candles = [];
      });

      Future.microtask(() async {
        if (!mounted) return;
        await _loadChart();
        await _loadLogs();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedSymbol = widget.initialSymbol;
    _selectedName = widget.initialName;
    _currentPrice = widget.currentPrice;
    _clearLocalTradeLogsOnce();

    // ✅ 페이지가 열릴 때 전달받은 initialMode 로 설정
    _mode = widget.initialMode;

    _loadChart();  // ✅ 차트 먼저 로드
    _loadLogs();   // ✅ 로그 로드
  }

  // 숫자 변환 헬퍼 (서버 값 double로)
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _normalizeSymbolForServer(String rawSymbol) {
    final s = rawSymbol.trim().toUpperCase();
    if (s.isEmpty) return s;

    if (s.contains('.')) return s;
    if (s.contains('-USD')) return '$s.CC';

    return '$s.US';
  }

  Future<String> _resolveUidForMode() async {
    // ✅ 1) 랭킹에서 넘어온 uid가 있으면 최우선 (타인 조회)
    final forced = widget.overrideUid;
    if (forced != null && forced.trim().isNotEmpty) {
      return forced.trim();
    }

    // ✅ 2) Firebase 로그인 uid가 있으면 최우선 (앱 재시작 시 prefs가 오래된 값일 수 있음)
    final fbUser = FirebaseAuth.instance.currentUser;
    final fbUid = (fbUser?.uid ?? '').trim();
    if (fbUid.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      // prefs 키들도 같이 최신화
      await prefs.setString('uid', fbUid);
      await prefs.setString('game_uid', fbUid);
      await prefs.setString('log_uid', fbUid);
      return fbUid;
    }

    // ✅ 3) 마지막으로 prefs 기반 (기존 규칙 유지)
    final prefs = await SharedPreferences.getInstance();
    final u = (prefs.getString('uid') ?? '').trim();
    final gu = (prefs.getString('game_uid') ?? '').trim();

    if (_mode == TradeMode.log) {
      return u.isNotEmpty ? u : gu;
    }
    return gu.isNotEmpty ? gu : u;
  }


  Future<void> _loadChart() async {
    if (_selectedSymbol.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _candles = [];
        _chartLoading = false;
      });
      return;
    }

    setState(() {
      _chartLoading = true;
    });

    try {
      final symbolForServer = _normalizeSymbolForServer(_selectedSymbol);

      final candles = await ChartCacheService.getChart(
        symbolRaw: symbolForServer,
        period: '1y',
      );

      if (!mounted) return;
      setState(() {
        _candles = candles;
        _chartLoading = false;
      });
    } catch (e) {
      debugPrint('❌ TradeLogPage 차트 로드 실패: $e');

      if (!mounted) return;
      setState(() {
        _candles = [];
        _chartLoading = false;
      });
    }
  }

  // =====================================================
  // ✅ 서버에서 개별 종목 요약 불러오기
  // =====================================================
  Future<void> _loadServerSymbolSummary() async {
    // 투자 게임 모드일 때만 서버 요약 사용 (log 모드는 일단 무시)
    if (_mode != TradeMode.game) {
      setState(() {
        _serverSymbolSummary = null;
        _serverSummaryError = null;
        _serverSummaryLoading = false;
      });
      return;
    }

    if (_selectedSymbol.isEmpty) return;

    setState(() {
      _serverSummaryLoading = true;
      _serverSummaryError = null;
      _serverSymbolSummary = null;
    });

    try {
      // ✅ 서버는 mode=log|game 만 허용 → 투자게임은 game
      final uid = await _resolveUidForMode();


// ✅ 서버는 mode=log|game 만 허용 → 투자게임은 game
      final uri = Uri.parse(
        '$_serverBaseUrl/game/symbol_summary'
            '?uid=$uid&symbol=$_selectedSymbol&mode=game',
      );


      final res = await http.get(uri);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        setState(() {
          _serverSymbolSummary = data;
          _serverSummaryLoading = false;
        });
      } else {
        setState(() {
          _serverSummaryLoading = false;
          _serverSummaryError =
          "서버 오류: ${res.statusCode} ${res.body.toString()}";
        });
      }
    } catch (e) {
      setState(() {
        _serverSummaryLoading = false;
        _serverSummaryError = "예외: $e";
      });
    }
  }


// =====================================================
// ✅ 서버 종목 요약 (총손익만 표시, 테두리 없음)
// =====================================================
  Widget _buildServerSummaryCard() {
    if (_serverSummaryLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8, right: 16, bottom: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            "총손익 불러오는 중...",
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (_serverSymbolSummary == null) {
      return const SizedBox.shrink();
    }

    final totalPnl = _serverSymbolSummary!['total_pnl'];

    if (totalPnl == null) {
      return const SizedBox.shrink();
    }

    final double pnl = (totalPnl as num).toDouble();
    final bool isPositive = pnl >= 0;

    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        right: 18,
        bottom: 12,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "총손익 ",
              style: TextStyle(
                fontSize: 18, // ✅ 기존 16 -> 18
                color: Colors.black54,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            Text(
              pnl.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 22, // ✅ 숫자 강조
                fontWeight: FontWeight.w900,
                color: isPositive ? Colors.red : Colors.blue,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }





  // =====================================================
  //  로그 로딩
  // =====================================================
  _loadLogs() async {
    final String serverMode = (_mode == TradeMode.game) ? 'game' : 'log';

    // ✅ 랭킹 uid 우선 적용 + 기존 규칙 유지
    final String uid = (await _resolveUidForMode()).trim();

    // ✅ 구매내역이 없어도 "연결된 UID"가 화면에 보이도록 저장
    setState(() {
      _activeUid = uid.isNotEmpty ? uid : null;
    });

    if (uid.isEmpty) {
      setState(() {
        _logs = [];
        _serverSummaryError = 'uid가 없습니다. (로그인/등록 필요)';
      });
      return;
    }

    try {
      final uri = Uri.parse('$_serverBaseUrl/game/trades').replace(
        queryParameters: {
          'uid': uid,
          'mode': serverMode, // ✅ log/game
          'limit': '200',
        },
      );

      final res = await http.get(uri);

      if (res.statusCode != 200) {
        throw Exception('서버 오류: ${res.statusCode} ${res.body}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final List<dynamic> trades = (body['trades'] as List<dynamic>?) ?? [];

      final List<Map<String, dynamic>> parsed = [];

      for (final t in trades) {
        final m = Map<String, dynamic>.from(t as Map);

        if ((m['symbol']?.toString() ?? '') != _selectedSymbol) continue;

        final side = (m['side']?.toString() ?? '').toUpperCase();
        final qty = (m['quantity'] as num?)?.toInt() ?? 0;
        final price = (m['price'] as num?)?.toDouble() ?? 0.0;
        final date = (m['trade_date']?.toString() ?? '').trim();

        final int tradeId = (m['id'] as num?)?.toInt() ?? -1;

        parsed.add({
          'trade_id': tradeId, // ✅ 서버 메모 수정에 필요
          'mode': serverMode,  // ✅ 추가: 이 거래가 log인지 game인지 표시
          'symbol': _selectedSymbol,
          'date': date, // ✅ TradeCalcService 정렬 키
          'type': side == 'BUY' ? '매수' : '매도',
          'qty': qty,
          'price': price,
          'memo': m['memo']?.toString() ?? '',
        });

      }

      // backupPrice: 최신 거래의 price(현재가 없을 때 대체)
      double? backupPrice;
      if (parsed.isNotEmpty) {
        parsed.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
        final p = parsed.first['price'];
        if (p is num) backupPrice = p.toDouble();
      }

      if (_currentPrice == null || _currentPrice == 0) {
        _currentPrice = backupPrice ?? 0;
      }

      // ✅ 거래별 평단/수익/수익률/잔고를 "앱에서" 계산
      final calc = TradeCalcService.calculate(parsed, _currentPrice);

      // ✅ UI는 최신 거래가 위로 보이게 다시 정렬(내림차순)
      final logsForUi = List<Map<String, dynamic>>.from(calc.logs);
      logsForUi.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));

      setState(() {
        _logs = logsForUi; // ✅ 이제 여기엔 avgPriceAtTrade/profitAtTrade/... 들어있음
        _serverSummaryError = null;
      });

      await _loadServerSymbolSummary();
    } catch (e) {
      setState(() {
        _logs = [];
        _serverSummaryError = '거래내역 서버 조회 실패: $e';
      });
    }
  }




  void _onFavoriteSelected(String symbol, String name) {
    setState(() {
      _selectedSymbol = symbol;
      _selectedName = name;

      // ✅ 종목이 바뀌면 기준 가격/요약값/로그 모두 초기화
      _currentPrice = null;
      _avgPrice = null;
      _profit = null;
      _profitRate = null;
      _logs = [];
      _candles = [];

      // 서버 요약도 초기화
      _serverSymbolSummary = null;
      _serverSummaryError = null;
      _serverSummaryLoading = false;
    });

    _loadChart(); // ✅ 새 심볼 차트 다시 읽기
    _loadLogs();  // ✅ 새 심볼 로그 다시 읽기
  }

  // =====================================================
  // ✅ 개별 매매 기록 삭제 확인 + 실제 삭제 함수
  // =====================================================
  Future<void> _confirmDeleteLog(Map<String, dynamic> log) async {
    // ✅ game 거래는 삭제 불가
    final mode = (log['mode'] ?? '').toString();
    if (mode != 'log') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('투자게임 거래는 삭제할 수 없습니다.')),
        );
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('매매 기록 삭제'),
        content: Text(
          '${log['date'] ?? ''}  '
              '${log['type'] ?? ''} ${log['qty'] ?? ''}주  '
              '가격 ${log['price'] ?? ''}\n\n'
              '이 매매 기록을 삭제할까요?',
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

    if (result == true) {
      await _deleteLog(log);
    }
  }


  Future<void> _deleteLog(Map<String, dynamic> target) async {
    // ✅ game 거래는 삭제 불가 (안전장치)
    final mode = (target['mode'] ?? '').toString();
    if (mode != 'log') return;

    // ✅ 서버 삭제는 trade_id 필요
    final int tradeId = (target['trade_id'] as num?)?.toInt() ?? -1;
    if (tradeId <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패: trade_id 없음 (서버 데이터 id 필요)')),
        );
      }
      return;
    }

    final String uid = (await _resolveUidForMode()).trim();


    if (uid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패: UID 없음')),
        );
      }
      return;
    }

    try {
      debugPrint('[DELETE SIGNAL] trade_id=$tradeId uid=$uid mode=log');

      await GameServerApi.deleteTrade(
        tradeId: tradeId,
        uid: uid,
        mode: 'log',
      );

      debugPrint('[DELETE OK] trade_id=$tradeId');

      await _loadLogs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('매매 기록이 삭제되었습니다.')),
        );
      }
    } catch (e) {
      // ✅ Flutter Web에서 "Failed to fetch"로 예외가 떠도
      //    서버에서 이미 삭제됐을 수 있으니, 재조회로 실제 삭제 여부 확인
      debugPrint('[DELETE EXCEPTION] $e');

      await _loadLogs();

      final bool stillExists = _logs.any((x) {
        final id = (x['trade_id'] as num?)?.toInt() ?? -1;
        return id == tradeId;
      });

      if (!stillExists) {
        // ✅ 실제로 삭제됨 → 성공 처리
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('매매 기록이 삭제되었습니다.')),
          );
        }
        return;
      }

      // ❌ 재조회 후에도 남아있으면 진짜 실패
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }




  // =====================================================
  // ✅ 매매 내용(메모) 수정 기능
  // =====================================================
  Future<void> _editMemo(Map<String, dynamic> target) async {
    // ✅ 타인 UID 조회는 수정 불가
    if (_isReadOnlyOtherUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('다른 아이디 조회 중에는 수정할 수 없습니다.')),
        );
      }
      return;
    }

    final TextEditingController controller =
    TextEditingController(text: target['memo'] ?? '');

    final String? newMemo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('매매 내용 수정'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '매매 내용을 입력하세요',
          ),
        ),
        actions: [
          TextButton(
            child: const Text('취소'),
            onPressed: () => Navigator.pop(context, null),
          ),
          TextButton(
            child: const Text('저장'),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
      ),
    );

    if (newMemo == null) return;

    // ✅ trade_id 필요 (서버 update_memo용)
    final int tradeId = (target['trade_id'] as num?)?.toInt() ?? -1;
    if (tradeId <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메모 수정 실패: trade_id 없음 (서버 데이터에 id가 필요)')),
        );
      }
      return;
    }

    final String serverMode = (_mode == TradeMode.game) ? 'game' : 'log';
    final String uid = (await _resolveUidForMode()).trim();


    if (uid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메모 수정 실패: UID 없음')),
        );
      }
      return;
    }

    try {
      await GameServerApi.updateTradeMemo(
        tradeId: tradeId,
        uid: uid,
        mode: serverMode,
        memo: newMemo.isEmpty ? null : newMemo,
      );

      // ✅ 서버에서 다시 불러와 화면 갱신
      await _loadLogs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('매매 내용이 수정되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 수정 실패: $e')),
        );
      }
    }
  }


  // =====================================================
  //  build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: KeyedSubtree(
        key: ValueKey('trade_body_${_mode.name}_$_selectedSymbol'),
        child: Column(
          children: [
            // 🔹 상단 차트
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    _chartLoading
                        ? const Center(child: CircularProgressIndicator())
                        : CandleChart(
                      key: ValueKey(_selectedSymbol),
                      symbol: _selectedSymbol,
                      candles: _candles,
                      tradeLogs: _logs,
                    ),

                    // 🔹 종목명
                    Positioned(
                      top: 8,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _selectedName.isNotEmpty
                              ? _selectedName
                              : _selectedSymbol,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),

                    // ✅ (삭제) 즐겨찾기 버튼
                  ],
                ),
              ),
            ),

            // 🔹 통계 요약 (클라이언트 계산)
            TradeLogSummary(
              mode: _mode,
              logs: _logs,
              currentPrice: _currentPrice,
              onCalculated: (avg, profit, rate) {
                setState(() {
                  _avgPrice = avg;
                  _profit = profit;
                  _profitRate = rate;
                });
              },
            ),




// 🔹 하단 내역 + 디버그 패널
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(thickness: 1.2),
                    _buildLogList(),
                    const SizedBox(height: 8),

                    // ✅ (삭제) TradeDebugPanel 표시 제거
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }


  Widget _buildLogList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_logs.isEmpty)
          const Text(
            '📭 이 종목의 매매일지가 없습니다.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          )
        else ...[
          _buildTradeValueHeaderCard(),
          const SizedBox(height: 4), // ✅ 6 -> 4

          Column(
            children: [
              for (final log in _logs) ...[
                _buildTradeLogCard(log),
                const SizedBox(height: 4), // ✅ 6 -> 4
              ],
            ],
          ),
        ],
      ],
    );
  }
  Widget _buildTradeLogCard(Map<String, dynamic> log) {
    const double fsDate = 14;    // 날짜
    const double fsAction = 11;  // 매수/매도
    const double fsValue = 11;   // 잔고/매매가/평단가/수익
    const double fsProfit = 14;  // 수익
    const double fsMemo = 12;

    final String type = (log['type'] ?? '').toString();
    final bool isBuy = type == '매수';

    final String date = (log['date'] ?? '').toString();
    final int qty = (log['qty'] as num?)?.toInt() ?? 0;

    final double price = (log['price'] as num?)?.toDouble() ?? 0.0;
    final double avg = (log['avgPriceAtTrade'] as num?)?.toDouble() ?? 0.0;
    final double profit = (log['profitAtTrade'] as num?)?.toDouble() ?? 0.0;
    final double curQty = (log['currentQty'] as num?)?.toDouble() ?? 0.0;

    final String memo = (log['memo'] ?? '').toString().trim();
    final String shownMemo = memo.isEmpty ? '-' : memo;

    final Color actionColor = isBuy ? Colors.red : Colors.blue;
    final Color profitColor = profit >= 0 ? Colors.redAccent : Colors.blueAccent;

    return InkWell(
      onTap: _isReadOnlyOtherUid ? null : () => _editMemo(log),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E8EE), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // [왼쪽 1열] 날짜
                  Expanded(
                    flex: 14,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        date,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontSize: fsDate,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),

                  // [가운데 2열] 매매가 / 평단가  ← 위치 변경
                  Expanded(
                    flex: 16,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          price.toStringAsFixed(2),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: fsValue,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          avg.toStringAsFixed(2),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: fsValue,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // [가운데 3열] 매매 / 잔고  ← 위치 변경
                  Expanded(
                    flex: 16,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$type ${qty}주',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: fsAction,
                            fontWeight: FontWeight.w800,
                            color: actionColor,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          curQty.toStringAsFixed(0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: fsValue,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // [오른쪽 4열] 수익
                  Expanded(
                    flex: 10,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        profit.toStringAsFixed(0),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: fsProfit,
                          fontWeight: FontWeight.w900,
                          color: profitColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '메모: $shownMemo',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: fsMemo,
                      color: Colors.black54,
                      height: 1.1,
                    ),
                  ),
                ),

                if (_mode == TradeMode.log)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _confirmDeleteLog(log),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _vDivider() {
    return Container(
      width: 1,
      height: 20, // ✅ 22 -> 20
      margin: const EdgeInsets.symmetric(horizontal: 8), // ✅ 10 -> 8
      color: const Color(0xFFE9ECF2),
    );
  }
  Widget _buildTradeValueHeaderCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EE), width: 1),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // [왼쪽 1열] 날짜
            Expanded(
              flex: 14,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '날짜',
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),

            // [가운데 2열] 매매가 / 평단가  ← 위치 변경
            Expanded(
              flex: 7,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    '매매가',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '평단가',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),

            // [가운데 3열] 매매 / 잔고  ← 위치 변경
            Expanded(
              flex: 12,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    '매매',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '잔고',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),

            // [오른쪽 4열] 수익
            Expanded(
              flex: 8,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '수익',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerLabelOnly(String label) {
    return Center(
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12, // ✅ 12 -> 13
          color: Colors.black54,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
  Widget _valueOnly(String value, {Color? color, double fontSize = 14}) {
    return Center(
      child: Text(
        value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: color ?? Colors.black87,
          height: 1.0,
        ),
      ),
    );
  }


}

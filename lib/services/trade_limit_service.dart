// 📄 lib/services/trade_limit_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'trade_calc_service.dart';
import '../widgets/trade_mode_toggle.dart';

/// ⭐ 추가: 시장 종류 구분용
enum MarketType {
  usStock, // 미국 주식
  krStock, // 한국 주식
  usFutures, // 미국 선물 (예: ES=F, NQ=F 등)
  crypto, // 코인 (BTC-USD, ETHUSDT 등)
  forex, // FX (EURUSD 등 6자리 통화쌍)
}

/// 투자 한도 체크 결과
class TradeLimitResult {
  final bool ok; // true면 저장 가능, false면 투자금 초과
  final double equity; // 현재 자본(초기 투자금 + 실현/평가 손익)
  final double usedAmount; // 총 사용 금액 (총 매수금 기준)

  TradeLimitResult({
    required this.ok,
    required this.equity,
    required this.usedAmount,
  });
}


/// 날짜 기준 포트폴리오에서 한 종목의 상태
class DateSymbolPosition {
  final String symbol;      // 심볼
  final String name;        // 종목 이름
  final double qty;         // 보유 수량(양수 = 롱, 음수 = 공매도)
  final double amount;      // 평가 금액 (투자금 + 손익)
  final double profitRate;  // 수익률 %
  final double weight;      // 전체 보유금액 대비 비중 %

  DateSymbolPosition({
    required this.symbol,
    required this.name,
    required this.qty,
    required this.amount,
    required this.profitRate,
    required this.weight,
  });
}

/// 날짜 기준 상태 결과 (현재 종목 + 전체 포트폴리오)
class DateStatusResult {
  final double qty;          // 현재 선택된 종목 잔고 수량
  final double avgPrice;     // 현재 선택된 종목 평단
  final double profitRate;   // 현재 선택된 종목 수익률
  final double available;    // 전체 포트폴리오 기준 매수 가능 금액
  final List<DateSymbolPosition> positions; // 전체 보유 종목 리스트

  // ✅ 포트폴리오 전체 기준
  final double totalAmount;      // 전체 자산 평가금액(초기투자+전체손익)
  final double totalProfitRate;  // 전체 수익률(전체 자산 / 초기투자 - 1)

  DateStatusResult({
    required this.qty,
    required this.avgPrice,
    required this.profitRate,
    required this.available,
    required this.positions,
    required this.totalAmount,
    required this.totalProfitRate,
  });
}

class TradeLimitService {
  // 실제 계좌용
  static const String _investKey = 'invest_amount';
  static const String _logsKey = 'trade_logs';

  // 투자 게임용
  static const String _gameInvestKey = 'game_invest_amount';
  static const String _gameLogsKey = 'game_trade_logs';

  // ─────────────────────────────────
  // ⭐ 추가: 심볼 → 시장 타입 자동 판별
  // ─────────────────────────────────
  static MarketType detectMarket(String symbol) {
    String s = symbol.toUpperCase();

    // 한국 주식 (.KS, .KQ, .KR 등)
    if (s.endsWith('.KS') || s.endsWith('.KQ') || s.endsWith('.KR')) {
      return MarketType.krStock;
    }

    // 미국 선물 (예: ES=F, NQ=F, YM=F)
    if (s.endsWith('=F')) {
      return MarketType.usFutures;
    }

    // 코인 (BTC-USD, ETH-USD, BTCUSDT, ETHUSDT 등)
    if (s.contains('-') || s.endsWith('USDT') || s.endsWith('USD')) {
      return MarketType.crypto;
    }

    // FX (EURUSD, USDJPY 등 알파벳 6자리)
    final fx = RegExp(r'^[A-Z]{6}$');
    if (fx.hasMatch(s)) {
      return MarketType.forex;
    }

    // 기본값: 미국 주식
    return MarketType.usStock;
  }

  // ─────────────────────────────────
  // ⭐ 추가: 시장별 거래시간 체크 (UTC 기준 now)
  // ─────────────────────────────────
  static bool _isTradableByTime(MarketType market, DateTime nowUtc) {
    // 여기서는 간단히 기기 local 시간 기준으로 판단
    final local = nowUtc.toLocal();
    final t = local.hour + local.minute / 60.0;

    switch (market) {
      case MarketType.usStock:
      // 미국 주식: 09:30 ~ 16:00 (현지 시간 가정)
        return t >= 9.5 && t <= 16.0;

      case MarketType.krStock:
      // 한국 주식: 09:00 ~ 15:30
        return t >= 9.0 && t <= 15.5;

      case MarketType.usFutures:
      // CME 선물: 24시간, 단 17:00 ~ 18:00 휴장
        if (t >= 17.0 && t < 18.0) return false;
        return true;

      case MarketType.crypto:
      // 코인: 24시간 365일
        return true;

      case MarketType.forex:
      // FX: 주말만 휴장 (토/일)
        if (local.weekday == DateTime.saturday ||
            local.weekday == DateTime.sunday) {
          return false;
        }
        return true;
    }
  }

  /// ⭐ 외부에서 쉽게 쓰는 헬퍼
  ///   - nowUtc 생략하면 현재 시간 자동 사용
  static bool isTradingTimeForSymbol(String symbol, {DateTime? nowUtc}) {
    final m = detectMarket(symbol);
    final t = nowUtc ?? DateTime.now().toUtc();
    return _isTradableByTime(m, t);
  }

  /// 🔥 TradeLogForm 에서 저장 전에 투자 한도 체크
  static Future<TradeLimitResult> checkWithProfit({
    required TradeMode mode,
    required String symbol,
    required String dateStr,
    required String type,
    required double price,
    required double qty,
    required double? currentPrice,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) 기준 투자금 (모드별 키 선택)
    final investKey =
    mode == TradeMode.log ? _investKey : _gameInvestKey;
    final double baseInvest = prefs.getDouble(investKey) ?? 0.0;


    // 투자금을 설정하지 않았으면 한도 체크는 건너뜀
    if (baseInvest <= 0) {
      return TradeLimitResult(ok: true, equity: 0, usedAmount: 0);
    }

    // 2) 기존 로그 중 해당 심볼만 (모드별 키 선택)
    final logsKey =
    mode == TradeMode.log ? _logsKey : _gameLogsKey;
    final List<String> saved = prefs.getStringList(logsKey) ?? [];

    final List<Map<String, dynamic>> symbolLogs = [];

    for (final raw in saved) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['symbol'] == symbol) {
          symbolLogs.add(Map<String, dynamic>.from(map));
        }
      } catch (_) {
        // 파싱 실패는 무시
      }
    }

    // 3) 이번에 저장하려는 거래까지 포함해서 시뮬레이션
    symbolLogs.add({
      'symbol': symbol,
      'date': dateStr,
      'type': type,
      'price': price,
      'qty': qty,
    });

    // 4) 공통 계산 로직 사용
    final calcResult = TradeCalcService.calculate(symbolLogs, currentPrice);

    final double usedAmount = calcResult.totalInvested; // 총 매수금
    final double equity = baseInvest + calcResult.totalProfit; // 현재 자본

    final bool ok = usedAmount <= equity;

    return TradeLimitResult(
      ok: ok,
      equity: equity,
      usedAmount: usedAmount,
    );
  }

  /// 📅 해당 날짜 기준 포트폴리오 상태
  static Future<DateStatusResult> statusForDate({
    required TradeMode mode,
    required String symbol,
    required String dateStr,       // 'YYYY-M-D' 형식 들어와도 처리
    required double? currentPrice, // 선택된 종목 현재가
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 모드별로 다른 초기 투자금 / 로그 사용
    final investKey =
    mode == TradeMode.log ? _investKey : _gameInvestKey;
    final logsKey =
    mode == TradeMode.log ? _logsKey : _gameLogsKey;

    final double baseInvest = prefs.getDouble(investKey) ?? 0.0;
    final List<String> saved = prefs.getStringList(logsKey) ?? [];


    // 모든 로그 파싱
    final List<Map<String, dynamic>> allLogs = [];
    for (final raw in saved) {
      try {
        allLogs.add(Map<String, dynamic>.from(jsonDecode(raw)));
      } catch (_) {}
    }

    DateTime _parseDate(String raw) {
      final cleaned = raw.trim().replaceAll(RegExp(r'[./\\]'), '-');
      final parts = cleaned.split('-');
      if (parts.length != 3) return DateTime(2000, 1, 1);
      final y = int.tryParse(parts[0]) ?? 2000;
      final m = int.tryParse(parts[1]) ?? 1;
      final d = int.tryParse(parts[2]) ?? 1;
      return DateTime(y, m, d);
    }

    final DateTime selectedDate = _parseDate(dateStr);

    // 🔹 날짜 기준으로 심볼별 로그 그룹화
    final Map<String, List<Map<String, dynamic>>> bySymbol = {};
    for (final log in allLogs) {
      final String sym = (log['symbol'] ?? 'N/A').toString();
      final String dateRaw = (log['date'] ?? '').toString();
      final DateTime d = _parseDate(dateRaw);

      if (d.isAfter(selectedDate)) continue; // 선택 날짜 이후 거래는 제외

      bySymbol.putIfAbsent(sym, () => []);
      bySymbol[sym]!.add(log);
    }

    double totalProfitAll = 0.0;      // 전체 손익 (실현+평가)
    double totalInvestAll = 0.0;      // 전체 투자금(모든 종목 총 매수금)
    double investedAmountAll = 0.0;   // 보유 종목들의 평가금액 합 (현금 제외)

    double mainQty = 0.0;
    double mainAvg = 0.0;
    double mainProfitRate = 0.0;

    final List<DateSymbolPosition> positions = [];

    // 🔹 심볼별로 공통 계산 로직 재사용
    for (final entry in bySymbol.entries) {
      final sym = entry.key;
      final logs = entry.value;

      // 선택된 심볼만 현재가 사용, 나머지는 TradeCalcService 기본 로직
      final calc = TradeCalcService.calculate(
        logs,
        sym == symbol ? currentPrice : null,
      );

      final double qtySym =
      calc.buyQty > 0 ? calc.buyQty : -calc.sellQty; // 롱/숏 모두 대응
      final double avgPriceSym =
      calc.buyQty > 0 ? calc.avgBuy : calc.avgSell;
      final double investSym = calc.totalInvested;
      final double profitSym = calc.totalProfit;

      totalProfitAll += profitSym;
      totalInvestAll += investSym;

      // ✅ 이 종목의 "평가금액 = 투자금 + 손익"
      final double amountSym = investSym + profitSym;

      // 보유 수량이 있고, 평가금액이 의미 있을 때만 리스트에 추가
      if (qtySym.abs() > 0.0001 || amountSym.abs() > 0.0001) {
        investedAmountAll += amountSym;

        final double rateSym =
        investSym > 0 ? (profitSym / investSym) * 100.0 : 0.0;

        // 이름은 최신 로그에서 name/companyName 우선 사용
        final lastLog = logs.last;
        final String name =
        (lastLog['name'] ??
            lastLog['companyName'] ??
            sym)
            .toString();

        positions.add(
          DateSymbolPosition(
            symbol: sym,
            name: name,
            qty: qtySym,
            amount: amountSym,
            profitRate: rateSym,
            weight: 0, // 나중에 비중 다시 채움
          ),
        );
      }

      // 선택된 종목의 요약 값
      if (sym == symbol) {
        mainQty = qtySym;
        mainAvg = avgPriceSym;
        mainProfitRate =
        investSym > 0 ? (profitSym / investSym) * 100.0 : 0.0;
      }
    }

    // 🔹 보유 종목들끼리 비중(%)
    if (investedAmountAll > 0) {
      for (int i = 0; i < positions.length; i++) {
        final p = positions[i];
        final w = (p.amount / investedAmountAll) * 100.0;
        positions[i] = DateSymbolPosition(
          symbol: p.symbol,
          name: p.name,
          qty: p.qty,
          amount: p.amount,
          profitRate: p.profitRate,
          weight: w,
        );
      }
    }

    // 🔹 전체 자본 = 초기 투자금 + 전체 손익
    final double equityAll = baseInvest + totalProfitAll;

    // 🔹 전체 기준 매수 가능 금액 = (전체 자본) - (현재까지 총 매수금)
    double available = equityAll - totalInvestAll;
    if (available < 0) available = 0;

    // 🔹 포트폴리오 전체 수익률 (초기 투자금 기준)
    final double totalProfitRateAll =
    baseInvest > 0 ? ((equityAll - baseInvest) / baseInvest) * 100.0 : 0.0;

    // ✅ totalAmount = 전체 자산 평가금액(자본)
    return DateStatusResult(
      qty: mainQty,
      avgPrice: mainAvg,
      profitRate: mainProfitRate,
      available: available,
      positions: positions,
      totalAmount: equityAll,
      totalProfitRate: totalProfitRateAll,
    );
  }
}

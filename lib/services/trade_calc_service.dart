// 📄 lib/services/trade_calc_service.dart
class TradeCalcResult {
  final List<Map<String, dynamic>> logs; // 정렬 + 계산정보가 들어간 로그
  final double buyQty;
  final double buyAmount;
  final double avgBuy;

  final double sellQty;
  final double sellAmount;
  final double avgSell;

  final double realizedProfit;
  final double evalProfit;
  final double totalInvested;
  final double totalProfit;
  final double profitRate;

  TradeCalcResult({
    required this.logs,
    required this.buyQty,
    required this.buyAmount,
    required this.avgBuy,
    required this.sellQty,
    required this.sellAmount,
    required this.avgSell,
    required this.realizedProfit,
    required this.evalProfit,
    required this.totalInvested,
    required this.totalProfit,
    required this.profitRate,
  });
}

class TradeCalcService {
  /// TradeLogSummary에 있던 로직을 그대로 옮긴 계산 함수
  static TradeCalcResult calculate(
      List<Map<String, dynamic>> rawLogs,
      double? currentPrice,
      ) {
    if (rawLogs.isEmpty) {
      return TradeCalcResult(
        logs: [],
        buyQty: 0,
        buyAmount: 0,
        avgBuy: 0,
        sellQty: 0,
        sellAmount: 0,
        avgSell: 0,
        realizedProfit: 0,
        evalProfit: 0,
        totalInvested: 0,
        totalProfit: 0,
        profitRate: 0,
      );
    }

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    // ✅ 원본을 그대로 쓰지 않고 복사해서 사용 (UI 쪽과 분리)
    final sortedLogs = rawLogs
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);

    // ✅ 날짜 순 정렬 (date / trade_date 둘 다 지원)
    sortedLogs.sort((a, b) {
      DateTime parseDate(String s) {
        final parts = s.replaceAll('.', '-').split('-');
        if (parts.length < 3) return DateTime(2000);
        return DateTime(
          int.tryParse(parts[0]) ?? 2000,
          int.tryParse(parts[1]) ?? 1,
          int.tryParse(parts[2]) ?? 1,
        );
      }

      final ad = (a['date'] ?? a['trade_date'] ?? '').toString();
      final bd = (b['date'] ?? b['trade_date'] ?? '').toString();

      return parseDate(ad).compareTo(parseDate(bd));
    });

    // ✅ 매수/매도 상태 변수
    double buyQty = 0;
    double buyAmount = 0;
    double avgBuy = 0;

    double sellQty = 0;
    double sellAmount = 0;
    double avgSell = 0;

    double realizedProfit = 0;
    double evalProfit = 0;
    double totalInvested = 0;

    // ✅ 거래별 루프
    for (var log in sortedLogs) {
      // 서버: side=BUY/SELL, quantity
      // 앱: type=매수/매도, qty
      final typeRaw = (log['type'] ?? log['side'] ?? '').toString();
      final upper = typeRaw.toUpperCase();

      final bool isBuy = (typeRaw == '매수') || (upper == 'BUY');
      final bool isSell = (typeRaw == '매도') || (upper == 'SELL');

      final qty = _toDouble(log['qty'] ?? log['quantity']);
      final price = _toDouble(log['price']);

      // 타입이 이상하면 스킵(안전)
      if (!isBuy && !isSell) {
        log['avgPriceAtTrade'] = 0.0;
        log['profitAtTrade'] = 0.0;
        log['profitRateAtTrade'] = 0.0;
        log['currentQty'] = (buyQty - sellQty);
        log['currentBalance'] = 0.0;
        continue;
      }

      // ✅ 매수 처리
      if (isBuy) {
        if (sellQty > 0) {
          // 공매도 청산 중
          double closeQty = qty <= sellQty ? qty : sellQty;

          // ✅ FIX: 공매도(숏) 청산 손익은 (진입가 - 청산가)
          double profit = (avgSell - price) * closeQty;
          realizedProfit += profit;

          sellQty -= closeQty;
          sellAmount -= avgSell * closeQty;
          if (sellQty < 0) sellQty = 0;

          log['avgPriceAtTrade'] = avgSell;
          log['profitAtTrade'] = profit;
          log['profitRateAtTrade'] =
          avgSell > 0 ? (profit / (avgSell * closeQty)) * 100 : 0;

          // 남은 수량이 있다면 새 매수 진입
          if (qty > closeQty) {
            double openQty = qty - closeQty;
            buyAmount += price * openQty;
            buyQty += openQty;
            avgBuy = buyAmount / buyQty;
            totalInvested += price * openQty;
          }
        } else {
          // ✅ 잔량 있는 매수 누적
          buyAmount += price * qty;
          buyQty += qty;
          avgBuy = buyAmount / buyQty;
          totalInvested += price * qty;

          log['avgPriceAtTrade'] = avgBuy;
          log['profitAtTrade'] = 0;
          log['profitRateAtTrade'] = 0;
        }

        // ✅ 거래 직후 잔고 계산
        double currentQty = buyQty - sellQty;
        double avgPrice = buyQty > 0 ? avgBuy : avgSell;
        double currentBalance = avgPrice * currentQty;

        log['currentQty'] = currentQty;
        log['currentBalance'] = currentBalance;
      }

      // ✅ 매도 처리
      else if (isSell) {
        if (buyQty > 0) {
          // 일반 매도 청산
          double closeQty = qty <= buyQty ? qty : buyQty;
          double profit = (price - avgBuy) * closeQty;
          realizedProfit += profit;

          buyQty -= closeQty;
          buyAmount -= avgBuy * closeQty;
          if (buyQty < 0) buyQty = 0;

          log['avgPriceAtTrade'] = avgBuy;
          log['profitAtTrade'] = profit;
          log['profitRateAtTrade'] =
          avgBuy > 0 ? (profit / (avgBuy * closeQty)) * 100 : 0;

          // 남은 수량이 있으면 공매도 진입
          if (qty > closeQty) {
            double openQty = qty - closeQty;
            sellAmount += price * openQty;
            sellQty += openQty;
            avgSell = sellAmount / sellQty;
          }
        } else {
          // ✅ 잔량 있는 매도 누적
          sellAmount += price * qty;
          sellQty += qty;
          avgSell = sellAmount / sellQty;

          log['avgPriceAtTrade'] = avgSell;
          log['profitAtTrade'] = 0;
          log['profitRateAtTrade'] = 0;
        }

        // ✅ 거래 직후 잔고 계산
        double currentQty = buyQty - sellQty;
        double avgPrice = buyQty > 0 ? avgBuy : avgSell;
        double currentBalance = avgPrice * currentQty;

        log['currentQty'] = currentQty;
        log['currentBalance'] = currentBalance;
      }
    }

    // ✅ 평가손익 (현재가 기준)
    if (currentPrice != null) {
      if (buyQty > 0) {
        evalProfit = (currentPrice - avgBuy) * buyQty;
      } else if (sellQty > 0) {
        evalProfit = (avgSell - currentPrice) * sellQty;
      }
    }

    double totalProfit = realizedProfit + evalProfit;
    double profitRate =
    totalInvested > 0 ? (totalProfit / totalInvested) * 100 : 0;

    return TradeCalcResult(
      logs: sortedLogs,
      buyQty: buyQty,
      buyAmount: buyAmount,
      avgBuy: avgBuy,
      sellQty: sellQty,
      sellAmount: sellAmount,
      avgSell: avgSell,
      realizedProfit: realizedProfit,
      evalProfit: evalProfit,
      totalInvested: totalInvested,
      totalProfit: totalProfit,
      profitRate: profitRate,
    );
  }

  // ✅ 추가: 거래내역(rawLogs)로부터 특정 날짜(asOf) 기준 보유수량 계산 (거래내역과 동일 로직 공유)
  static double holdingQtyAsOf(
      List<Map<String, dynamic>> rawLogs,
      DateTime asOf,
      ) {
    if (rawLogs.isEmpty) return 0.0;

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    DateTime _parseDate(dynamic v) {
      final s = (v ?? '').toString();
      if (s.isEmpty) return DateTime(2000);

      // "YYYY-MM-DD" 또는 "YYYY.MM.DD" 또는 ISO 대응
      final normalized = s.replaceAll('.', '-');
      if (normalized.length >= 10) {
        final head = normalized.substring(0, 10);
        final parts = head.split('-');
        if (parts.length >= 3) {
          return DateTime(
            int.tryParse(parts[0]) ?? 2000,
            int.tryParse(parts[1]) ?? 1,
            int.tryParse(parts[2]) ?? 1,
          );
        }
      }

      try {
        return DateTime.parse(normalized);
      } catch (_) {
        return DateTime(2000);
      }
    }

    // ✅ 날짜순 정렬(원본 보호)
    final logs = rawLogs.map((e) => Map<String, dynamic>.from(e)).toList();
    logs.sort((a, b) {
      final ad = _parseDate(a['date'] ?? a['trade_date']);
      final bd = _parseDate(b['date'] ?? b['trade_date']);
      return ad.compareTo(bd);
    });

    // ✅ 기준일(날짜만)로 맞춤
    final asOfDay = DateTime(asOf.year, asOf.month, asOf.day);

    double buyQty = 0.0;
    double sellQty = 0.0;

    for (final log in logs) {
      final d = _parseDate(log['date'] ?? log['trade_date']);
      final day = DateTime(d.year, d.month, d.day);
      if (day.isAfter(asOfDay)) break;

      final typeRaw = (log['type'] ?? log['side'] ?? '').toString();
      final upper = typeRaw.toUpperCase();

      final bool isBuy = (typeRaw == '매수') || (upper == 'BUY');
      final bool isSell = (typeRaw == '매도') || (upper == 'SELL');
      if (!isBuy && !isSell) continue;

      final qty = _toDouble(log['qty'] ?? log['quantity']);

      if (isBuy) {
        // BUY는 +, 단 숏 청산은 sellQty 감소로 자연 반영
        if (sellQty > 0) {
          final closeQty = qty <= sellQty ? qty : sellQty;
          sellQty -= closeQty;
          final remain = qty - closeQty;
          if (remain > 0) buyQty += remain;
        } else {
          buyQty += qty;
        }
      } else if (isSell) {
        // SELL은 -, 단 롱 청산은 buyQty 감소로 자연 반영
        if (buyQty > 0) {
          final closeQty = qty <= buyQty ? qty : buyQty;
          buyQty -= closeQty;
          final remain = qty - closeQty;
          if (remain > 0) sellQty += remain;
        } else {
          sellQty += qty;
        }
      }
    }

    return buyQty - sellQty;
  }
}

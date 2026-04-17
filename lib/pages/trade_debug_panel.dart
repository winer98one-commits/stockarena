// 📄 lib/pages/trade_debug_panel.dart
import 'package:flutter/material.dart';
import '../widgets/trade_mode_toggle.dart'; // TradeMode enum 사용

/// 거래내역 페이지 하단에 붙는 디버그 전용 패널
class TradeDebugPanel extends StatelessWidget {
  final TradeMode mode;
  final List<Map<String, dynamic>> logs;
  final double? currentPrice;

  const TradeDebugPanel({
    super.key,
    required this.mode,
    required this.logs,
    this.currentPrice,
  });

  @override
  Widget build(BuildContext context) {
    // 매매내역 없으면 아무것도 안 보이게
    if (logs.isEmpty) {
      return const SizedBox.shrink();
    }

    // 🔹 1) 날짜 순 정렬 (오래된 순)
    final sortedLogs = List<Map<String, dynamic>>.from(logs);
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

      return parseDate(a['date'].toString())
          .compareTo(parseDate(b['date'].toString()));
    });

    // 🔹 2) 요약 계산용 변수 (기존 summary 로직과 동일한 구조)
    double buyQty = 0;
    double buyAmount = 0;
    double avgBuy = 0;

    double sellQty = 0;
    double sellAmount = 0;
    double avgSell = 0;

    double realizedProfit = 0;
    double evalProfit = 0;
    double totalInvested = 0;

    // ✅ 거래 루프 (상태만 계산, 거래별 문자열은 더 이상 만들지 않음)
    for (final log in sortedLogs) {
      final type = log['type'];
      final qty = (log['qty'] ?? 0).toDouble();
      final price = (log['price'] ?? 0).toDouble();

      // 매수 처리
      if (type == '매수') {
        if (sellQty > 0) {
          // 공매도 일부/전체 청산
          final closeQty = qty <= sellQty ? qty : sellQty;
          final profit = (avgSell - price) * closeQty;
          realizedProfit += profit;

          sellQty -= closeQty;
          sellAmount -= avgSell * closeQty;
          if (sellQty < 0) sellQty = 0;

          // 남은 수량은 새 매수 진입
          if (qty > closeQty) {
            final openQty = qty - closeQty;
            buyAmount += price * openQty;
            buyQty += openQty;
            avgBuy = buyAmount / (buyQty == 0 ? 1 : buyQty);
            totalInvested += price * openQty;
          }
        } else {
          // 일반 매수 누적
          buyAmount += price * qty;
          buyQty += qty;
          avgBuy = buyAmount / (buyQty == 0 ? 1 : buyQty);
          totalInvested += price * qty;
        }
      }

      // 매도 처리
      else if (type == '매도') {
        if (buyQty > 0) {
          // 롱 포지션 청산
          final closeQty = qty <= buyQty ? qty : buyQty;
          final profit = (price - avgBuy) * closeQty;
          realizedProfit += profit;

          buyQty -= closeQty;
          buyAmount -= avgBuy * closeQty;
          if (buyQty < 0) buyQty = 0;

          // 남은 수량은 공매도 진입
          if (qty > closeQty) {
            final openQty = qty - closeQty;
            sellAmount += price * openQty;
            sellQty += openQty;
            avgSell = sellAmount / (sellQty == 0 ? 1 : sellQty);
          }
        } else {
          // 공매도 진입/증가
          sellAmount += price * qty;
          sellQty += qty;
          avgSell = sellAmount / (sellQty == 0 ? 1 : sellQty);
        }
      }
    }

    // 🔹 3) 평가손익 + 수익률 계산
    if (currentPrice != null) {
      if (buyQty > 0) {
        // 롱 포지션 잔량
        evalProfit = (currentPrice! - avgBuy) * buyQty;
      } else if (sellQty > 0) {
        // 공매도 잔량
        evalProfit = (avgSell - currentPrice!) * sellQty;
      }
    }

    final totalProfit = realizedProfit + evalProfit;
    final profitRate =
    totalInvested > 0 ? (totalProfit / totalInvested) * 100 : 0;

    // 잔고 수량
    final netQtyRaw = buyQty > 0 ? buyQty : -sellQty;
    final netQty = netQtyRaw.abs() < 1e-8 ? 0.0 : netQtyRaw; // -0 방지

    // 잔고 금액
    double? balance;
    if (currentPrice != null) {
      final rawBalance = currentPrice! * netQty;
      balance = rawBalance.abs() < 1e-8 ? 0.0 : rawBalance;
    }

    final profitColor = profitRate > 0
        ? Colors.red
        : (profitRate < 0 ? Colors.blue : Colors.grey);

    // 🔹 4) UI (간단 2~3줄 정보만 표시)
    final String modeLabel =
    mode == TradeMode.log ? '매매일지' : '투자 게임';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔍 디버그(임시용 출력)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '모드: $modeLabel',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 4),

          // ▶ 1줄: 총 투자금 / 실현손익 / 평가손익 + 기준가
          Text(
            '총 투자금: ${totalInvested.toStringAsFixed(2)},  '
                '실현손익: ${realizedProfit.toStringAsFixed(2)},  '
                '평가손익(잔량): ${evalProfit.toStringAsFixed(2)}'
                '${currentPrice != null ? ' (기준가: ${currentPrice!.toStringAsFixed(2)})' : ''}',
            style: const TextStyle(fontSize: 11),
          ),

          // ▶ 2줄: 총 손익 / 수익률
          Text(
            '총 손익: ${totalProfit.toStringAsFixed(2)},  '
                '수익률: ${profitRate.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 11,
              color: profitColor,
              fontWeight: FontWeight.w600,
            ),
          ),

          // ▶ 3줄: 잔고 수량 / 잔고 금액
          Text(
            '잔고 수량: ${netQty.toStringAsFixed(0)}주'
                '${balance != null ? ',  잔고 금액: ${balance!.toStringAsFixed(2)}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

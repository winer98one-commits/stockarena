// 📄 lib/widgets/candle_chart.dart
import 'package:flutter/material.dart';
import '../src/model/candle.dart';
import '../src/chart/candlesticks.dart';

class CandleChart extends StatelessWidget {
  final String symbol;
  final List<Candle> candles;
  final List<Map<String, dynamic>>? tradeLogs; // ✅ 매매일지 데이터 추가

  const CandleChart({
    super.key,
    required this.symbol,
    required this.candles,
    this.tradeLogs,
  });

  @override
  Widget build(BuildContext context) {
    // 🔹 심볼이 비어 있을 때는 차트 대신 안내 문구만
    if (symbol.isEmpty) {
      return const Center(
        child: Text('심볼을 선택하세요'),
      );
    }

    if (candles.isEmpty) {
      return const Center(child: Text('📭 차트 데이터가 없습니다.'));
    }

    final List<Candle> candlesSorted = List<Candle>.from(candles)
      ..sort((a, b) => a.date.compareTo(b.date));

    return Column(
      children: [
        Expanded(
          child: Candlesticks(
            candles: candlesSorted,
            tradeLogs: tradeLogs,
            symbol: symbol,
          ),
        ),
      ],
    );
  }
}
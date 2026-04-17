// 📄 lib/pages/trade_log_summary.dart
//
// ✅ 변경 후: 매매일지 / 투자게임 요약을 "서버 계산 결과"로 표시하는 위젯
//   - 더 이상 앱 내에서 직접 계산하지 않음
//   - logs + currentPrice 를 서버 /calc/trade-summary 에 보내서 결과 사용

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/trade_mode_toggle.dart'; // TradeMode enum
import '../services/stocknote_server_api.dart'; // fetchTradeSummaryFromServer 사용

class TradeLogSummary extends StatefulWidget {
  final TradeMode mode; // 🔹 매매일지 / 투자게임 모드
  final List<Map<String, dynamic>> logs;
  final double? currentPrice;

  // 🔹 요약 계산이 끝났을 때 부모에게 알려주는 콜백
  //    (예: 차트에 평가선 그릴 때 사용)
  final Function(double avgPrice, double totalProfit, double profitRate)?
  onCalculated;

  const TradeLogSummary({
    super.key,
    required this.mode,
    required this.logs,
    this.currentPrice,
    this.onCalculated,
  });

  @override
  State<TradeLogSummary> createState() => _TradeLogSummaryState();
}

class _TradeLogSummaryState extends State<TradeLogSummary> {
  bool _loading = false;
  String? _error;

  double _avgPrice = 0.0;
  double _totalProfit = 0.0;
  double _profitRate = 0.0;
  double _buyQty = 0.0;
  double _buyAmount = 0.0;
  double _realizedProfit = 0.0;
  double _evalProfit = 0.0;

  @override
  void initState() {
    super.initState();
    _recalcIfNeeded();
  }

  @override
  void didUpdateWidget(covariant TradeLogSummary oldWidget) {
    super.didUpdateWidget(oldWidget);

    // logs / currentPrice 변경 시 다시 계산
    if (oldWidget.logs != widget.logs ||
        oldWidget.currentPrice != widget.currentPrice ||
        oldWidget.mode != widget.mode) {
      _recalcIfNeeded();
    }
  }

  Future<void> _recalcIfNeeded() async {
    if (widget.logs.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _avgPrice = 0;
        _totalProfit = 0;
        _profitRate = 0;
        _buyQty = 0;
        _buyAmount = 0;
        _realizedProfit = 0;
        _evalProfit = 0;
      });
      // 부모 콜백도 0으로 알려줌
      widget.onCalculated?.call(0, 0, 0);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 🔹 서버로 계산 요청
      final result = await fetchTradeSummaryFromServer(
        logs: widget.logs,
        currentPrice: widget.currentPrice,
      );

      final buyQty = (result['buyQty'] as num?)?.toDouble() ?? 0.0;
      final buyAmount = (result['buyAmount'] as num?)?.toDouble() ?? 0.0;
      final avgBuy = (result['avgBuy'] as num?)?.toDouble() ?? 0.0;
      final realizedProfit =
          (result['realizedProfit'] as num?)?.toDouble() ?? 0.0;
      final evalProfit = (result['evalProfit'] as num?)?.toDouble() ?? 0.0;
      final totalProfit = (result['totalProfit'] as num?)?.toDouble() ?? 0.0;
      final profitRate = (result['profitRate'] as num?)?.toDouble() ?? 0.0;

      setState(() {
        _loading = false;
        _error = null;
        _avgPrice = avgBuy;
        _totalProfit = totalProfit;
        _profitRate = profitRate;
        _buyQty = buyQty;
        _buyAmount = buyAmount;
        _realizedProfit = realizedProfit;
        _evalProfit = evalProfit;
      });

      // 🔹 부모에게도 계산 결과 전달 (차트 등에서 사용 가능)
      widget.onCalculated?.call(avgBuy, totalProfit, profitRate);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '서버 계산 실패: $e';
      });
    }
  }

  String _formatNumber(double v) {
    // 간단 포맷터 (원하면 나중에 NumberFormat로 교체)
    if (v.abs() >= 1000000) {
      return v.toStringAsFixed(0);
    } else if (v.abs() >= 1000) {
      return v.toStringAsFixed(1);
    } else {
      return v.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로딩/에러/빈값은 화면에서 숨김(원하면 문구로 바꿔도 됨)
    if (_loading || _error != null || widget.logs.isEmpty) {
      return const SizedBox.shrink();
    }

    final pnl = _totalProfit;
    final pnlColor = pnl >= 0 ? Colors.red : Colors.blue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '총손익 ',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              _formatNumber(pnl),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: pnlColor,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildItem(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            color: highlight ? Colors.blueAccent : Colors.black,
          ),
        ),
      ],
    );
  }
}

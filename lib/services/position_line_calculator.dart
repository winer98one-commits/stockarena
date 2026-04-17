import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../src/model/candle.dart';

/// 포지션 라인 수평 구간(한 조각)
class PositionSegment {
  final int startIndex;   // 포함
  final int endIndex;     // 포함
  final double avgPrice;  // 구간 평단(수평선 Y)
  final double qty;       // 구간 동안 유지된 잔고(굵기 기준)
  final double widthPx;   // 선 굵기(px)
  final Color color;      // +빨강 / -파랑 / 0회색

  const PositionSegment({
    required this.startIndex,
    required this.endIndex,
    required this.avgPrice,
    required this.qty,
    required this.widthPx,
    required this.color,
  });
}

/// 날짜 포맷 yyyy-MM-dd
String _normalizeDate(String raw) {
  final parts = raw.replaceAll('.', '-').split('-');
  if (parts.length != 3) return raw;
  final y = parts[0];
  final m = parts[1].padLeft(2, '0');
  final d = parts[2].padLeft(2, '0');
  return '$y-$m-$d';
}

/// Candle 날짜 yyyy-MM-dd
String _dateOnly(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// 절대최대 대비 0~1 정규화
double _normAbs(double v, double maxAbs) {
  if (maxAbs <= 0) return 0.0;
  final n = (v.abs() / maxAbs).clamp(0.0, 1.0);
  return n.isNaN ? 0.0 : n;
}

/// ------------------------------------------------------
/// ✅ 롱/숏 포지션 모두 지원하는 거래 적용 로직
/// ------------------------------------------------------
({double qty, double cost}) _applyTrade({
  required double qty,     // 현재 잔고(+롱, -숏)
  required double cost,    // 현재 원가(+롱, -숏)
  required String type,    // '매수' | '매도'
  required double price,   // 거래 단가
  required double amount,  // 거래 수량(양수)
}) {
  double avgBefore = qty == 0 ? 0.0 : cost / qty; // 평균단가 (양수)

  if (type == '매수') {
    if (qty >= 0) {
      // 롱 확대 or 신규 롱
      cost += amount * price;
      qty  += amount;
    } else {
      // 숏 청산(커버)
      final shortAbs = (-qty);
      if (amount <= shortAbs) {
        cost += avgBefore * amount;
        qty  += amount;
        if (qty.abs() < 1e-9) { qty = 0; cost = 0; }
      } else {
        // 숏 전부 청산 후 남는 양 = 신규 롱
        cost += avgBefore * shortAbs;
        qty  += shortAbs;
        final remain = amount - shortAbs;
        cost = remain * price;
        qty  = remain;
      }
    }
  } else if (type == '매도') {
    if (qty > 0) {
      // 롱 청산
      if (amount <= qty) {
        cost -= avgBefore * amount;
        qty  -= amount;
        if (qty.abs() < 1e-9) { qty = 0; cost = 0; }
      } else {
        // 롱 전부 청산 후 남는 양 = 신규 숏
        cost -= avgBefore * qty;
        final remain = amount - qty;
        cost = -(remain * price);
        qty  = -remain;
      }
    } else {
      // 숏 확대 or 신규 숏
      cost -= amount * price;
      qty  -= amount;
    }
  }

  return (qty: qty, cost: cost);
}

/// ------------------------------------------------------
/// ✅ 포지션 라인 계산
/// ------------------------------------------------------
List<PositionSegment> buildPositionSegments({
  required List<Candle> candles,
  required List<Map<String, dynamic>> tradeLogs,
  double minWidthPx = 2.0,
  double maxWidthPx = 14.0,
  Color posColor = const Color(0xFFE34B4B), // + 잔고
  Color negColor = const Color(0xFF2F6FE3), // - 잔고
  Color flatColor = const Color(0xFF9E9E9E), // 0 잔고
}) {
  if (candles.isEmpty || tradeLogs.isEmpty) return [];

  // 날짜 -> 인덱스
  final idxByDate = <String, int>{};
  for (int i = 0; i < candles.length; i++) {
    idxByDate[_dateOnly(candles[i].date)] = i;
  }

  // 로그 정렬
  final logs = List<Map<String, dynamic>>.from(tradeLogs)
    ..sort((a, b) => _normalizeDate(a['date']?.toString() ?? '')
        .compareTo(_normalizeDate(b['date']?.toString() ?? '')));

  // 차트 존재 날짜만 필터링
  final entries = <({int idx, String type, double price, double qty})>[];
  for (final m in logs) {
    final d = _normalizeDate(m['date']?.toString() ?? '');
    final idx = idxByDate[d];
    if (idx == null) continue;
    entries.add((
    idx: idx,
    type: (m['type'] ?? '').toString(),
    price: (m['price'] as num?)?.toDouble() ?? 0.0,
    qty: (m['qty'] as num?)?.toDouble() ?? 0.0,
    ));
  }
  if (entries.isEmpty) return [];

  double qty = 0.0;
  double cost = 0.0;
  double avg = 0.0;

  int? prevTradeIdx;
  double? avgToHold;
  double qtyAfterPrev = 0;

  double maxAbsQtyObserved = 0.0;
  final segments = <PositionSegment>[];

  for (int i = 0; i < entries.length; i++) {
    final e = entries[i];

    // ✅ 롱/숏 모두 지원하는 거래 적용
    final res = _applyTrade(
      qty: qty,
      cost: cost,
      type: e.type,
      price: e.price,
      amount: e.qty,
    );
    qty  = res.qty;
    cost = res.cost;

    avg = qty == 0 ? 0.0 : (cost / qty);
    maxAbsQtyObserved = math.max(maxAbsQtyObserved, qty.abs());

    if (i == 0) {
      prevTradeIdx = e.idx;
      avgToHold    = avg;
      qtyAfterPrev = qty;

      final widthPx = minWidthPx +
          (maxWidthPx - minWidthPx) * _normAbs(qtyAfterPrev, maxAbsQtyObserved);
      final col = qtyAfterPrev > 0 ? posColor : (qtyAfterPrev < 0 ? negColor : flatColor);

      segments.add(PositionSegment(
        startIndex: e.idx,
        endIndex: e.idx,
        avgPrice: avgToHold!,
        qty: qtyAfterPrev,
        widthPx: widthPx,
        color: col,
      ));
    } else {
      final start = prevTradeIdx!;
      final end   = e.idx;

      final widthPx = minWidthPx +
          (maxWidthPx - minWidthPx) * _normAbs(qtyAfterPrev, maxAbsQtyObserved);
      final col = qtyAfterPrev > 0 ? posColor : (qtyAfterPrev < 0 ? negColor : flatColor);

      segments.add(PositionSegment(
        startIndex: start,
        endIndex: end,
        avgPrice: avgToHold!,
        qty: qtyAfterPrev,
        widthPx: widthPx,
        color: col,
      ));

      prevTradeIdx = e.idx;
      avgToHold    = avg;
      qtyAfterPrev = qty;
    }
  }

  // 마지막 구간
  if (prevTradeIdx != null && avgToHold != null) {
    final widthPx = minWidthPx +
        (maxWidthPx - minWidthPx) * _normAbs(qtyAfterPrev, maxAbsQtyObserved);
    final col = qtyAfterPrev > 0 ? posColor : (qtyAfterPrev < 0 ? negColor : flatColor);

    segments.add(PositionSegment(
      startIndex: prevTradeIdx!,
      endIndex: candles.length - 1,
      avgPrice: avgToHold!,
      qty: qtyAfterPrev,
      widthPx: widthPx,
      color: col,
    ));
  }

  // (보정)
  if (segments.isEmpty && entries.isNotEmpty) {
    final widthPx = minWidthPx +
        (maxWidthPx - minWidthPx) * _normAbs(qty, maxAbsQtyObserved);
    final col = qty > 0 ? posColor : (qty < 0 ? negColor : flatColor);

    segments.add(PositionSegment(
      startIndex: entries.first.idx,
      endIndex: candles.length - 1,
      avgPrice: avg,
      qty: qty,
      widthPx: widthPx,
      color: col,
    ));
  }

  return segments;
}

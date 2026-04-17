import 'dart:math';
import 'package:flutter/material.dart';
import '../model/candle.dart';
import '../../services/position_line_calculator.dart'; // ✅ 추가
import 'dart:math' as math; // ✅ 추가

class CandlesticksPainter extends CustomPainter {
  final List<Candle> candles;

  // ✅ 고정 간격 + 스크롤 기반
  final double candleStep;
  final double scrollX;
  final double viewportWidth;

  final Offset? hoverPos;
  final List<Map<String, dynamic>>? tradeLogs;

  // ✅ 추가: 한국 종목 판단 + 환율
  final String? symbol;
  final double usdToKrw;

  bool get _isKoreanStock {
    final s = (symbol ?? '').toUpperCase();
    return s.endsWith('.KS') || s.endsWith('.KQ');
  }

  CandlesticksPainter({
    required this.candles,
    required this.candleStep,
    required this.scrollX,
    required this.viewportWidth,
    this.hoverPos,
    this.tradeLogs,
    this.symbol,
    this.usdToKrw = 1.0,
  });


  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const double rightPadding = 60;

    final chartWidth = viewportWidth - rightPadding;
    final double fullCandleW = candleStep;

    int start = (scrollX / fullCandleW).floor();
    int end = ((scrollX + chartWidth) / fullCandleW).ceil();

    start = start.clamp(0, max(0, candles.length - 1));
    end = end.clamp(0, candles.length);

    if (end - start < 5) {
      end = min(candles.length, start + 5);
    }

    final slice = candles.sublist(start, end);

    double _xLeftByGlobal(int globalIndex) => globalIndex * fullCandleW;
    double _xCenterByGlobal(int globalIndex) =>
        (globalIndex * fullCandleW) + fullCandleW / 2;

    double _xLeftBySlice(int idxInSlice) => _xLeftByGlobal(start + idxInSlice);
    double _xCenterBySlice(int idxInSlice) =>
        _xCenterByGlobal(start + idxInSlice);

    double _xCenterByGlobalIndex(int globalIndex) =>
        _xCenterByGlobal(globalIndex);

    const double bottomLabelArea = 22.0;

    final priceHeight = size.height * 0.68;
    final volumeHeight = size.height * 0.14;
    final chartBottom = priceHeight + volumeHeight;

    final double viewportLeft = scrollX;
    final double viewportRight = scrollX + viewportWidth;
    final double yAxisTextX = viewportRight - 5.0;

    // ✅ 현재 보이는 구간은 유지하되, Y축 스케일은 최근 1년 기준으로 고정
    final now = DateTime.now();
    int endIndex = candles.length - 1;
    for (int i = candles.length - 1; i >= 0; i--) {
      if (!candles[i].date.isAfter(now)) {
        endIndex = i;
        break;
      }
    }

    final int yearStartIndex = max(0, endIndex - 252 + 1);
    final yearSlice = candles.sublist(yearStartIndex, endIndex + 1);

    double yearHigh = yearSlice.map((c) => c.high).reduce(max);
    double yearLow = yearSlice.map((c) => c.low).reduce(min);

    final double yearMid = (yearHigh + yearLow) / 2;
    double halfRange = (yearHigh - yearLow) / 2;

    if (halfRange <= 0) {
      halfRange = max(1.0, yearMid.abs() * 0.02);
    }

    halfRange *= 1.12;

    double high = yearMid + halfRange;
    double low = yearMid - halfRange;

    double y(double v) => priceHeight * (1 - (v - low) / (high - low));

    final paint = Paint()..strokeWidth = 1.0;

    final ma5 = _calcMA(slice, 5);
    final ma20 = _calcMA(slice, 20);
    final ma60 = _calcMA(slice, 60);

    final maColors = [
      Colors.orangeAccent,
      Colors.green,
      Colors.purpleAccent,
    ];
    final maData = [ma5, ma20, ma60];

    for (int j = 0; j < maData.length; j++) {
      final ma = maData[j];
      final path = Path();
      for (int i = 0; i < ma.length; i++) {
        if (ma[i] == null) continue;
        final x = _xCenterBySlice(i);
        final yPos = y(ma[i]!);
        if (i == 0 || ma[i - 1] == null) {
          path.moveTo(x, yPos);
        } else {
          path.lineTo(x, yPos);
        }
      }
      final maPaint = Paint()
        ..color = maColors[j]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(path, maPaint);
    }

    for (int i = 0; i < slice.length; i++) {
      final c = slice[i];
      final xLeft = _xLeftBySlice(i);
      final xCenter = _xCenterBySlice(i);

      paint.color = c.close >= c.open ? Colors.red : Colors.blue;

      canvas.drawLine(
        Offset(xCenter, y(c.high)),
        Offset(xCenter, y(c.low)),
        paint,
      );

      final rect = Rect.fromLTRB(
        xLeft + fullCandleW * 0.3,
        min(y(c.open), y(c.close)),
        xLeft + fullCandleW * 0.7,
        max(y(c.open), y(c.close)),
      );
      canvas.drawRect(rect, paint);
    }

    final double maxVol = slice.map((c) => c.volume).reduce(max);
    final double volScale = maxVol <= 0 ? 0 : volumeHeight / maxVol;

    for (int i = 0; i < slice.length; i++) {
      final c = slice[i];
      final xLeft = _xLeftBySlice(i);
      final volH = c.volume * volScale;
      final volTop = priceHeight + (volumeHeight - volH) - 6;

      paint.color = c.close >= c.open
          ? Colors.red.withValues(alpha: 0.6)
          : Colors.blue.withValues(alpha: 0.6);

      canvas.drawRect(
        Rect.fromLTRB(
          xLeft + fullCandleW * 0.3,
          volTop,
          xLeft + fullCandleW * 0.7,
          priceHeight + volumeHeight - 6,
        ),
        paint,
      );
    }

    if (tradeLogs != null && tradeLogs!.isNotEmpty) {
      final segments = buildPositionSegments(
        candles: candles,
        tradeLogs: tradeLogs!,
        minWidthPx: 3.0,
        maxWidthPx: 16.0,
      );

      final int startIdx = start;
      final int endIdxInclusive = end - 1;

      double yPrice(double p) => y(p);

      for (final seg in segments) {
        final s = seg.startIndex.clamp(startIdx, endIdxInclusive);
        final e = seg.endIndex.clamp(startIdx, endIdxInclusive);
        if (e < s) continue;

        final linePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..strokeWidth = seg.widthPx
          ..color = seg.color.withOpacity(
            seg.qty == 0 ? 0.10 : 0.30,
          );

        double priceForY = seg.avgPrice;

        if (_isKoreanStock && usdToKrw > 1.0) {
          final looksLikeUsd = priceForY > 0 && priceForY < low * 0.2;
          if (looksLikeUsd) {
            priceForY *= usdToKrw;
          }
        }

        final yy = yPrice(priceForY);
        canvas.drawLine(
          Offset(_xCenterByGlobalIndex(s), yy),
          Offset(_xCenterByGlobalIndex(e), yy),
          linePaint,
        );
      }

      const double capLen = 12.0;

      for (int i = 0; i < segments.length - 1; i++) {
        final curr = segments[i];
        final next = segments[i + 1];

        final eIdx = curr.endIndex;
        if (eIdx < startIdx || eIdx > endIdxInclusive) continue;

        final bool becomesFlat =
            curr.qty != 0 && next.qty == 0 && next.startIndex == curr.endIndex;

        if (!becomesFlat) continue;

        final x = _xCenterByGlobalIndex(eIdx);
        double priceForY = curr.avgPrice;

        if (_isKoreanStock && usdToKrw > 1.0) {
          final looksLikeUsd = priceForY > 0 && priceForY < low * 0.2;
          if (looksLikeUsd) {
            priceForY *= usdToKrw;
          }
        }

        final yMid = yPrice(priceForY);

        final capPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(2.0, curr.widthPx)
          ..color = Colors.black87.withOpacity(0.85);

        canvas.drawLine(
          Offset(x, yMid - capLen / 2),
          Offset(x, yMid + capLen / 2),
          capPaint,
        );
      }
    }

    if (tradeLogs != null && tradeLogs!.isNotEmpty) {
      for (final log in tradeLogs!) {
        final raw = log['date'] ?? '';
        final type = log['type'] ?? '';
        final bool edited =
            (log['price_edited'] == true) || (log['date_edited'] == true);

        try {
          final parts = raw.split('-');
          if (parts.length != 3) continue;

          final yearStr = parts[0];
          final monthStr = parts[1].padLeft(2, '0');
          final dayStr = parts[2].padLeft(2, '0');

          final date = DateTime.parse('$yearStr-$monthStr-$dayStr');

          final idxInSlice = slice.indexWhere((c) {
            final diff = c.date.difference(date).inHours.abs();
            return diff < 24;
          });

          if (idxInSlice == -1) {
            continue;
          }

          final bool isBuy = type == '매수';
          final paintTriangle = Paint()
            ..color = edited ? Colors.grey : (isBuy ? Colors.red : Colors.blue)
            ..style = PaintingStyle.fill;

          final double x = _xCenterBySlice(idxInSlice);

          final path = Path();
          if (isBuy) {
            final double yBottom = y(slice[idxInSlice].low) + 10;
            path
              ..moveTo(x, yBottom - 6)
              ..lineTo(x - 6, yBottom + 6)
              ..lineTo(x + 6, yBottom + 6)
              ..close();
            canvas.drawPath(path, paintTriangle);
          } else {
            final double yTop = y(slice[idxInSlice].high) - 10;
            path
              ..moveTo(x, yTop + 6)
              ..lineTo(x - 6, yTop - 6)
              ..lineTo(x + 6, yTop - 6)
              ..close();
            canvas.drawPath(path, paintTriangle);
          }
        } catch (_) {
          continue;
        }
      }
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final int labelCount = max(4, min(7, (chartWidth / 90).floor()));

    for (int i = 0; i < labelCount; i++) {
      final int index = ((slice.length - 1) * i / max(1, labelCount - 1)).round();
      final c = slice[index];

      String dateLabel;
      if (c.date.day <= 7) {
        dateLabel = "${c.date.year}/${c.date.month}";
      } else {
        dateLabel = "${c.date.month}/${c.date.day}";
      }

      final x = _xCenterBySlice(index);

      textPainter.text = TextSpan(
        text: dateLabel,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();

      final double labelY = chartBottom + ((bottomLabelArea - textPainter.height) / 2);

      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, labelY),
      );
    }

    final priceLabelPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    for (int i = 0; i <= 5; i++) {
      final double p = low + (high - low) * (i / 5);
      final double yPos = y(p);

      priceLabelPainter.text = TextSpan(
        text: p.toStringAsFixed(2),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.black87,
        ),
      );
      priceLabelPainter.layout();

      priceLabelPainter.paint(
        canvas,
        Offset(yAxisTextX - priceLabelPainter.width, yPos - 6),
      );
    }

    if (hoverPos != null) {
      final double localX = hoverPos!.dx.clamp(
        0,
        (candles.length * fullCandleW).toDouble(),
      );

      int globalIndex = (localX / fullCandleW).round();
      globalIndex = globalIndex.clamp(0, candles.length - 1);

      final Candle c = candles[globalIndex];
      final double x = _xCenterByGlobalIndex(globalIndex);

      final guidePaint = Paint()
        ..color = Colors.grey.withOpacity(0.7)
        ..strokeWidth = 0.8;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);

      final yValue = hoverPos!.dy.clamp(0, priceHeight).toDouble();
      canvas.drawLine(
        Offset(viewportLeft, yValue),
        Offset(viewportRight, yValue),
        guidePaint,
      );

      final dateLabel = "${c.date.year}-${c.date.month}-${c.date.day}";
      final hoverDate = TextPainter(
        text: TextSpan(
          text: dateLabel,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.deepPurple,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hoverDate.paint(canvas, Offset(x - hoverDate.width / 2, size.height - 18));

      final priceValue = high - (high - low) * (yValue / priceHeight);
      final hoverPrice = TextPainter(
        text: TextSpan(
          text: priceValue.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 11,
            color: Colors.deepPurple,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      hoverPrice.paint(
        canvas,
        Offset(yAxisTextX - hoverPrice.width, yValue - 8),
      );

      final info = "날짜: ${c.date.year}-${c.date.month}-${c.date.day}\n"
          "시가: ${c.open.toStringAsFixed(2)}\n"
          "고가: ${c.high.toStringAsFixed(2)}\n"
          "저가: ${c.low.toStringAsFixed(2)}\n"
          "종가: ${c.close.toStringAsFixed(2)}\n"
          "거래량: ${c.volume.toStringAsFixed(0)}";

      final hoverText = TextPainter(
        text: TextSpan(
          text: info,
          style: const TextStyle(color: Colors.black, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);

      final boxW = hoverText.width + 10;
      final boxH = hoverText.height + 10;
      final double tooltipX = hoverPos!.dx + 10;
      final double tooltipY = hoverPos!.dy - boxH - 10;

      final safeX =
      tooltipX + boxW > viewportRight ? hoverPos!.dx - boxW - 10 : tooltipX;
      final safeY = tooltipY < 0 ? hoverPos!.dy + 10 : tooltipY;

      final rect = Rect.fromLTWH(safeX, safeY, boxW, boxH);
      final boxPaint = Paint()..color = Colors.white.withOpacity(0.9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        boxPaint,
      );
      hoverText.paint(canvas, Offset(rect.left + 5, rect.top + 5));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  // ✅ 이동평균 계산 함수
  List<double?> _calcMA(List<Candle> candles, int period) {
    List<double?> ma = List.filled(candles.length, null);
    for (int i = period - 1; i < candles.length; i++) {
      final subset = candles.sublist(i - period + 1, i + 1);
      final avg =
          subset.map((c) => c.close).reduce((a, b) => a + b) / period;
      ma[i] = avg;
    }
    return ma;
  }
}

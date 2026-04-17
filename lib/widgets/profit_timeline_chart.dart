// 📄 lib/widgets/profit_timeline_chart.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/profit_timeline_service.dart';

final intl.NumberFormat _currency =
intl.NumberFormat.compactCurrency(locale: 'en_US', symbol: r'$');

const double _leftPadding = 50;
const double _rightPadding = 8;
const double _topPadding = 18;
const double _bottomPadding = 36;

class ProfitTimelineChart extends StatefulWidget {
  final List<ProfitPoint> points;
  final Map<String, String> symbolNames; // 심볼 → 이름

  const ProfitTimelineChart({
    super.key,
    required this.points,
    required this.symbolNames,
  });

  @override
  State<ProfitTimelineChart> createState() => _ProfitTimelineChartState();
}

class _ProfitTimelineChartState extends State<ProfitTimelineChart> {
  int? _selectedIndex; // 사용자가 가리키는 날짜 인덱스

  void _updateSelected(double dx, double width) {
    final points = widget.points;
    if (points.length < 2) return;

    final chartWidth = width - _leftPadding - _rightPadding;
    if (chartWidth <= 0) return;

    // x좌표를 차트 내부 범위로 클램핑
    final clampedX =
    dx.clamp(_leftPadding, width - _rightPadding).toDouble();

    final t = (clampedX - _leftPadding) / chartWidth; // 0~1
    final idx =
    (t * (points.length - 1)).round().clamp(0, points.length - 1);

    setState(() {
      _selectedIndex = idx;
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;

    if (points.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Text(
            '투자금과 매매 일지가 있어야\n수익 차트를 볼 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '투자 성장 차트 (누적 영역, 금액 기준)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) =>
                        _updateSelected(d.localPosition.dx, width),
                    onHorizontalDragUpdate: (d) =>
                        _updateSelected(d.localPosition.dx, width),
                    onHorizontalDragStart: (d) =>
                        _updateSelected(d.localPosition.dx, width),
                    child: ClipRect(
                      child: CustomPaint(
                        painter: _ProfitTimelinePainter(
                          points: points,
                          symbolNames: widget.symbolNames,
                          highlightedIndex: _selectedIndex,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfitTimelinePainter extends CustomPainter {
  final List<ProfitPoint> points;
  final Map<String, String> symbolNames;
  final int? highlightedIndex; // 툴팁으로 강조할 인덱스

  _ProfitTimelinePainter({
    required this.points,
    required this.symbolNames,
    required this.highlightedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final chartWidth = size.width - _leftPadding - _rightPadding;
    final chartHeight = size.height - _topPadding - _bottomPadding;

    // ✅ Y축 범위: 항상 0 ~ 전체 자산(totalEquity)의 최대값 기준
    final List<double> allValues = points
        .map((p) => p.totalEquity)
        .where((v) => v.isFinite && v > 0)
        .toList();

    if (allValues.isEmpty) return;

    double minY = 0;
    double maxY = allValues.reduce(math.max);

    if (maxY <= 0) {
      maxY = 1;
    } else {
      maxY *= 1.05; // 위로 5% 여유
    }

    double toX(int index) {
      if (points.length == 1) return _leftPadding + chartWidth / 2;
      final t = index / (points.length - 1);
      return _leftPadding + chartWidth * t;
    }

    double toY(double value) {
      final t = (value - minY) / (maxY - minY);
      return _topPadding + chartHeight * (1 - t);
    }

    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 0.8;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // ✅ Y축 눈금 (min / mid / max)
    final midYVal = (minY + maxY) / 2;
    final yLabels = <double>[minY, midYVal, maxY];

    for (final v in yLabels) {
      final y = toY(v);

      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(size.width - _rightPadding, y),
        axisPaint..color = Colors.grey.shade300,
      );

      textPainter.text = TextSpan(
        text: _currency.format(v),
        style: const TextStyle(fontSize: 9, color: Colors.grey),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          _leftPadding - 4 - textPainter.width,
          y - textPainter.height / 2,
        ),
      );
    }

    // ✅ X축 날짜: 최대 6개 지점
    final int labelCount = math.min(6, points.length);
    for (int i = 0; i < labelCount; i++) {
      final double t =
      (labelCount == 1) ? 0.0 : i / (labelCount - 1); // 0 ~ 1
      final int idx =
      ((points.length - 1) * t).round().clamp(0, points.length - 1);
      final date = points[idx].date;

      final x = toX(idx);
      textPainter.text = TextSpan(
        text: '${date.month}/${date.day}',
        style: const TextStyle(fontSize: 9, color: Colors.grey),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          x - textPainter.width / 2,
          size.height - _bottomPadding + 4,
        ),
      );
    }

    // ✅ 색 팔레트 (종목별 + 현금)
    final symbolList = symbolNames.keys.toList();
    const String cashKey = '_CASH_'; // totalEquity - 종목합

    final List<Color> palette = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.brown,
      Colors.teal,
    ];

    Color colorForKey(String key) {
      if (key == cashKey) return Colors.grey.shade400;
      final idx = symbolList.indexOf(key);
      if (idx < 0) return Colors.grey;
      return palette[idx % palette.length];
    }

    // ✅ 각 시점별 값 준비 (현금 = totalEquity - 종목 합)
    final int n = points.length;
    final List<String> layerKeys = [cashKey, ...symbolList];
    final Map<String, List<double>> seriesValues = {
      for (final k in layerKeys) k: List<double>.filled(n, 0),
    };

    double sanitize(double raw) {
      if (!raw.isFinite) return 0.0;
      if (raw < 0) return 0.0;
      return raw;
    }

    for (int i = 0; i < n; i++) {
      final p = points[i];

      double symbolsSum = 0;

      for (final sym in symbolList) {
        final double raw = (p.symbolEquity[sym] ?? 0).toDouble();
        final double v = sanitize(raw);
        seriesValues[sym]![i] = v;
        symbolsSum += v;
      }

      final double cashRaw = (p.totalEquity - symbolsSum).toDouble();
      final double cashVal = sanitize(cashRaw);
      seriesValues[cashKey]![i] = cashVal;
    }

    // ✅ Stacked area 그리기
    final List<double> base = List<double>.filled(n, 0);

    for (final key in layerKeys) {
      final values = seriesValues[key]!;
      final hasPositive = values.any((v) => v > 0);
      if (!hasPositive) continue;

      final path = Path();
      final List<Offset> tops = [];
      final List<Offset> bottoms = [];

      for (int i = 0; i < n; i++) {
        final x = toX(i);
        final bottomVal = base[i];
        final topVal = base[i] + values[i];

        bottoms.add(Offset(x, toY(bottomVal)));
        tops.add(Offset(x, toY(topVal)));
      }

      if (tops.isEmpty) continue;

      path.moveTo(tops.first.dx, tops.first.dy);
      for (int i = 1; i < tops.length; i++) {
        path.lineTo(tops[i].dx, tops[i].dy);
      }
      for (int i = bottoms.length - 1; i >= 0; i--) {
        path.lineTo(bottoms[i].dx, bottoms[i].dy);
      }
      path.close();

      final areaColor = colorForKey(key);

      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = areaColor.withValues(
          alpha: key == cashKey ? 0.3 : 0.55,
        );
      canvas.drawPath(path, fillPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = areaColor.withValues(alpha: 0.9);
      canvas.drawPath(path, borderPaint);

      for (int i = 0; i < n; i++) {
        base[i] += values[i];
      }
    }

    // ✅ 상단 범례
    double legendX = _leftPadding + 4;
    final double legendY = _topPadding + 4;

    void drawLegendItem(String label, Color color) {
      canvas.drawRect(
        Rect.fromLTWH(legendX, legendY + 2, 10, 6),
        Paint()..color = color,
      );
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(fontSize: 9, color: Colors.black87),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(legendX + 14, legendY),
      );
      legendX += 14 + textPainter.width + 8;
    }

    drawLegendItem('현금', colorForKey(cashKey));

    for (final sym in symbolList) {
      final name = symbolNames[sym] ?? sym;
      final shortName =
      name.length > 6 ? '${name.substring(0, 6)}…' : name;

      if (legendX > size.width - 60) break;
      drawLegendItem(shortName, colorForKey(sym));
    }

    // 🔍 선택된 날짜 툴팁 & 세로 라인
    if (highlightedIndex != null &&
        highlightedIndex! >= 0 &&
        highlightedIndex! < points.length) {
      final idx = highlightedIndex!;
      final p = points[idx];

      final x = toX(idx);

      // 세로 기준선
      final linePaint = Paint()
        ..color = Colors.grey.shade700
        ..strokeWidth = 0.8;
      canvas.drawLine(
        Offset(x, _topPadding),
        Offset(x, size.height - _bottomPadding),
        linePaint,
      );

      // 툴팁 내용 구성
      final dateStr = intl.DateFormat('yyyy-MM-dd').format(p.date);
      final totalStr = _currency.format(p.totalEquity);

      // 보유 종목 금액 + 현금
      final Map<String, double> active = {};
      double holdingsSum = 0;
      for (final sym in symbolList) {
        final v = (p.symbolEquity[sym] ?? 0).toDouble();
        if (v > 0) {
          active[sym] = v;
          holdingsSum += v;
        }
      }
      double cashVal = p.totalEquity - holdingsSum;
      if (cashVal < 0) cashVal = 0;

      final List<String> lines = [];
      lines.add('날짜: $dateStr');
      lines.add('총 자산: $totalStr');
      lines.add('현금: ${_currency.format(cashVal)}');

      // 보유 종목 최대 4개까지 표시
      final entries = active.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final maxSymbols = 4;
      for (int i = 0; i < entries.length && i < maxSymbols; i++) {
        final e = entries[i];
        final name = symbolNames[e.key] ?? e.key;
        lines.add('${name}: ${_currency.format(e.value)}');
      }

      const double rowHeight = 18;                 // 줄 간격 넓게
      final double boxWidth = 210;                 // 가로폭 넓게
      final double boxHeight = 14 + lines.length * rowHeight + 10;


      double boxX = x + 8;
      if (boxX + boxWidth > size.width - _rightPadding) {
        boxX = x - boxWidth - 8;
      }
      double boxY = _topPadding + 4;

      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(boxX, boxY, boxWidth, boxHeight),
        const Radius.circular(6),
      );
      final Paint tooltipPaint = Paint()..color = Colors.white;
      canvas.drawRRect(rrect, tooltipPaint);
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = Colors.grey.shade400,
      );

      // ✅ 글자도 크게 + 패딩 살짝 증가
      double textY = boxY + 10;
      for (final line in lines) {
        textPainter.text = TextSpan(
          text: line,
          style: const TextStyle(
            fontSize: 11,               // 글자 크기 ↑
            color: Colors.black87,
          ),
        );
        textPainter.layout(maxWidth: boxWidth - 12);
        textPainter.paint(
          canvas,
          Offset(boxX + 8, textY),      // 왼쪽 패딩 ↑
        );
        textY += rowHeight;
      }

    }
  }

  @override
  bool shouldRepaint(covariant _ProfitTimelinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.symbolNames.length != symbolNames.length ||
        oldDelegate.highlightedIndex != highlightedIndex;
  }
}

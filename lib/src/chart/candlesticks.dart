import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../model/candle.dart';
import '_candlesticks_painter.dart';

/// ✅ PC/WEB에서 마우스 드래그로 가로 스크롤 되게 하는 ScrollBehavior
class _ChartScrollBehavior extends MaterialScrollBehavior {
  const _ChartScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

enum _RangePreset { m3, m6, y1 }

class Candlesticks extends StatefulWidget {
  final List<Candle> candles;
  final List<Map<String, dynamic>>? tradeLogs;

  // ✅ 심볼(한국/미국 판단용)
  final String symbol;

  const Candlesticks({
    super.key,
    required this.candles,
    required this.symbol,
    this.tradeLogs,
  });

  @override
  State<Candlesticks> createState() => _CandlesticksState();
}

class _CandlesticksState extends State<Candlesticks> {
  final ScrollController _scroll = ScrollController();

  Offset? _hoverPos;
  _RangePreset _range = _RangePreset.y1;
  bool _needsApplyRange = true;

  String _timeframe = '1D';

  int _findEndIndexByToday(List<Candle> candles) {
    if (candles.isEmpty) return 0;
    final now = DateTime.now();

    for (int i = candles.length - 1; i >= 0; i--) {
      final d = candles[i].date;
      if (!d.isAfter(now)) return i;
    }
    return 0;
  }

  String _displayNameFromSymbol(String symbol) {
    final upper = symbol.toUpperCase();
    if (upper.endsWith('.US')) {
      return symbol.substring(0, symbol.length - 3);
    }
    if (upper.endsWith('.KS') || upper.endsWith('.KQ')) {
      return symbol.substring(0, symbol.length - 3);
    }
    return symbol;
  }

  double? _latestClose() {
    if (widget.candles.isEmpty) return null;
    return widget.candles.last.close;
  }

  double? _prevClose() {
    if (widget.candles.length < 2) return null;
    return widget.candles[widget.candles.length - 2].close;
  }

  double? _changeValue() {
    final latest = _latestClose();
    final prev = _prevClose();
    if (latest == null || prev == null) return null;
    return latest - prev;
  }

  double? _changePercent() {
    final latest = _latestClose();
    final prev = _prevClose();
    if (latest == null || prev == null || prev == 0) return null;
    return ((latest - prev) / prev) * 100.0;
  }

  int _presetToCount(_RangePreset p) {
    switch (p) {
      case _RangePreset.m3:
        return 63;
      case _RangePreset.m6:
        return 126;
      case _RangePreset.y1:
        return 252;
    }
  }

  double _stepForRange(double chartWidth) {
    final visibleCount = _presetToCount(_range);
    final step = chartWidth / visibleCount;
    return step.clamp(5.0, 18.0);
  }

  void _jumpToRange({
    required double chartWidth,
    required int endIndex,
    required _RangePreset preset,
  }) {
    if (!_scroll.hasClients) return;

    final visibleCount = _presetToCount(preset);
    final candleStep = (chartWidth / visibleCount).clamp(5.0, 18.0);
    final startIndex = max(0, endIndex - visibleCount + 1);
    final targetOffset = startIndex * candleStep;
    final maxExtent = _scroll.position.maxScrollExtent;

    _scroll.jumpTo(targetOffset.clamp(0.0, maxExtent));
  }

  void _applyRangeAfterBuild({
    required double chartWidth,
  }) {
    if (!_needsApplyRange) return;
    if (widget.candles.isEmpty) return;

    final endIndex = _findEndIndexByToday(widget.candles);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;

      _jumpToRange(
        chartWidth: chartWidth,
        endIndex: endIndex,
        preset: _range,
      );

      _needsApplyRange = false;
    });
  }

  @override
  void didUpdateWidget(covariant Candlesticks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candles.length != widget.candles.length) {
      _needsApplyRange = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _rangeButton(String label, _RangePreset preset) {
    final selected = _range == preset;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() {
          _range = preset;
          _needsApplyRange = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _timeButton(String label) {
    final selected = _timeframe == label;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        setState(() {
          _timeframe = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.grey.shade200 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected ? Border.all(color: Colors.black12) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.blue.shade800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double rightPadding = 90.0;
        const double topBarHeight = 92.0;

        final double chartWidth = max(0.0, constraints.maxWidth - rightPadding);
        final double candleStep = _stepForRange(chartWidth);

        final double contentWidth = max(
          constraints.maxWidth,
          (widget.candles.length * candleStep) + rightPadding,
        );

        _applyRangeAfterBuild(chartWidth: chartWidth);

        final latest = _latestClose();
        final change = _changeValue();
        final changePct = _changePercent();
        final isUp = (change ?? 0) >= 0;
        final nameText = _displayNameFromSymbol(widget.symbol);

        return Column(
          children: [
            SizedBox(
              height: topBarHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 250,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: latest == null
                            ? const SizedBox.shrink()
                            : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    nameText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '전일 기준',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                children: [
                                  Text(
                                    latest.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isUp ? Colors.red : Colors.blue,
                                    ),
                                  ),
                                  if (change != null && changePct != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} '
                                          '(${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isUp ? Colors.red : Colors.blue,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        )
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _timeButton('5'),
                            const SizedBox(width: 8),
                            _timeButton('15'),
                            const SizedBox(width: 8),
                            _timeButton('30'),
                            const SizedBox(width: 8),
                            _timeButton('1H'),
                            const SizedBox(width: 8),
                            _timeButton('5H'),
                            const SizedBox(width: 8),
                            _timeButton('1D'),
                            const SizedBox(width: 8),
                            _timeButton('1W'),
                            const SizedBox(width: 8),
                            _timeButton('1M'),
                            const SizedBox(width: 12),
                            _rangeButton('3개월', _RangePreset.m3),
                            const SizedBox(width: 6),
                            _rangeButton('6개월', _RangePreset.m6),
                            const SizedBox(width: 6),
                            _rangeButton('1년', _RangePreset.y1),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: MouseRegion(
                onHover: (e) {
                  final scrollOffset = _scroll.hasClients ? _scroll.offset : 0.0;
                  setState(() {
                    _hoverPos = Offset(
                      e.localPosition.dx + scrollOffset,
                      e.localPosition.dy,
                    );
                  });
                },
                onExit: (_) => setState(() => _hoverPos = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    if (!_scroll.hasClients) return;
                    final next = (_scroll.offset - details.delta.dx).clamp(
                      0.0,
                      _scroll.position.maxScrollExtent,
                    );
                    _scroll.jumpTo(next);
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      setState(() {});
                      return false;
                    },
                    child: ScrollConfiguration(
                      behavior: const _ChartScrollBehavior(),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: contentWidth,
                          height: max(0.0, constraints.maxHeight - topBarHeight),
                          child: CustomPaint(
                            painter: CandlesticksPainter(
                              candles: widget.candles,
                              candleStep: candleStep,
                              scrollX: _scroll.hasClients ? _scroll.offset : 0.0,
                              viewportWidth: constraints.maxWidth,
                              hoverPos: _hoverPos,
                              tradeLogs: widget.tradeLogs,
                              symbol: '',
                              usdToKrw: 1350.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
import '../src/model/candle.dart';
import 'chart_cache_service.dart';

class TradeDatePriceLookupResult {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  const TradeDatePriceLookupResult({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

class TradeDatePriceLookupService {
  static Future<TradeDatePriceLookupResult?> findByDate({
    required String symbol,
    required DateTime targetDate,
    String period = '1y',
  }) async {
    final candles = await ChartCacheService.getChart(
      symbolRaw: symbol,
      period: period,
    );

    if (candles.isEmpty) return null;

    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);

    Candle? found;
    for (final candle in candles) {
      final d = DateTime(candle.date.year, candle.date.month, candle.date.day);
      if (d.year == target.year && d.month == target.month && d.day == target.day) {
        found = candle;
        break;
      }
    }

    if (found == null) return null;

    return TradeDatePriceLookupResult(
      date: DateTime(found.date.year, found.date.month, found.date.day),
      open: found.open,
      high: found.high,
      low: found.low,
      close: found.close,
    );
  }
}
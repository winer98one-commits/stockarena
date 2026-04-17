// 📄 lib/services/chart_cache_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../src/model/candle.dart';
import 'stocknote_server_api.dart';

class ChartCacheService {

  static const Duration cacheDuration = Duration(hours: 24);
  static final Map<String, Future<List<Candle>>> _inFlight = {};

  static String _dataKey(String symbol) => "chart_data_$symbol";
  static String _timeKey(String symbol) => "chart_time_$symbol";

  /// 차트 가져오기 (캐시 우선)
  static Future<List<Candle>> getChart({
    required String symbolRaw,
    String period = '1y',
  }) async {

    final key = "$symbolRaw|$period";

    final prefs = await SharedPreferences.getInstance();

    final dataKey = _dataKey(symbolRaw);
    final timeKey = _timeKey(symbolRaw);

    // 1️⃣ 캐시 먼저 반환
    final cachedJson = prefs.getString(dataKey);
    final cachedTime = prefs.getInt(timeKey);

    if (cachedJson != null && cachedTime != null) {
      final cacheDate =
      DateTime.fromMillisecondsSinceEpoch(cachedTime);

      final diff = DateTime.now().difference(cacheDate);

      if (diff < cacheDuration) {
        final List list = jsonDecode(cachedJson);

        return list
            .map((e) => _candleFromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    }

    // 2️⃣ 이미 요청 중이면 공유
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }

    // 3️⃣ 서버 요청
    final future = _fetchAndCache(symbolRaw, period);
    _inFlight[key] = future;

    final result = await future;

    _inFlight.remove(key);

    return result;
  }

  static Future<List<Candle>> _fetchAndCache(
      String symbolRaw,
      String period,
      ) async {

    final prefs = await SharedPreferences.getInstance();

    try {
      final candles = await StocknoteServerApi.fetchPrices(
        symbolRaw: symbolRaw,
        period: period,
      );

      if (candles.isNotEmpty) {
        final jsonList =
        candles.map((e) => _candleToMap(e)).toList();

        await prefs.setString(
            _dataKey(symbolRaw),
            jsonEncode(jsonList));

        await prefs.setInt(
            _timeKey(symbolRaw),
            DateTime.now().millisecondsSinceEpoch);

        return candles;
      }
    } catch (_) {}

    // 🔥 실패 시 캐시 fallback
    final cachedJson = prefs.getString(_dataKey(symbolRaw));

    if (cachedJson != null) {
      final List list = jsonDecode(cachedJson);

      return list
          .map((e) => _candleFromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    return [];
  }

  /// 강제 업데이트
  static Future<List<Candle>> refreshChart({
    required String symbolRaw,
    String period = '1y',
  }) async {

    final prefs = await SharedPreferences.getInstance();

    final candles = await StocknoteServerApi.fetchPrices(
      symbolRaw: symbolRaw,
      period: period,
    );

    final jsonList = candles.map((e) => _candleToMap(e)).toList();

    await prefs.setString(
        _dataKey(symbolRaw),
        jsonEncode(jsonList));

    await prefs.setInt(
        _timeKey(symbolRaw),
        DateTime.now().millisecondsSinceEpoch);

    return candles;
  }

  static Candle _candleFromMap(Map<String, dynamic> map) {
    return Candle(
      date: DateTime.parse((map['date'] ?? '').toString()),
      open: (map['open'] as num?)?.toDouble() ?? 0.0,
      high: (map['high'] as num?)?.toDouble() ?? 0.0,
      low: (map['low'] as num?)?.toDouble() ?? 0.0,
      close: (map['close'] as num?)?.toDouble() ?? 0.0,
      volume: (map['volume'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static Map<String, dynamic> _candleToMap(Candle candle) {
    return {
      'date': candle.date.toIso8601String(),
      'open': candle.open,
      'high': candle.high,
      'low': candle.low,
      'close': candle.close,
      'volume': candle.volume,
    };
  }
}
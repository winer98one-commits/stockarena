// 📄 lib/services/quote_cache_service.dart

import 'stocknote_server_api.dart';

import 'stocknote_server_api.dart';

class QuoteCacheService {
  static const Duration cacheDuration = Duration(minutes: 5); // 🔥 변경
  static const Duration serverFreshDuration = Duration(minutes: 30);

  static final Map<String, double> _priceCache = {};
  static final Map<String, DateTime> _timeCache = {};
  static final Map<String, Future<double?>> _inFlight = {};

  static DateTime? _parseQuoteTime(Map<String, dynamic>? item) {
    if (item == null) return null;

    final rawSourceTs = item['source_timestamp']?.toString().trim();
    if (rawSourceTs != null && rawSourceTs.isNotEmpty) {
      try {
        return DateTime.parse(rawSourceTs).toUtc();
      } catch (_) {}
    }

    final rawUpdatedAt = item['updated_at']?.toString().trim();
    if (rawUpdatedAt != null && rawUpdatedAt.isNotEmpty) {
      try {
        return DateTime.parse(rawUpdatedAt).toUtc();
      } catch (_) {}
    }

    return null;
  }

  static bool _isFreshQuoteTime(DateTime? quoteTime) {
    if (quoteTime == null) return false;

    final nowUtc = DateTime.now().toUtc();
    final diff = nowUtc.difference(quoteTime);

    if (diff.isNegative) return true;
    return diff <= serverFreshDuration;
  }

  /// 현재가 조회
  static Future<double?> getLatestQuote({
    required String symbol,
    bool forceRefresh = false,
  }) async {
    // 1️⃣ 캐시 먼저 반환 (가장 중요)
    if (!forceRefresh &&
        _priceCache.containsKey(symbol) &&
        _timeCache.containsKey(symbol)) {
      final diff = DateTime.now().difference(_timeCache[symbol]!);

      if (diff < cacheDuration) {
        return _priceCache[symbol];
      }
    }

    // 2️⃣ 이미 요청 중이면 기존 요청 공유
    if (_inFlight.containsKey(symbol)) {
      return _inFlight[symbol];
    }

    // 3️⃣ 서버 요청 생성
    final future = _fetchAndCache(symbol);

    _inFlight[symbol] = future;

    final result = await future;

    _inFlight.remove(symbol);

    return result ?? _priceCache[symbol]; // 🔥 실패 시 기존 값 유지
  }

  static Future<double?> _fetchAndCache(String symbol) async {
    try {
      final latestQuote = await StocknoteServerApi.fetchLatestQuote(
        symbol: symbol,
      );

      final rawPrice = latestQuote?['price'];
      final quoteTime = _parseQuoteTime(latestQuote);

      if (rawPrice is num && _isFreshQuoteTime(quoteTime)) {
        final price = rawPrice.toDouble();

        _priceCache[symbol] = price;
        _timeCache[symbol] = DateTime.now();

        return price;
      }
    } catch (_) {}

    return _priceCache[symbol]; // 🔥 실패해도 기존 값 유지
  }

  /// 강제 새로고침
  static Future<double?> refreshQuote({
    required String symbol,
  }) async {
    return getLatestQuote(
      symbol: symbol,
      forceRefresh: true,
    );
  }
}
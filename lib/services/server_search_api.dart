// 📄 lib/services/server_search_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 서버의 /search (EODHD 기반)를 호출해서
/// [{symbol, name, exchange, ...}, ...] 형태로 돌려주는 헬퍼
class ServerSearchApi {
  // ⭐ 서버 주소
  static const String baseUrl = 'http://46.224.127.151:8000';

  /// EODHD 기반 서버 검색
  /// - 반환 형식: List<Map<String, dynamic>>
  ///   각각의 Map 안에는 최소한 다음 필드가 들어 있음:
  ///   { 'symbol': 'AAA.US', 'name': 'AAA Corp', 'exchange': 'US/NYSE', ... }
  static Future<List<Map<String, dynamic>>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final uri = Uri.parse('$baseUrl/search?q=$trimmed');

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Server search failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);

    if (data is! List) {
      throw Exception('Unexpected search response format');
    }

    final List<Map<String, dynamic>> results = [];

    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;

      // 🔹 서버가 내려주는 정식 심볼 우선 사용
      final symbolRaw = (item['symbol_raw'] ??
          item['Symbol'] ??
          item['symbol'] ??
          item['Code'] ??
          item['code'] ??
          '')
          .toString()
          .trim();

      final code =
      (item['Code'] ?? item['code'] ?? item['symbol'] ?? '').toString().trim();

      String name = (item['Name'] ?? item['name'] ?? '').toString().trim();
      final exchange = (item['Exchange'] ?? item['exchange'] ?? '').toString().trim();
      final country = (item['Country'] ?? item['country'] ?? '').toString().trim();
      final currency = (item['Currency'] ?? item['currency'] ?? '').toString().trim();
      final type = (item['Type'] ?? item['type'] ?? item['asset_type'] ?? '')
          .toString()
          .trim();

      if (symbolRaw.isEmpty) continue;

      if (name.isEmpty) {
        name = symbolRaw;
      }

      final exchangeLabel = country.isNotEmpty
          ? (exchange.isNotEmpty ? '$country/$exchange' : country)
          : (exchange.isNotEmpty ? exchange : 'EODHD');

      results.add({
        // ✅ 서버 조회/저장용 정식 심볼
        'symbol': symbolRaw,        // 예: "AAPL.US", "BTC-USD.CC"

        // ✅ 표시용 코드
        'code': code.isNotEmpty ? code : symbolRaw, // 예: "AAPL", "BTC"

        'symbol_raw': symbolRaw,    // 예: "AAPL.US", "BTC-USD.CC"
        'name': name,
        'exchange': exchangeLabel,
        'country': country,
        'currency': currency,
        'rawType': type,
      });
    }

    return results;
  }
}

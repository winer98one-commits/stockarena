// 📄 lib/services/stocknote_server_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../src/model/candle.dart';

/// 서버와 통신하는 공용 API 모음
class StocknoteServerApi {
  /// FastAPI 서버 기본 주소
  static const String baseUrl = 'http://46.224.127.151:8000';

  /// 🔎 검색 API 호출
  static Future<List<Map<String, dynamic>>> search({
    required String query,
    String assetType = '',
    String country = '',
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.parse(
      '$baseUrl/search?q=${Uri.encodeQueryComponent(q)}'
          '&asset_type=${Uri.encodeQueryComponent(assetType)}'
          '&country=${Uri.encodeQueryComponent(country)}',
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception(
        '검색 실패: ${res.statusCode} ${res.body}',
      );
    }

    final decoded = jsonDecode(res.body);

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    throw Exception('search 응답 형식 오류: $decoded');
  }

  /// 📌 차트용 캔들 데이터 불러오기
  /// GET /prices?symbol_raw=AAA.US&period=1y
  static Future<List<Candle>> fetchPrices({
    required String symbolRaw,
    String period = '1y',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/prices?symbol_raw=${Uri.encodeQueryComponent(symbolRaw)}'
          '&period=${Uri.encodeQueryComponent(period)}',
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception(
        '가격 조회 실패: ${res.statusCode} ${res.body}',
      );
    }

    final decoded = jsonDecode(res.body);

    List<dynamic> candlesJson;
    if (decoded is List) {
      candlesJson = decoded;
    } else if (decoded is Map<String, dynamic> &&
        decoded['candles'] is List) {
      candlesJson = decoded['candles'] as List<dynamic>;
    } else {
      throw Exception('prices 응답 형식 오류: $decoded');
    }

    return candlesJson.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return Candle(
        date: DateTime.parse(m['date'].toString()),
        open: (m['open'] as num).toDouble(),
        high: (m['high'] as num).toDouble(),
        low: (m['low'] as num).toDouble(),
        close: (m['close'] as num).toDouble(),
        volume: (m['volume'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  /// 📌 현재가 조회
  /// GET /quotes/latest?symbol=AAA.US
  static Future<Map<String, dynamic>?> fetchLatestQuote({
    required String symbol,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/quotes/latest?symbol=${Uri.encodeQueryComponent(symbol)}',
    );

    final res = await http.get(uri);

    if (res.statusCode == 404) {
      return null;
    }

    if (res.statusCode != 200) {
      throw Exception(
        '현재가 조회 실패: ${res.statusCode} ${res.body}',
      );
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic> &&
        decoded['ok'] == true &&
        decoded['item'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(decoded['item'] as Map);
    }

    throw Exception('quotes/latest 응답 형식 오류: $decoded');
  }
}

/// 📌 매매일지 / 투자게임 공통: 단일 종목 매매 요약 계산
///
/// - 서버 /calc/trade-summary 호출
/// - logs 에서 date, type, qty, price 만 뽑아서 보냄 (서버 모델에 맞추기)
Future<Map<String, dynamic>> fetchTradeSummaryFromServer({
  required List<Map<String, dynamic>> logs,
  double? currentPrice,
}) async {
  // 👉 서버 기본 주소는 위 StocknoteServerApi.baseUrl 재사용
  final uri = Uri.parse('${StocknoteServerApi.baseUrl}/calc/trade-summary');

  // 🔹 logs 안에는 symbol, memo 등 여러 필드가 있지만
  // 서버 pydantic 모델은 date/type/qty/price 네 개만 받음
  // → 꼭 필요한 필드만 골라서 보냄.
  final payloadLogs = logs.map((log) {
    final date = (log['date'] ?? '').toString();
    final type = (log['type'] ?? '').toString();

    double parseNum(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final qty = parseNum(log['qty']);
    final price = parseNum(log['price']);

    return {
      'date': date,
      'type': type,
      'qty': qty,
      'price': price,
    };
  }).toList();

  final body = jsonEncode({
    'logs': payloadLogs,
    'current_price': currentPrice,
  });

  final res = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: body,
  );

  if (res.statusCode != 200) {
    throw Exception(
      'calc/trade-summary 실패: ${res.statusCode} ${res.body}',
    );
  }

  final Map<String, dynamic> json = jsonDecode(res.body);
  return json;
}

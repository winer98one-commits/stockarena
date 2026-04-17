// 📄 lib/utils/symbol_resolver.dart (서버 전용 버전)

import '../services/server_search_api.dart';
import '../data/korea_symbol_map.dart';
import '../data/us_symbols.dart';
import '../data/crypto_symbols.dart';



/// 자산 종류 (지금은 쓰지 않지만, 나중 확장 대비해서 남겨둠)
enum AssetCategory {
  manual,
  kospi,
  kosdaq,
  future,
  crypto,
  usIndex,
  usEtf,
}

/// 검색 결과 구조 (필요하면 다른 곳에서 재사용 가능)
class SymbolSearchResult {
  final String name;
  final String symbol;
  final AssetCategory type;

  const SymbolSearchResult({
    required this.name,
    required this.symbol,
    required this.type,
  });
}

/// 직접 관리(예외용)
final Map<String, String> manualMap = {};

/// ==============================================
///  1) 한글 → 심볼 변환
///     - 예외 케이스만 수동으로 넣고, 나머지는 그대로 반환
/// ==============================================
String convertKoreanToSymbol(String input) {
  final key = input.trim();
  if (key.isEmpty) return key;

  // 1️⃣ 수동 등록 (가장 우선)
  if (manualMap.containsKey(key)) {
    return manualMap[key]!;
  }

  // 2️⃣ 이제는 별도의 Dart 맵을 쓰지 않고, 그대로 반환
  //    (실제 변환은 서버 /search 에서 처리)
  return key;
}

/// ==============================================
///  2) 서버 검색 전용 함수
///     - EODHD 기반 FastAPI 서버의 /search 를 그대로 사용
///     - 결과 형식: [{symbol, name, exchange, ...}, ...]
/// ==============================================
Future<List<Map<String, dynamic>>> searchAllWithYahoo(String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return [];

  try {
    // 서버 API 호출 (/search?q=...)
    final serverResults = await ServerSearchApi.search(trimmed);

    // 혹시 null 이나 이상한 값이 오더라도 안전하게 List<Map> 로 정리
    final List<Map<String, dynamic>> results = [];
    for (final item in serverResults) {
      if (item is Map<String, dynamic>) {
        results.add(item);
      }
    }
    return results;
  } catch (e) {
    // 에러 나면 그냥 빈 리스트 반환 (앱이 죽지 않도록)
    return [];
  }
}

/// ==============================================
///  3) 로컬 다트맵 검색 함수들
///     - korea_symbol_map.dart / us_symbols.dart / crypto_symbols.dart 등 사용
/// ==============================================

List<Map<String, dynamic>> searchLocalKorea(String keyword) {
  final lower = keyword.toLowerCase();
  final results = <Map<String, dynamic>>[];

  // korea_symbol_map.dart
  //   const Map<String, String> koreaSymbolMap = { '에임드바이오': '0009K0.KQ', ... };
  koreaSymbolMap.forEach((name, symbol) {
    final nameLower = name.toLowerCase();
    final symbolLower = symbol.toLowerCase();

    if (nameLower.contains(lower) || symbolLower.contains(lower)) {
      // .KQ → KOSDAQ, 나머지는 KOSPI 라고 대충 구분
      String exchange = 'KOREA';
      if (symbol.endsWith('.KQ')) {
        exchange = 'KOSDAQ';
      } else if (symbol.endsWith('.KS') || symbol.endsWith('.KO')) {
        exchange = 'KOSPI';
      }

      results.add({
        'name': name,
        'symbol': symbol,
        'exchange': exchange,
      });
    }
  });

  return results;
}

List<Map<String, dynamic>> searchLocalUS(String keyword) {
  final lower = keyword.toLowerCase();
  final results = <Map<String, dynamic>>[];

  // us_symbols.dart
  //   const Map<String, String> usSymbolMap = { 'Apple Inc': 'AAPL', ... };
  usSymbolMap.forEach((name, symbol) {
    final nameLower = name.toLowerCase();
    final symbolLower = symbol.toLowerCase();

    if (nameLower.contains(lower) || symbolLower.contains(lower)) {
      results.add({
        'name': name,
        'symbol': symbol,
        'exchange': 'US',
      });
    }
  });

  return results;
}

List<Map<String, dynamic>> searchLocalCrypto(String keyword) {
  final lower = keyword.toLowerCase();
  final results = <Map<String, dynamic>>[];

  // crypto_symbols.dart
  //   예: const Map<String, String> cryptoSymbolMap = { 'Bitcoin': 'BTC-USD', ... };
  //   실제 변수 이름이 다르면 아래 cryptoSymbolMap 을 맞게 바꿔주세요.
  cryptoSymbolMap.forEach((name, symbol) {
    final nameLower = name.toLowerCase();
    final symbolLower = symbol.toLowerCase();

    if (nameLower.contains(lower) || symbolLower.contains(lower)) {
      results.add({
        'name': name,
        'symbol': symbol,
        'exchange': 'CRYPTO',
      });
    }
  });

  return results;
}

/// 통합 로컬 검색: 한국 + 미국 + 코인 (+ 필요 시 선물/지수도 추가)
List<Map<String, dynamic>> searchLocalStocks(String keyword) {
  final results = <Map<String, dynamic>>[];

  results.addAll(searchLocalKorea(keyword));
  results.addAll(searchLocalUS(keyword));
  results.addAll(searchLocalCrypto(keyword));

  // 필요하면 futures / index 도 여기에 addAll
  // results.addAll(searchLocalFutures(keyword));
  // results.addAll(searchLocalIndex(keyword));

  return results;
}

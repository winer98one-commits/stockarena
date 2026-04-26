// 📄 lib/services/game_server_api.dart (교체 후 최종)

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class GameServerApi {
  static const String _baseUrl = "https://api.stockarena.co.kr";


  // --------------------------------------------------
  // ✅ 관리자용 Firebase ID Token 헤더 생성
  // --------------------------------------------------
  static Future<Map<String, String>> _buildAdminHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final token = await user.getIdToken(true);
    if (token == null || token.trim().isEmpty) {
      throw Exception('Firebase 토큰을 가져오지 못했습니다.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<bool> isCurrentUserAdmin() async {
    final uri = Uri.parse('$_baseUrl/admin/me');

    final res = await http.get(
      uri,
      headers: await _buildAdminHeaders(),
    );

    if (res.statusCode == 401) {
      return false;
    }

    if (res.statusCode != 200) {
      throw Exception('관리자 확인 실패: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['is_admin'] == true;
  }


  // --------------------------------------------------
  // 1) 게임 계정 생성 / 업데이트
  //    POST /game/register  → 서버 main.py: game_register()
  // --------------------------------------------------
  static Future<void> registerGameUser({
    required String uid,          // Firebase UID (로그인 사용자 고유 ID)
    required String nickname,
    String? email,
    String mode = "game",
    double initialBalance = 100000.0,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/register');

    final body = jsonEncode({
      'uid': uid,
      'nickname': nickname,
      'email': email,
      'mode': mode,
      'initial_balance': initialBalance,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('게임 계정 생성 실패: ${res.statusCode} ${res.body}');
    }
  }

  // --------------------------------------------------
  // ✅ 닉네임 중복 체크 / 저장
  //   GET  /game/nickname/check?nickname=...&uid=...
  //   POST /game/nickname/set { uid, nickname }
  // --------------------------------------------------

  static Future<bool> checkNickname({
    required String nickname,
    String? uid,
  }) async {
    final n = nickname.trim();
    if (n.isEmpty) return false;

    final qp = <String, String>{'nickname': n};
    final u = (uid ?? '').trim();
    if (u.isNotEmpty) qp['uid'] = u;

    final uri = Uri.parse('$_baseUrl/game/nickname/check')
        .replace(queryParameters: qp);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('닉네임 확인 실패: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);
    return (data['available'] == true);
  }

  static Future<void> setNickname({
    required String uid,
    required String nickname,
  }) async {
    final u = uid.trim();
    final n = nickname.trim();
    if (u.isEmpty) throw Exception('uid is required');
    if (n.isEmpty) throw Exception('nickname is required');

    final uri = Uri.parse('$_baseUrl/game/nickname/set');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'uid': u, 'nickname': n}),
    );

    if (res.statusCode == 409) {
      throw Exception('nickname already taken');
    }

    if (res.statusCode != 200) {
      throw Exception('닉네임 저장 실패: ${res.statusCode} ${res.body}');
    }
  }



  // --------------------------------------------------
  // ✅ 공통: 게임/랭킹/토론용 심볼 키 정규화
  // - "AAPL.US" -> "AAPL"
  // - "TSLA"    -> "TSLA"
  // --------------------------------------------------
  static String normalizeSymbolKey(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return s;
    final idx = s.indexOf('.');
    if (idx <= 0) return s;
    return s.substring(0, idx);
  }




  // --------------------------------------------------
  // 2) 주문(매수/매도) 전송
  //    POST /game/trade  → 서버 main.py: game_trade() → process_trade()
  //
  //    mode:
  //      - "game" : 투자게임
  //      - "log"  : 매매일지
  //      - "normal" : 예전 호환용 (가능하면 사용 지양)
  // --------------------------------------------------
  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<void> _ensureGamePriceReady(String symbolRaw) async {
    // ✅ 최근 며칠만 호출해도 서버가 prices_daily 채우는 용도라 충분
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 10));
    final to = now;

    final uri = Uri.parse('$_baseUrl/prices').replace(queryParameters: {
      'symbol_raw': symbolRaw,
      'from': _fmtDate(from),
      'to': _fmtDate(to),
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('가격 수집(/prices) 실패: ${res.statusCode} ${res.body}');
    }
  }

  static String _fmtDateTime(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    return '$y-$m-$day' 'T' '$h:$min:$s';
  }

  static Future<Map<String, dynamic>> sendTrade({
    required String uid,
    required String symbol,
    required String symbolRaw,
    required String side,
    required int quantity,
    required double price,
    required DateTime tradeDate,
    required DateTime tradeTime,
    required String mode,
    String? memo,
    double fee = 0.0,
  }) async {
    if (mode == 'game') {
      await _ensureGamePriceReady(symbolRaw);
    }

    final uri = Uri.parse('$_baseUrl/game/trade');

    final body = jsonEncode({
      'uid': uid,
      'mode': mode,
      'symbol': symbol,
      'side': side,
      'quantity': quantity,
      'price': price,
      'fee': fee,
      'trade_date': _fmtDate(tradeDate),
      'trade_time': _fmtDateTime(tradeTime),
      'memo': memo,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('주문 전송 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }


  // --------------------------------------------------
  // 3) 심볼별 요약 정보 조회
  //    GET /game/symbol_summary  → 서버 main.py: game_symbol_summary()
  //    👉 앱에서 계산하던 TradeLogSummary 를
  //       서버 계산값으로 대체할 때 이 함수 사용
  // --------------------------------------------------
  static Future<Map<String, dynamic>> fetchSymbolSummary({
    required String uid,      // 동일한 게임 계좌 UID
    required String symbol,   // 예: 'AAPL.US'
    String mode = "game",
  }) async {
    // 쿼리파라미터는 Uri.replace 로 안전하게 인코딩
    final uri = Uri.parse('$_baseUrl/game/symbol_summary').replace(
      queryParameters: {
        'uid': uid,
        'symbol': symbol,
        'mode': mode,
      },
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception(
        '심볼 요약 조회 실패: ${res.statusCode} ${res.body}',
      );
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --------------------------------------------------
  // 4) 계좌 상태 조회
  //    GET /game/account
  // --------------------------------------------------
  static Future<Map<String, dynamic>> fetchAccount({
    required String uid,
    required String mode, // "log" or "game"
  }) async {
    final uri = Uri.parse('$_baseUrl/game/account').replace(
      queryParameters: {'uid': uid, 'mode': mode},
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('계좌 조회 실패: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --------------------------------------------------
  // 5) 초기 투자금 변경 (log만 허용)
  //    POST /game/set_initial_balance
  // --------------------------------------------------
  static Future<Map<String, dynamic>> setInitialBalance({
    required String uid,
    required String mode, // ✅ 추가: "log" / "game"
    required double initialBalance,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/set_initial_balance');

    final body = jsonEncode({
      'uid': uid,
      'mode': mode, // ✅ 고정 'log' 제거
      'initial_balance': initialBalance,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('초기 투자금 변경 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --------------------------------------------------
// ✅ 7) 개별 거래 삭제
//    POST /game/trade/delete
// --------------------------------------------------
  static Future<Map<String, dynamic>> deleteTrade({
    required int tradeId,
    required String uid,
    required String mode, // "log" / "game"
  }) async {
    final uri = Uri.parse('$_baseUrl/game/trade/delete');

    final body = jsonEncode({
      'trade_id': tradeId,
      'uid': uid,
      'mode': mode,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('거래 삭제 실패: ${res.statusCode} ${res.body}');
    }

    final text = res.body.trim();
    if (text.isEmpty) return {'ok': true};
    return jsonDecode(text) as Map<String, dynamic>;
  }


// --------------------------------------------------
// ✅ 6) 거래 메모 수정
//    POST /game/trade/update_memo
// --------------------------------------------------
  static Future<Map<String, dynamic>> updateTradeMemo({
    required int tradeId,
    required String uid,
    required String mode, // "log" / "game"
    String? memo,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/trade/update_memo');

    final body = jsonEncode({
      'trade_id': tradeId,
      'uid': uid,
      'mode': mode,
      'memo': memo,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('메모 수정 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --------------------------------------------------
  // ✅ 8) 거래내역 조회 (거래내역 페이지와 같은 데이터 재사용)
  //    GET /game/trades?uid=...&mode=...&symbol=...
  //
  // ⚠️ 만약 서버가 /game/trade_logs 또는 /trades 등 다른 경로면
  //    아래 path 한 줄만 바꾸면 됨.
  // --------------------------------------------------
  static Future<List<Map<String, dynamic>>> fetchTrades({
    required String uid,
    required String mode,   // "log" / "game"
    required String symbol, // "AAPL.US"
  }) async {
    final uri = Uri.parse('$_baseUrl/game/trades').replace(
      queryParameters: {
        'uid': uid,
        'mode': mode,
        'symbol': symbol,
      },
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('거래내역 조회 실패: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);

    // 서버가 바로 List를 주는 경우
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }

    // 서버가 {"trades":[...]} 형태로 주는 경우
    if (decoded is Map && decoded['trades'] is List) {
      return (decoded['trades'] as List).cast<Map<String, dynamic>>();
    }

    return [];
  }

  // --------------------------------------------------
  // ✅ 토론 목록 조회
  //    GET /discussion/posts?uid=...&symbol=...&limit=...
  // --------------------------------------------------
  static Future<List<Map<String, dynamic>>> fetchDiscussionPosts({
    required String uid,
    required String symbol, // ✅ "AAPL" (normalizeSymbolKey 적용 권장)
    int limit = 50,
  }) async {
    final sym = normalizeSymbolKey(symbol);

    final uri = Uri.parse('$_baseUrl/discussion/posts').replace(
      queryParameters: {
        'uid': uid,
        'symbol': sym,
        'limit': '$limit',
      },
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('토론 조회 실패: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  // --------------------------------------------------
  // ✅ 토론 글 작성
  //    POST /discussion/post
  // --------------------------------------------------
  static Future<Map<String, dynamic>> createDiscussionPost({
    required String uid,
    required String symbol, // ✅ "AAPL" (normalizeSymbolKey 적용 권장)
    required String bodyText,
  }) async {
    final sym = normalizeSymbolKey(symbol);

    final uri = Uri.parse('$_baseUrl/discussion/post');

    final body = jsonEncode({
      'uid': uid,
      'symbol': sym,
      'body': bodyText,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('토론 작성 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --------------------------------------------------
  // ✅ 토론 댓글 신고
  //    POST /discussion/report
  // --------------------------------------------------
  static Future<Map<String, dynamic>> reportDiscussionPost({
    required String uid,
    required int postId,
    String? reason,
  }) async {
    final uri = Uri.parse('$_baseUrl/discussion/report');

    final body = jsonEncode({
      'uid': uid,
      'post_id': postId,
      'reason': (reason ?? '').trim(),
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('댓글 신고 실패: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {'ok': true};
  }
  // --------------------------------------------------
  // ✅ 관리자 전용: 신고 목록 조회
  //    GET /admin/discussion/reports?limit=...
  // --------------------------------------------------
  static Future<List<Map<String, dynamic>>> fetchAdminDiscussionReports({
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_baseUrl/admin/discussion/reports').replace(
      queryParameters: {
        'limit': '$limit',
      },
    );

    final headers = await _buildAdminHeaders();

    final res = await http.get(uri, headers: headers);

    if (res.statusCode != 200) {
      throw Exception('관리자 신고 목록 조회 실패: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }

  // --------------------------------------------------
  // ✅ 관리자 전용: 댓글 숨김 / 해제
  //    POST /admin/discussion/hide
  // --------------------------------------------------
  static Future<Map<String, dynamic>> adminHideDiscussionPost({
    required int postId,
    bool hidden = true,
  }) async {
    final uri = Uri.parse('$_baseUrl/admin/discussion/hide');
    final headers = await _buildAdminHeaders();

    final body = jsonEncode({
      'post_id': postId,
      'hidden': hidden,
    });

    final res = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('댓글 숨김 처리 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --------------------------------------------------
  // ✅ 관리자 전용: 신고 삭제
  //    POST /admin/discussion/report/delete
  // --------------------------------------------------
  static Future<Map<String, dynamic>> adminDeleteDiscussionReport({
    required int reportId,
  }) async {
    final uri = Uri.parse('$_baseUrl/admin/discussion/report/delete');
    final headers = await _buildAdminHeaders();

    final body = jsonEncode({
      'report_id': reportId,
    });

    final res = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('신고 삭제 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

// --------------------------------------------------
// ✅ 관리자 전용: 사용자 경고 / 차단 / 해제
//    POST /admin/user/moderate
// --------------------------------------------------
  static Future<Map<String, dynamic>> adminModerateUser({
    required String uid,
    required String action, // warn / ban_1d / ban_7d / perm_ban / unban
  }) async {
    final uri = Uri.parse('$_baseUrl/admin/user/moderate');
    final headers = await _buildAdminHeaders();

    final body = jsonEncode({
      'uid': uid,
      'action': action,
    });

    final res = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('사용자 제재 실패: ${res.statusCode} ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

}


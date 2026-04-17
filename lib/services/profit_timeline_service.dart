// 📄 lib/services/profit_timeline_service.dart
//
// ✅ 서버 기준 버전
// - 로컬 SharedPreferences(trade_logs, invest_amount) 기반 계산 제거
// - Yahoo 캔들 로딩 제거
// - 서버의 equity snapshot 타임라인(/profit/equity-timeline)만 사용

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/trade_mode_toggle.dart';

/// 차트에서 사용하는 한 점(Point)
/// - totalEquity : 전체 포트폴리오 평가 금액(달러)
/// - totalGrowth : 전체 성장률 (1.0 = 100% 원금)
/// - symbolEquity: 심볼별 평가 금액 (서버 응답에 없으면 빈 dict)
/// - symbolGrowth: 심볼별 성장률 (서버 응답에 없으면 빈 dict)
class ProfitPoint {
  final DateTime date;
  final double totalEquity;
  final double totalGrowth;
  final Map<String, double> symbolEquity;
  final Map<String, double> symbolGrowth;

  ProfitPoint({
    required this.date,
    required this.totalEquity,
    required this.totalGrowth,
    required this.symbolEquity,
    required this.symbolGrowth,
  });
}

class ProfitTimelineService {
  // ✅ 서버 주소 (GameServerApi와 동일)
  static const String _baseUrl = "http://46.224.127.151:8000";

  /// 🔥 수익률 타임라인 (서버에서 가져오기)
  ///
  /// 서버: GET /profit/equity-timeline?uid=...&mode=game|log
  /// 응답: [
  ///   { "date":"2026-01-02", "equity":100249.5, "profit_rate":0.0025, ... },
  ///   ...
  /// ]
  static Future<List<ProfitPoint>> buildTimeline({
    TradeMode mode = TradeMode.log,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ 서버 모드 매핑
    final String serverMode = (mode == TradeMode.game) ? "game" : "log";

    // ✅ uid: uid 우선, 없으면 game_uid fallback
    final String uid =
    (prefs.getString('uid') ?? '').trim().isNotEmpty
        ? (prefs.getString('uid') ?? '').trim()
        : (prefs.getString('game_uid') ?? '').trim();

    if (uid.isEmpty) {
      debugPrint('[ProfitTimelineService] uid empty -> return []');
      return [];
    }

    final uri = Uri.parse('$_baseUrl/profit/equity-timeline').replace(
      queryParameters: {
        'uid': uid,
        'mode': serverMode,
      },
    );

    try {
      final res = await http.get(uri);

      if (res.statusCode != 200) {
        throw Exception('server ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);

      if (decoded is! List) {
        debugPrint('[ProfitTimelineService] invalid response: ${res.body}');
        return [];
      }

      final List<ProfitPoint> points = [];

      for (final row in decoded) {
        if (row is! Map) continue;

        final map = Map<String, dynamic>.from(row as Map);

        final dateStr = (map['date'] ?? '').toString().trim();
        if (dateStr.isEmpty) continue;

        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;

        // 서버 스냅샷은 equity 키 사용
        final equityNum = map['equity'];
        final double equity =
        (equityNum is num) ? equityNum.toDouble() : 0.0;

        // profit_rate: 서버에서 0.0025(=0.25%) 형태로 내려오는 값 기준
        final pr = map['profit_rate'];
        final double profitRate =
        (pr is num) ? pr.toDouble() : 0.0;

        // ✅ 차트에서 쓰는 totalGrowth는 1.0=원금
        final double totalGrowth = 1.0 + profitRate;

        points.add(
          ProfitPoint(
            date: DateTime(date.year, date.month, date.day),
            totalEquity: equity,
            totalGrowth: totalGrowth,
            symbolEquity: const {}, // 서버 응답에 종목별이 없으므로 빈 dict
            symbolGrowth: const {},
          ),
        );
      }

      // 서버가 ASC로 주지만 안전하게 정렬
      points.sort((a, b) => a.date.compareTo(b.date));

      debugPrint(
        '[ProfitTimelineService] loaded ${points.length} points '
            '(uid=$uid mode=$serverMode)',
      );

      return points;
    } catch (e) {
      debugPrint('[ProfitTimelineService] error: $e');
      return [];
    }
  }
}

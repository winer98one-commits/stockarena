// 📄 lib/services/trading_calendar_service.dart
//
// 기능 요약
// ------------------------------------------------------
// 1) 서버 holidays.json 다운로드 (가능하면 서버 우선)
// 2) 오프라인 → 로컬 JSON 사용
// 3) 로컬도 없으면 assets 기본 JSON
// 4) JSON에 없는 날짜 → 내부 규칙(미국/한국)으로 자동 휴일 계산
// ------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum MarketSessionState {
  open,
  closedWeekend,
  closedHoliday,
  closedOffHours,
}

class TradingCalendarService {
  TradingCalendarService._();

  static bool _initialized = false;

  static const String _localFileName = 'holidays.json';

  // ⭐ NEW: 실제 서버 주소 입력할 곳
  static const String _remoteUrl =
      'https://myserver.com/api/holidays.json';

  static final Set<DateTime> _usHolidays = {};
  static final Set<DateTime> _krHolidays = {};

  /// 🇰🇷 한국 종목 여부 판단
  static bool _isKoreanSymbol(String symbol) {
    if (symbol.endsWith('.KS')) return true;
    if (symbol.endsWith('.KQ')) return true;
    if (symbol.endsWith('.KO')) return true;
    return false;
  }

  // ------------------------------------------------------
  // 🔸 특정 날짜(yyyy-MM-dd 기준)가 미국 휴일/주말인지 확인하는 함수
  //    - "지금 시간"이 아니라, 매매일지에서 사용자가 고른 날짜 기준
  // ------------------------------------------------------
  static Future<bool> isUsHolidayDate(DateTime dateLocal) async {
    await init(); // 혹시라도 아직 초기화 안 되었으면

    final d = _dateOnly(dateLocal);

    // 주말이면 바로 휴일
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      return true;
    }

    // JSON에 있거나, 내부 규칙에 걸리면 휴일
    if (_usHolidays.contains(d)) return true;
    if (_isUsAutoHoliday(d)) return true;

    return false;
  }


  // ⭐ NEW: 내부 계산용 미국 휴일 규칙 (fallback)
  static final Map<String, DateTime Function(int)> _usRules = {
    "new_year": (y) => DateTime(y, 1, 1),
    "independence": (y) => DateTime(y, 7, 4),
    "christmas": (y) => DateTime(y, 12, 25),
  };

  // ⭐ NEW: 한국 휴일 기본 규칙 (필요 시 확장 가능)
  static final Map<String, DateTime Function(int)> _krRules = {
    "new_year": (y) => DateTime(y, 1, 1),
    "child_day": (y) => DateTime(y, 5, 5),
  };

  // ------------------------------------------------------
  // 초기화
  // ------------------------------------------------------
  static Future<void> init() async {
    if (_initialized) return;

    try {
      bool loaded = await _loadFromLocalFile();

      if (!loaded) {
        await _loadFromAssetAndSave();
      }

      await _updateFromRemoteIfAvailable();
    } catch (e) {
      // 오류 무시
    }

    _initialized = true;
  }

  // ------------------------------------------------------
  // 내부 유틸
  // ------------------------------------------------------
  static DateTime _dateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  static DateTime? _parseDate(String s) {
    try {
      final p = s.split('-');
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  static void _applyHolidayJson(Map<String, dynamic> jsonMap) {
    _usHolidays.clear();
    _krHolidays.clear();

    final us = (jsonMap['us'] as List?) ?? [];
    final kr = (jsonMap['kr'] as List?) ?? [];

    for (final e in us) {
      final dt = _parseDate(e);
      if (dt != null) _usHolidays.add(_dateOnly(dt));
    }

    for (final e in kr) {
      final dt = _parseDate(e);
      if (dt != null) _krHolidays.add(_dateOnly(dt));
    }
  }

  static Future<File> _getLocalFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_localFileName');
  }

  // ------------------------------------------------------
  // 로컬 로딩
  // ------------------------------------------------------
  static Future<bool> _loadFromLocalFile() async {
    try {
      final file = await _getLocalFile();
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      final jsonMap = json.decode(content) as Map<String, dynamic>;
      _applyHolidayJson(jsonMap);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------
  // assets 기본 JSON → 로컬 저장
  // ------------------------------------------------------
  static Future<void> _loadFromAssetAndSave() async {
    try {
      final asset = await rootBundle.loadString(
          'assets/holidays/holidays.json');
      final jsonMap = json.decode(asset) as Map<String, dynamic>;
      _applyHolidayJson(jsonMap);

      final file = await _getLocalFile();
      await file.writeAsString(asset);
    } catch (_) {}
  }

  // ------------------------------------------------------
  // 서버 JSON 최신 업데이트
  // ------------------------------------------------------
  static Future<void> _updateFromRemoteIfAvailable() async {
    try {
      final uri = Uri.parse(_remoteUrl);
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final jsonMap = json.decode(resp.body);
        _applyHolidayJson(jsonMap);

        final file = await _getLocalFile();
        await file.writeAsString(resp.body);
      }
    } catch (_) {
      /* 무시 */
    }
  }

  // ------------------------------------------------------
  // ⭐ NEW 내부 자동 계산 휴일 Fallback (JSON에 없는 경우)
  // ------------------------------------------------------
  static bool _isUsAutoHoliday(DateTime date) {
    final y = date.year;
    for (final rule in _usRules.values) {
      if (_dateOnly(rule(y)) == _dateOnly(date)) return true;
    }
    return false;
  }

  static bool _isKrAutoHoliday(DateTime date) {
    final y = date.year;
    for (final rule in _krRules.values) {
      if (_dateOnly(rule(y)) == _dateOnly(date)) return true;
    }
    return false;
  }

  // ------------------------------------------------------
  // 미국 시장 판단
  // ------------------------------------------------------
  // ------------------------------------------------------
  // 미국 시장 판단
  // ------------------------------------------------------

  /// 📅 "이 날짜가 미국 시장 거래 가능한 날(영업일)이냐?"를 체크
  /// - 시간은 모두 버리고 날짜(YYYY-MM-DD)만 본다
  /// - DatePicker 의 selectableDayPredicate 에서 사용
  static bool isUsTradingDate(DateTime date) {
    final d = _dateOnly(date);

    // 1) 주말이면 거래 불가
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      return false;
    }

    // 2) JSON에 있는 휴일
    if (_usHolidays.contains(d)) return false;

    // 3) JSON에 없을 때 내부 규칙으로 잡은 휴일
    if (_isUsAutoHoliday(d)) return false;

    // 4) 그 외는 거래 가능
    return true;
  }

  /// 📅 한국 시장 거래 가능 날짜인지 (DatePicker용)
  static bool isKrTradingDate(DateTime dateLocal) {
    final d = _dateOnly(dateLocal);

    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      return false;
    }

    if (_krHolidays.contains(d)) return false;
    if (_isKrAutoHoliday(d)) return false;

    return true;
  }
  /// ⭐ 종목(symbol)에 따라 미국 / 한국 시장 휴일 자동 적용
  static bool isTradingDateForSymbol(DateTime date, String symbol) {
    if (_isKoreanSymbol(symbol)) {
      return isKrTradingDate(date);   // 🇰🇷 한국 주식이면 한국 휴일
    } else {
      return isUsTradingDate(date);   // 🇺🇸 나머지는 미국 휴일
    }
  }



  /// ⏱ 지금 시각(nowUtc)이 미국 시장 "거래일"인지 (날짜+시간 기준)
  static bool isUsTradingDay(DateTime nowUtc) {
    final ny = nowUtc.toLocal();
    final d = _dateOnly(ny);

    if (ny.weekday == DateTime.saturday ||
        ny.weekday == DateTime.sunday) {
      return false;
    }

    // JSON → 자동 계산 순서로 체크
    if (_usHolidays.contains(d)) return false;
    if (_isUsAutoHoliday(d)) return false;

    return true;
  }

  /// 정규장 시간(미국 동부 09:30 ~ 16:00)인지 확인
  static bool isUsRegularSession(DateTime nowUtc) {
    final ny = nowUtc.toLocal();
    final t = ny.hour + ny.minute / 60.0;
    return t >= 9.5 && t <= 16.0;
  }

  static MarketSessionState getUsSessionState(DateTime nowUtc) {
    final ny = nowUtc.toLocal();

    if (!isUsTradingDay(nowUtc)) {
      if (ny.weekday == DateTime.saturday ||
          ny.weekday == DateTime.sunday) {
        return MarketSessionState.closedWeekend;
      }

      return MarketSessionState.closedHoliday;
    }

    if (!isUsRegularSession(nowUtc)) {
      return MarketSessionState.closedOffHours;
    }

    return MarketSessionState.open;
  }


  // ------------------------------------------------------
  // 한국 시장 판단
  // ------------------------------------------------------
  static bool isKrTradingDay(DateTime nowLocal) {
    final d = _dateOnly(nowLocal);

    if (nowLocal.weekday == DateTime.saturday ||
        nowLocal.weekday == DateTime.sunday) {
      return false;
    }

    // JSON → 자동 계산 순서
    if (_krHolidays.contains(d)) return false;
    if (_isKrAutoHoliday(d)) return false;

    return true;
  }

  static bool isKrRegularSession(DateTime nowLocal) {
    final t = nowLocal.hour + nowLocal.minute / 60.0;
    return t >= 9.0 && t <= 15.5;
  }

  static MarketSessionState getKrSessionState(DateTime nowLocal) {
    if (!isKrTradingDay(nowLocal)) {
      if (nowLocal.weekday == DateTime.saturday ||
          nowLocal.weekday == DateTime.sunday) {
        return MarketSessionState.closedWeekend;
      }
      return MarketSessionState.closedHoliday;
    }

    if (!isKrRegularSession(nowLocal)) {
      return MarketSessionState.closedOffHours;
    }

    return MarketSessionState.open;
  }
}

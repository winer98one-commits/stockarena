// 📄 lib/services/trading_date_picker.dart
import 'package:flutter/material.dart';
import 'trading_calendar_service.dart';

/// 미국 시장 기준으로 "거래 가능한 날짜만 선택"할 수 있는 달력
Future<DateTime?> pickUsTradingDate(BuildContext context,
    {DateTime? initialDate}) async {
  // 휴일/주말 정보 로딩
  await TradingCalendarService.init();

  final now = DateTime.now();
  final init = initialDate ?? now;

  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 5),
    // 🔴 여기서 '선택 가능한 날'을 필터링
    selectableDayPredicate: (day) {
      // true  → 선택 가능(영업일)
      // false → 선택 불가(주말/휴일)
      return TradingCalendarService.isUsTradingDate(day);
    },
    helpText: '미국 시장 거래일 선택',
  );
}

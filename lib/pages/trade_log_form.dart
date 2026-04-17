import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/trade_limit_service.dart';
import '../widgets/trade_mode_toggle.dart';
import '../services/trading_calendar_service.dart';
import '../services/trade_calc_service.dart';
import '../services/game_server_api.dart';
import 'package:flutter/foundation.dart';
import '../services/trade_date_price_lookup_service.dart';
import 'login_page.dart';

class TradeLogForm extends StatefulWidget {
  final TradeMode mode;
  final double? currentPrice;
  final VoidCallback? onSaved;
  final String? symbol;
  final String? companyName;
  final double? selectedDateHigh;
  final double? selectedDateLow;
  final Function(DateTime)? onDateChanged;

  // ✅ 추가: 현재가를 다시 불러오라고 부모에게 요청하는 콜백
  final Future<double?> Function()? onRefreshPrice;

  const TradeLogForm({
    super.key,
    required this.mode,
    this.currentPrice,
    this.onSaved,
    this.symbol,
    this.companyName,
    this.selectedDateHigh,
    this.selectedDateLow,
    this.onDateChanged,
    this.onRefreshPrice,
  });

  @override
  State<TradeLogForm> createState() => _TradeLogFormState();
}

class _TradeLogFormState extends State<TradeLogForm> {
  late int _selectedYear;
  final TextEditingController _monthController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _dayController = TextEditingController();

  TimeOfDay _selectedTime = TimeOfDay.now();

  DateTime? _lastPriceRefreshAt;
  bool _didRequestInitialPrice = false;

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _investController = TextEditingController();

  // 날짜 기준 상태 표시용
  double? _statusQty;
  double? _statusAvgPrice;
  double? _statusProfitRate;
  double? _statusAvailable;
  double? _statusTotalAmount;
  double? _statusTotalProfitRate;
  List<DateSymbolPosition> _statusPositions = [];
  double? _holdingQtyAsOf;

  bool _isDateValid = true;
  bool _isHoliday = false;

  double? _currentPrice;
  String _tradeType = '매수';
  List<String> _logs = [];

  bool _isPriceValid = true;
  double _dayLow = 0.0;
  double _dayHigh = 0.0;

  bool _isSearchingDatePrice = false;
  double? _searchedDateClose;
  double? _searchedDateLow;
  double? _searchedDateHigh;

  bool _isInvestButtonActive = false;

  bool get _canRefreshPrice {
    if (_lastPriceRefreshAt == null) return true;
    final diff = DateTime.now().difference(_lastPriceRefreshAt!);
    return diff >= const Duration(minutes: 3);
  }

  // ✅ 검색 결과 우선, 없으면 부모에서 넘어온 값 사용
  double? get _effectiveSelectedDateHigh {
    final h = _searchedDateHigh;
    if (h != null && h > 0) return h;

    final wh = widget.selectedDateHigh;
    if (wh != null && wh > 0) return wh;

    if (_dayHigh > 0) return _dayHigh;
    return null;
  }

  double? get _effectiveSelectedDateLow {
    final l = _searchedDateLow;
    if (l != null && l > 0) return l;

    final wl = widget.selectedDateLow;
    if (wl != null && wl > 0) return wl;

    if (_dayLow > 0) return _dayLow;
    return null;
  }

  bool get _hasValidOhlcForSelectedDate {
    final h = _effectiveSelectedDateHigh;
    final l = _effectiveSelectedDateLow;
    if (h == null || l == null) return false;
    if (h <= 0 || l <= 0) return false;
    return true;
  }

  bool get _isCryptoSymbol {
    final s = widget.symbol ?? '';
    return s.contains('-USD');
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();

    _selectedYear = now.year;
    _yearController.text = now.year.toString();
    _monthController.text = now.month.toString();
    _dayController.text = now.day.toString();
    _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);

    _applyIncomingPrice(widget.currentPrice, force: true);

    _loadLogs();
    _loadInvestAmount();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _validateDate(force: true);
      await _ensureInitialPrice();
    });
  }

  @override
  void dispose() {
    _monthController.dispose();
    _yearController.dispose();
    _dayController.dispose();
    _priceController.dispose();
    _memoController.dispose();
    _qtyController.dispose();
    _investController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TradeLogForm oldWidget) {
    super.didUpdateWidget(oldWidget);

    final symbolChanged = (oldWidget.symbol ?? '') != (widget.symbol ?? '');
    final priceChanged = oldWidget.currentPrice != widget.currentPrice;
    final modeChanged = oldWidget.mode != widget.mode;

    if (symbolChanged) {
      _didRequestInitialPrice = false;

      setState(() {
        _priceController.clear();
        _currentPrice = null;
        _isPriceValid = true;
        _holdingQtyAsOf = null;
        _searchedDateClose = null;
        _searchedDateLow = null;
        _searchedDateHigh = null;
        _dayLow = 0.0;
        _dayHigh = 0.0;
        _clearStatusForInvalidDate();
      });

      if (widget.currentPrice != null && widget.currentPrice! > 0) {
        setState(() {
          _applyIncomingPrice(widget.currentPrice!, force: true);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ensureInitialPrice();
        });
      }

      _validateDate(force: true);
    }

    if (priceChanged && widget.currentPrice != null && widget.currentPrice! > 0) {
      setState(() {
        _applyIncomingPrice(
          widget.currentPrice!,
          force: widget.mode == TradeMode.game || symbolChanged,
        );
      });

      _updateStatusForDate();
    }

    if (modeChanged) {
      _didRequestInitialPrice = false;

      _resetAllInputs();
      _loadInvestAmount();
      _loadLogs();

      setState(() {
        _applyIncomingPrice(widget.currentPrice, force: true);
      });

      _validateDate(force: true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureInitialPrice();
      });
    }

    if (oldWidget.selectedDateHigh != widget.selectedDateHigh ||
        oldWidget.selectedDateLow != widget.selectedDateLow) {
      final newValid = _validatePriceRange(_priceController.text);

      bool shouldSetMidPrice = false;
      String? midPriceStr;

      if (widget.mode == TradeMode.log &&
          widget.selectedDateHigh != null &&
          widget.selectedDateLow != null) {
        final midPrice =
            (widget.selectedDateHigh! + widget.selectedDateLow!) / 2.0;
        midPriceStr = midPrice.toStringAsFixed(2);

        final currentStr = _priceController.text.trim();

        String? oldMidStr;
        if (oldWidget.selectedDateHigh != null &&
            oldWidget.selectedDateLow != null) {
          final oldMid =
              (oldWidget.selectedDateHigh! + oldWidget.selectedDateLow!) / 2.0;
          oldMidStr = oldMid.toStringAsFixed(2);
        }

        if (currentStr.isEmpty ||
            !_isPriceValid ||
            (oldMidStr != null && currentStr == oldMidStr)) {
          shouldSetMidPrice = true;
        }
      }

      setState(() {
        if (shouldSetMidPrice && midPriceStr != null) {
          _priceController.text = midPriceStr;
          _isPriceValid = true;
        } else {
          _isPriceValid = newValid;
        }
      });
    }
  }

  Future<void> _handleRefreshPrice() async {
    if (widget.onRefreshPrice == null) return;

    if (!_canRefreshPrice) {
      final diff = DateTime.now().difference(_lastPriceRefreshAt!);
      final remain = const Duration(minutes: 3) - diff;
      final m = remain.inMinutes;
      final s = remain.inSeconds % 60;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '가격 새로고침은 3분마다 가능합니다. 남은 시간: ${m}분 ${s}초',
          ),
        ),
      );
      return;
    }

    final newPrice = await widget.onRefreshPrice!();
    if (!mounted) return;

    if (newPrice != null) {
      setState(() {
        _applyIncomingPrice(newPrice, force: true);
        _lastPriceRefreshAt = DateTime.now();
      });

      await _updateStatusForDate();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격을 불러오지 못했습니다.')),
      );
    }
  }

  void _resetAllInputs() {
    final now = DateTime.now();

    setState(() {
      _selectedYear = now.year;
      _yearController.text = now.year.toString();
      _monthController.text = now.month.toString();
      _dayController.text = now.day.toString();
      _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);

      _priceController.clear();
      _qtyController.clear();
      _memoController.clear();

      _currentPrice = null;
      _tradeType = '매수';

      _isPriceValid = true;
      _isDateValid = true;

      _searchedDateClose = null;
      _searchedDateLow = null;
      _searchedDateHigh = null;
      _dayLow = 0.0;
      _dayHigh = 0.0;

      _clearStatusForInvalidDate();
    });

    _applyIncomingPrice(widget.currentPrice, force: true);
    widget.onDateChanged?.call(now);
  }





  void _clearStatusForInvalidDate() {
    _statusQty = null;
    _statusAvgPrice = null;
    _statusProfitRate = null;
    _statusAvailable = null;
    _statusTotalAmount = null;
    _statusTotalProfitRate = null;
    _statusPositions = [];
  }

  int _daysInMonth(int year, int month) {
    if (month < 1 || month > 12) return 0;
    final nextMonth =
    (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final lastDayOfMonth = nextMonth.subtract(const Duration(days: 1));
    return lastDayOfMonth.day;
  }

  Future<void> _validateDate({bool force = false}) async {
    if (!force && widget.mode == TradeMode.game) {
      return;
    }

    final year = int.tryParse(_yearController.text);
    final month = int.tryParse(_monthController.text);
    final day = int.tryParse(_dayController.text);

    if (year == null || month == null || day == null) {
      setState(() {
        _isDateValid = false;
        _isHoliday = false;
        _clearStatusForInvalidDate();
        _holdingQtyAsOf = null;
      });
      return;
    }

    final maxDay = _daysInMonth(year, month);
    if (maxDay == 0 || day < 1 || day > maxDay) {
      setState(() {
        _isDateValid = false;
        _isHoliday = false;
        _clearStatusForInvalidDate();
        _holdingQtyAsOf = null;
      });
      return;
    }

    final date = DateTime(year, month, day);

    await TradingCalendarService.init();

    final symbol = widget.symbol ?? '';
    final isTrading =
    TradingCalendarService.isTradingDateForSymbol(date, symbol);

    setState(() {
      _isDateValid = true;
      _isHoliday = !isTrading;
      _selectedYear = year;
    });

    widget.onDateChanged?.call(date);
    await _updateStatusForDate();
  }

  Future<void> _onDateInputChanged() async {
    setState(() {
      _priceController.clear();
      _isPriceValid = true;

      _searchedDateClose = null;
      _searchedDateLow = null;
      _searchedDateHigh = null;
      _dayLow = 0.0;
      _dayHigh = 0.0;
    });

    await _validateDate();
  }

  String _formatNumber(String s) {
    if (s.isEmpty) return '';
    final number = double.tryParse(s.replaceAll(',', ''));
    if (number == null) return s;
    return number.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
    );
  }

  Future<void> _pickTradeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (picked == null) return;

    setState(() {
      _selectedTime = picked;
    });
  }

  void _applyIncomingPrice(double? price, {bool force = false}) {
    if (price == null || price <= 0) return;

    _currentPrice = price;

    final bool shouldWriteText =
        force ||
            _priceController.text.trim().isEmpty ||
            (widget.mode == TradeMode.game);

    if (shouldWriteText) {
      if (_priceController.text.isEmpty) {
        _priceController.text = price.toStringAsFixed(2);
      }
    }

    _isPriceValid = _validatePriceRange(_priceController.text);
  }

  Future<void> _searchPriceForSelectedDate() async {
    if (widget.symbol == null || widget.symbol!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종목을 먼저 선택해주세요.')),
      );
      return;
    }

    await _validateDate(force: true);

    if (!_isDateValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('날짜를 다시 확인해주세요.')),
      );
      return;
    }

    final year = int.tryParse(_yearController.text);
    final month = int.tryParse(_monthController.text);
    final day = int.tryParse(_dayController.text);

    if (year == null || month == null || day == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('날짜를 다시 확인해주세요.')),
      );
      return;
    }

    final targetDate = DateTime(year, month, day);

    setState(() {
      _isSearchingDatePrice = true;
    });

    try {
      final result = await TradeDatePriceLookupService.findByDate(
        symbol: widget.symbol!,
        targetDate: targetDate,
        period: '1y',
      );

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _searchedDateClose = null;
          _searchedDateLow = null;
          _searchedDateHigh = null;
          _dayLow = 0.0;
          _dayHigh = 0.0;
          _priceController.clear();
          _isPriceValid = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('해당 날짜의 주가를 찾지 못했습니다.')),
        );
        return;
      }

      final double midPrice = (result.high + result.low) / 2.0;

      setState(() {
        _searchedDateClose = result.close;
        _searchedDateLow = result.low;
        _searchedDateHigh = result.high;

        _dayLow = result.low;
        _dayHigh = result.high;
        _currentPrice = midPrice;

        _priceController.text = midPrice.toStringAsFixed(2);
        _isPriceValid = _validatePriceRange(_priceController.text);
      });

      await _updateStatusForDate();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '검색 완료: 중간값 ${midPrice.toStringAsFixed(2)} / '
                '고가 ${result.high.toStringAsFixed(2)} / '
                '저가 ${result.low.toStringAsFixed(2)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('날짜별 주가 조회 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSearchingDatePrice = false;
      });
    }
  }

  Widget _buildDialogDateField(
      TextEditingController controller,
      String suffix,
      ) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Color(0xFF111111),
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        suffixText: suffix,
        suffixStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF666666),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD9DEE5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD9DEE5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF9AA4B2)),
        ),
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
    );
  }
  Future<void> _openDateSearchDialog() async {
    final yearCtrl = TextEditingController(text: _yearController.text);
    final monthCtrl = TextEditingController(text: _monthController.text);
    final dayCtrl = TextEditingController(text: _dayController.text);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                '날짜 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFD9DEE5),
                        ),
                      ),
                      child: const Text(
                        '오늘부터 1년 이내 날짜만 선택',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDialogDateField(yearCtrl, '년'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDialogDateField(monthCtrl, '월'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDialogDateField(dayCtrl, '일'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

// ✅ 시간 선택 UI (여기에 추가)
                    Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Text(
                            '시간',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _selectedTime,
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedTime = picked;
                                });
                              }
                            },
                            child: Container(
                              height: 42,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F8FA),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFD9DEE5)),
                              ),
                              child: Text(
                                '${_selectedTime.hour.toString().padLeft(2, '0')}:'
                                    '${_selectedTime.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () async {
                          _yearController.text = yearCtrl.text.trim();
                          _monthController.text = monthCtrl.text.trim();
                          _dayController.text = dayCtrl.text.trim();

                          await _onDateInputChanged();
                          await _searchPriceForSelectedDate();

                          if (mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF009688),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '검색',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _ensureInitialPrice() async {
    if (_didRequestInitialPrice) return;
    if (widget.onRefreshPrice == null) return;
    if (widget.currentPrice != null && widget.currentPrice! > 0) {
      _applyIncomingPrice(widget.currentPrice, force: true);
      return;
    }
    if ((_currentPrice ?? 0) > 0) return;

    _didRequestInitialPrice = true;

    final newPrice = await widget.onRefreshPrice!();
    if (!mounted) return;

    if (newPrice != null && newPrice > 0) {
      setState(() {
        _applyIncomingPrice(newPrice, force: true);
        _lastPriceRefreshAt = DateTime.now();
      });

      await _updateStatusForDate();
    }
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = widget.mode == TradeMode.log ? 'trade_logs' : 'game_trade_logs';
    setState(() {
      _logs = prefs.getStringList(key) ?? [];
    });
  }

  Future<void> _saveInvestAmount() async {
    if (widget.mode == TradeMode.log) return;

    const fixed = 10000000.0;
    setState(() {
      _investController.text = _formatNumber(fixed.toStringAsFixed(0));
      _isInvestButtonActive = false;
    });
  }

  Future<void> _loadInvestAmount() async {
    if (widget.mode == TradeMode.log) {
      return;
    }

    const fixed = 10000000.0;
    setState(() {
      _investController.text = _formatNumber(fixed.toStringAsFixed(0));
      _isInvestButtonActive = false;
    });
  }

  Future<void> _updateStatusForDate() async {
    if (!_isDateValid) return;

    if (widget.symbol == null || widget.symbol!.isEmpty) {
      setState(() {
        _clearStatusForInvalidDate();
        _holdingQtyAsOf = null;
      });
      return;
    }

    final dateStr =
        '$_selectedYear-${_monthController.text}-${_dayController.text}';

    final status = await TradeLimitService.statusForDate(
      mode: widget.mode,
      symbol: widget.symbol!,
      dateStr: dateStr,
      currentPrice: _currentPrice ?? widget.currentPrice,
    );

    double? holdingQty;
    double? gameCashBalance;

    try {
      final prefs = await SharedPreferences.getInstance();
      final u = (prefs.getString('uid') ?? '').trim();
      final gu = (prefs.getString('game_uid') ?? '').trim();

      final String uid =
      (widget.mode == TradeMode.game) ? (gu.isNotEmpty ? gu : u) : (u.isNotEmpty ? u : gu);

      if (uid.isNotEmpty) {
        final modeStr = (widget.mode == TradeMode.game) ? 'game' : 'log';

        final trades = await GameServerApi.fetchTrades(
          uid: uid,
          mode: modeStr,
          symbol: widget.symbol!,
        );

        String normSym(String s) {
          final v = s.trim().toUpperCase();
          final i = v.indexOf('.');
          return (i >= 0) ? v.substring(0, i) : v;
        }

        final curSymRaw = (widget.symbol ?? '').trim();
        final curSymNorm = normSym(curSymRaw);

        final filteredTrades = trades.where((t) {
          final s = (t['symbol'] ?? '').toString();
          if (s.trim().isEmpty) return false;
          return normSym(s) == curSymNorm;
        }).toList();

        final asOf = (widget.mode == TradeMode.game)
            ? DateTime.now()
            : DateTime(
          _selectedYear,
          int.tryParse(_monthController.text) ?? 1,
          int.tryParse(_dayController.text) ?? 1,
        );

        holdingQty = TradeCalcService.holdingQtyAsOf(filteredTrades, asOf);

        if (widget.mode == TradeMode.game) {
          final res = await GameServerApi.fetchAccount(
            uid: uid,
            mode: modeStr,
          );

          final Map<String, dynamic> account =
          (res['account'] is Map<String, dynamic>)
              ? (res['account'] as Map<String, dynamic>)
              : res;

          final cb = account['cash_balance'];
          if (cb is num) {
            gameCashBalance = cb.toDouble();
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _statusQty = status.qty;
      _statusAvgPrice = status.avgPrice;
      _statusProfitRate = status.profitRate;

      _statusAvailable =
      (widget.mode == TradeMode.game && gameCashBalance != null)
          ? gameCashBalance
          : status.available;

      _statusPositions = status.positions;
      _statusTotalAmount = status.totalAmount;
      _statusTotalProfitRate = status.totalProfitRate;
      _holdingQtyAsOf = holdingQty;
    });
  }

  Future<void> _saveLog() async {
    const bool kCheckTradingTimeInGame = false;
    final bool useCurrentPriceInLog =
        widget.mode == TradeMode.log &&
            _yearController.text == DateTime.now().year.toString() &&
            _monthController.text == DateTime.now().month.toString() &&
            _dayController.text == DateTime.now().day.toString();

    if (kCheckTradingTimeInGame &&
        widget.mode == TradeMode.game &&
        widget.symbol != null &&
        widget.symbol!.isNotEmpty) {
      final okTime = TradeLimitService.isTradingTimeForSymbol(widget.symbol!);

      if (!okTime) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('⏰ 거래 시간 아님'),
            content: Text(
              '투자 게임 입력은 실제 거래 시간에만 가능합니다.\n\n'
                  '종목: ${widget.companyName ?? widget.symbol}\n'
                  '현재 시간에는 이 시장이 휴장 상태입니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }
    }

    if (widget.mode == TradeMode.log && !useCurrentPriceInLog) {
      if (!_isDateValid || !_hasValidOhlcForSelectedDate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 날짜를 잘못 입력했거나, 해당 날짜에 차트 데이터가 없습니다.'),
          ),
        );
        return;
      }
    }

    if (widget.mode == TradeMode.game || useCurrentPriceInLog) {
      if (widget.onRefreshPrice != null) {
        final newPrice = await widget.onRefreshPrice!();

        if (newPrice != null && newPrice > 0) {
          setState(() {
            _currentPrice = newPrice;
            _priceController.text = newPrice.toStringAsFixed(2);
            _isPriceValid = true;
          });
        }
      }

      final livePrice = _currentPrice ?? widget.currentPrice;
      if (livePrice == null || livePrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('현재가가 없어 거래할 수 없습니다.'),
          ),
        );
        return;
      }
    }

    if (!useCurrentPriceInLog && !_isPriceValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 매매 주가가 해당 일자의 저가~고가 범위를 벗어났습니다.'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final debugGameUid = prefs.getString('game_uid') ?? '(no-game-uid)';
    final debugLogKey =
    (widget.mode == TradeMode.log) ? 'trade_logs' : 'game_trade_logs';
    debugPrint(
      '[TradeLogForm._saveLog] mode=${widget.mode} '
          'symbol=${widget.symbol} '
          'logKey=$debugLogKey '
          'game_uid=$debugGameUid',
    );

    if (widget.mode == TradeMode.game &&
        widget.symbol != null &&
        widget.symbol!.isNotEmpty) {
      final cooldownKey = 'game_last_trade_ts_${widget.symbol}';
      final lastMillis = prefs.getInt(cooldownKey);
      final now = DateTime.now();

      if (lastMillis != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMillis);
        final diff = now.difference(last);

        const cooldown = Duration(hours: 1);

        if (diff < cooldown) {
          final remain = cooldown - diff;
          final minutesLeft = remain.inMinutes;
          final hoursLeft = minutesLeft ~/ 60;
          final remainMinutes = minutesLeft % 60;

          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('⏰ 거래 제한'),
              content: Text(
                '같은 종목은 마지막 거래 후 1시간이 지나야 다시 거래할 수 있습니다.\n\n'
                    '종목: ${widget.companyName ?? widget.symbol}\n'
                    '마지막 거래 시간: ${last.toString().substring(0, 16)}\n'
                    '남은 시간: 약 ${hoursLeft}시간 ${remainMinutes}분',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }

    final limit = await TradeLimitService.checkWithProfit(
      mode: widget.mode,
      symbol: widget.symbol ?? "N/A",
      dateStr:
      '$_selectedYear-${_monthController.text.padLeft(2, '0')}-${_dayController.text.padLeft(2, '0')}',
      type: _tradeType,
      price: double.tryParse(_priceController.text) ?? 0.0,
      qty: double.tryParse(_qtyController.text) ?? 0.0,
      currentPrice: _currentPrice ?? widget.currentPrice,
    );

    if (!limit.ok) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("❗ 투자한도 초과"),
          content: Text(
            "이번 거래를 포함하면 투자금을 초과합니다.\n\n"
                "📌 현재 자본 (실현+평가손익 반영): ${limit.equity.toStringAsFixed(0)}\n"
                "📌 이번 거래 포함 사용액: ${limit.usedAmount.toStringAsFixed(0)}",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("확인"),
            )
          ],
        ),
      );
      return;
    }

    final String newDate =
        '$_selectedYear-${_monthController.text.padLeft(2, '0')}-${_dayController.text.padLeft(2, '0')}';
    final double newPrice = double.tryParse(_priceController.text) ?? 0.0;
    final double newQty = double.tryParse(_qtyController.text) ?? 0.0;

    final int month = int.tryParse(_monthController.text) ?? 1;
    final int day = int.tryParse(_dayController.text) ?? 1;
    final DateTime tradeDate = DateTime(
      _selectedYear,
      month,
      day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final String serverMode = (widget.mode == TradeMode.game) ? "game" : "log";

    final String uid = (() {
      final u = (prefs.getString('uid') ?? '').trim();
      final gu = (prefs.getString('game_uid') ?? '').trim();

      if (widget.mode == TradeMode.log) {
        return u.isNotEmpty ? u : gu;
      }

      return gu.isNotEmpty ? gu : u;
    })();

    if (widget.symbol == null ||
        widget.symbol!.isEmpty ||
        newQty <= 0 ||
        newPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('심볼/수량/가격을 확인해 주세요.')),
      );
      return;
    }

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다. 로그인 페이지로 이동합니다.'),
        ),
      );

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
      );

      if (result == true) {
        await _saveLog();
      }
      return;
    }

    try {
      final side = (_tradeType == '매수') ? 'BUY' : 'SELL';

      debugPrint(
        '[SERVER ONLY SAVE] mode=$serverMode uid=$uid symbol=${widget.symbol} '
            'side=$side qty=${newQty.toInt()} price=$newPrice date=$newDate',
      );

      final memoText = _memoController.text.trim();

      await GameServerApi.sendTrade(
        uid: uid,
        symbol: widget.symbol!,
        symbolRaw: widget.symbol!,
        side: side,
        quantity: newQty.toInt(),
        price: newPrice,
        tradeDate: tradeDate,
        tradeTime: tradeDate,
        mode: serverMode,
        memo: memoText.isEmpty ? null : memoText,
      );

      widget.onSaved?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
      }
    } catch (e) {
      debugPrint('[SERVER ONLY SAVE] error: $e');
      final errorText = e.toString();

      if (errorText.contains('로그인이 필요합니다')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다. 로그인 페이지로 이동합니다.'),
            ),
          );

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LoginPage(),
            ),
          );

          if (result == true) {
            await _saveLog();
          }
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서버 저장 실패: $e')),
        );
      }
      return;
    }

    if (widget.mode == TradeMode.game &&
        widget.symbol != null &&
        widget.symbol!.isNotEmpty) {
      final now = DateTime.now();
      final cooldownKey = 'game_last_trade_ts_${widget.symbol}';
      await prefs.setInt(cooldownKey, now.millisecondsSinceEpoch);
    }

    widget.onSaved?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('저장되었습니다.'),
      ),
    );
  }

  bool _validatePriceRange(String value) {
    if (value.isEmpty) return true;
    final num? price = num.tryParse(value.trim());
    if (price == null) return false;

    final lowRaw = _effectiveSelectedDateLow;
    final highRaw = _effectiveSelectedDateHigh;

    if (lowRaw == null || highRaw == null || lowRaw <= 0 || highRaw <= 0) {
      return true;
    }

    return price >= lowRaw && price <= highRaw;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isNarrow = screenW < 420;

    final double tableMaxW = isNarrow ? (screenW - 24.0) : 350.0;

    final bool isBuy = _tradeType == '매수';
    final Color actionColor = isBuy ? Colors.red : Colors.blue;
    final String actionText = isBuy ? '매수' : '매도';

    const double fsM = 14;
    const double fsXS = 11;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _tradeType = '매수'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isBuy ? actionColor : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      '매수',
                      style: TextStyle(
                        fontSize: fsM,
                        fontWeight: FontWeight.w700,
                        color: isBuy ? actionColor : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => setState(() => _tradeType = '매도'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: (!isBuy) ? actionColor : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      '매도',
                      style: TextStyle(
                        fontSize: fsM,
                        fontWeight: FontWeight.w700,
                        color: (!isBuy) ? actionColor : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFE0B2),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Color(0xFF8D6E63),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "본 기능은 가상 투자 기록용이며 실제 매매가 아닙니다.\n"
                        "가격 및 정보는 참고용이며 투자 판단과 책임은 사용자 본인에게 있습니다.",
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: Color(0xFF6D4C41),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        Card(
          margin: const EdgeInsets.all(12),
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: tableMaxW),
                    child: _buildMainTable(),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: _buildStatusPanel(),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _memoController,
                    maxLines: 1,
                    style: const TextStyle(fontSize: fsXS),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(50),
                    ],
                    decoration: InputDecoration(
                      hintText: '매매 내용 : 50자 이내',
                      hintStyle: const TextStyle(fontSize: fsXS),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF7F8FA),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFD9DEE5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFD9DEE5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF9AA4B2)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: _saveLog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  elevation: 1,
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  actionText,
                  style: const TextStyle(
                    fontSize: fsM,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labelCell(String text) {
    final bool isHighLow = text == '고가' || text == '저가';

    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(vertical: isHighLow ? 10 : 14),
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: isHighLow ? 11 : 14,
          fontWeight: isHighLow ? FontWeight.w600 : FontWeight.w700,
          color: isHighLow ? Colors.grey : Colors.black87,
        ),
      ),
    );
  }

  Widget _valueCell(
      String text, {
        Color color = Colors.black87,
        FontWeight fontWeight = FontWeight.w700,
        bool isHighLow = false,
      }) {
    return Container(
      alignment: Alignment.centerRight,
      padding: EdgeInsets.symmetric(vertical: isHighLow ? 10 : 14),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: isHighLow ? 11 : 14,
          fontWeight: isHighLow ? FontWeight.w600 : fontWeight,
          color: isHighLow ? Colors.grey : color,
        ),
      ),
    );
  }

  Widget _dividerRow() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey.shade200,
    );
  }
  Widget _buildMainTable() {
    final hasValidOhlc = _hasValidOhlcForSelectedDate;

    final high = hasValidOhlc
        ? (_effectiveSelectedDateHigh!).toStringAsFixed(2)
        : '-';
    final low = hasValidOhlc
        ? (_effectiveSelectedDateLow!).toStringAsFixed(2)
        : '-';

    final double availMoney = _statusAvailable ?? 0;
    final double priceForCalc =
        double.tryParse(_priceController.text) ??
            (_currentPrice ?? widget.currentPrice ?? 0);

    double? buyableQty;
    if (availMoney > 0 && priceForCalc > 0) {
      buyableQty = availMoney / priceForCalc;
    }

    double holdingQty = _holdingQtyAsOf ?? 0.0;
    if (_holdingQtyAsOf == null) {
      final currentSymbol = (widget.symbol ?? '').trim();
      for (final p in _statusPositions) {
        if (p.symbol == currentSymbol) {
          holdingQty = p.qty;
          break;
        }
      }
    }

    final bool isHoldingInt = (holdingQty % 1 == 0);
    final String holdingQtyText =
    isHoldingInt ? '${holdingQty.toStringAsFixed(0)}주' : '${holdingQty.toStringAsFixed(2)}주';

    const double fsM = 14;
    const double fsS = 14;
    const double fsXS = 12;

    Widget row({
      required String label,
      required Widget child,
      Widget? right,
      double rightWidth = 44,
      bool showDivider = true,
    }) {
      return Column(
        children: [
          SizedBox(
            height: 36,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111111),
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: child,
                  ),
                ),
                if (right != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: rightWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: right,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.shade200,
            ),
        ],
      );
    }

    Widget ohlcBox(String title, String value) {
      return Expanded(
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: fsXS,
                  color: Color(0xFF777777),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: fsS,
                    color: Color(0xFF111111),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    String? dateStatusText() {
      if (!_isDateValid) return '날짜 오류';
      if (_isHoliday) return '휴일';

      final hasCurrentPrice =
          (_currentPrice != null && _currentPrice! > 0) ||
              (widget.currentPrice != null && widget.currentPrice! > 0);

      // ✅ 현재가가 있으면 "데이터 없음" 숨김
      if (hasCurrentPrice) return null;

      // 투자게임
      if (widget.mode == TradeMode.game) {
        return '데이터 없음';
      }

      // 매매일지
      if (!hasValidOhlc) return '데이터 없음';

      return null;
    }

    Color dateStatusColor() {
      if (!_isDateValid) return Colors.red;
      if (_isHoliday) return Colors.red;

      if (widget.mode == TradeMode.game) {
        final hasCurrentPrice =
            (_currentPrice != null && _currentPrice! > 0) ||
                (widget.currentPrice != null && widget.currentPrice! > 0);

        if (!hasCurrentPrice) return Colors.orange;
        return const Color(0xFF777777);
      }

      if (!hasValidOhlc) return Colors.orange;
      return const Color(0xFF777777);
    }
    final String? statusText = dateStatusText();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        children: [
          if (widget.mode == TradeMode.game)
            row(
              label: '초기 투자금',
              child: TextField(
                controller: _investController,
                enabled: false,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: fsM,
                  fontWeight: FontWeight.w800,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
              ),
              right: null,
            ),

          row(
            label: '날짜',
            child: widget.mode == TradeMode.log
                ? InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openDateSearchDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD9DEE5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_yearController.text}.${_monthController.text.padLeft(2, '0')}.${_dayController.text.padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111111),
                      ),
                    ),
                    _isSearchingDatePrice
                        ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: Color(0xFF009688),
                    ),
                  ],
                ),
              ),
            )
                : Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_yearController.text}. ${_monthController.text}. ${_dayController.text}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
              ),
            ),
            right: null,
          ),

          if (statusText != null)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 90),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          constraints: const BoxConstraints(minHeight: 26),
                          decoration: BoxDecoration(
                            color: dateStatusColor().withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: dateStatusColor().withOpacity(0.25),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: fsXS,
                              color: dateStatusColor(),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 4,
                  thickness: 1,
                  color: Colors.grey.shade200,
                ),
              ],
            ),

          row(
            label: '매매주가',
            child: TextField(
              controller: _priceController,
              enabled: widget.mode == TradeMode.log,
              textAlign: TextAlign.right,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: widget.mode == TradeMode.log
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: (widget.mode == TradeMode.log && !_isPriceValid)
                    ? Colors.red
                    : const Color(0xFF111111),
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '가격',
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                filled: widget.mode == TradeMode.log && !_isPriceValid,
                fillColor: (widget.mode == TradeMode.log && !_isPriceValid)
                    ? Colors.red.withOpacity(0.08)
                    : null,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 2),
              ),
              onChanged: widget.mode == TradeMode.log
                  ? (v) => setState(() => _isPriceValid = _validatePriceRange(v))
                  : null,
            ),
            right: null,
          ),

          if (widget.mode == TradeMode.log)
            Column(
              children: [
                row(
                  label: '고가',
                  child: Text(
                    high,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: Color(0xFF111111),
                    ),
                  ),
                ),
                row(
                  label: '저가',
                  child: Text(
                    low,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: Color(0xFF111111),
                    ),
                  ),
                ),
              ],
            ),

          row(
            label: '매매 수량',
            child: SizedBox(
              width: 120,
              child: TextField(
                controller: _qtyController,
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: fsM,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF7F8FA),
                  suffixText: '주',
                  suffixStyle: const TextStyle(
                    fontSize: fsM,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111111),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFD9DEE5),
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFD9DEE5),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF9AA4B2),
                      width: 1.2,
                    ),
                  ),
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final text = newValue.text;
                    if (text.isEmpty) return newValue;

                    if (_isCryptoSymbol) {
                      final reg = RegExp(r'^\d*\.?\d{0,2}$');
                      return reg.hasMatch(text) ? newValue : oldValue;
                    } else {
                      final reg = RegExp(r'^\d*$');
                      return reg.hasMatch(text) ? newValue : oldValue;
                    }
                  }),
                ],
              ),
            ),
            showDivider: false,
          ),

          if (widget.mode == TradeMode.game)
            row(
              label: '매수 가능',
              child: Text(
                buyableQty == null ? '-' : '${buyableQty.floor()}주',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: fsM,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),

          row(
            label: '보유 수량',
            child: Text(
              holdingQtyText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: fsM,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    if (!_isDateValid) {
      return const SizedBox.shrink();
    }

    final currentSymbol = (widget.symbol ?? '').trim();
    if (currentSymbol.isEmpty) {
      return const SizedBox.shrink();
    }

    const double colName = 135;
    const double colQty = 60;
    const double colAmount = 95;
    const double colRate = 60;
    const double colWeight = 60;

    Widget headerCell(String text, double width, {bool right = false}) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget dataCell(
        String text,
        double width, {
          bool right = false,
          Color? color,
          FontWeight? fw,
        }) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: right ? TextAlign.right : TextAlign.left,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: color ?? Colors.black87,
            fontWeight: fw ?? FontWeight.normal,
          ),
        ),
      );
    }

    final visiblePositions = _statusPositions
        .where((p) => p.qty.abs() >= 0.000001)
        .toList();

    if (visiblePositions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 22),
                  headerCell('종목', colName),
                  headerCell('수량', colQty, right: true),
                  headerCell('평가금액', colAmount, right: true),
                  headerCell('수익률', colRate, right: true),
                  headerCell('비중', colWeight, right: true),
                ],
              ),
              const SizedBox(height: 2),
              for (final p in visiblePositions) ...[
                Row(
                  children: [
                    const SizedBox(width: 22),
                    dataCell(
                      p.name,
                      colName,
                      fw: p.symbol == currentSymbol
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    dataCell(
                          () {
                        final qtyStr = (p.qty % 1 == 0)
                            ? p.qty.toStringAsFixed(0)
                            : p.qty.toStringAsFixed(2);
                        return '$qtyStr주';
                      }(),
                      colQty,
                      right: true,
                    ),
                    dataCell(
                      p.amount.toStringAsFixed(0),
                      colAmount,
                      right: true,
                    ),
                    dataCell(
                      '${p.profitRate.toStringAsFixed(1)}%',
                      colRate,
                      right: true,
                      color: p.profitRate > 0
                          ? Colors.red
                          : (p.profitRate < 0 ? Colors.blue : Colors.grey),
                    ),
                    dataCell(
                      '${p.weight.toStringAsFixed(1)}%',
                      colWeight,
                      right: true,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextBox(
      TextEditingController c,
      String label,
      double width, {
        bool isNumber = false,
        bool enabled = true,
        bool boxed = false,
        void Function(String)? onChanged,
      }) {
    const double fsS = 13;

    return SizedBox(
      width: width,
      height: 32,
      child: TextField(
        controller: c,
        textAlign: TextAlign.right,
        textAlignVertical: TextAlignVertical.center,
        enabled: enabled,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: fsS,
          color: enabled ? const Color(0xFF111111) : const Color(0xFF777777),
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: boxed,
          fillColor: boxed ? const Color(0xFFF7F8FA) : null,
          suffixText: label,
          suffixStyle: TextStyle(
            fontSize: fsS,
            color: enabled ? const Color(0xFF111111) : const Color(0xFF777777),
            fontWeight: FontWeight.w800,
          ),
          contentPadding: EdgeInsets.symmetric(
            vertical: 6,
            horizontal: boxed ? 8 : 0,
          ),
          border: boxed
              ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color(0xFFD9DEE5),
              width: 1,
            ),
          )
              : InputBorder.none,
          enabledBorder: boxed
              ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color(0xFFD9DEE5),
              width: 1,
            ),
          )
              : InputBorder.none,
          focusedBorder: boxed
              ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color(0xFF9AA4B2),
              width: 1.2,
            ),
          )
              : InputBorder.none,
          disabledBorder: boxed
              ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color(0xFFE3E7EC),
              width: 1,
            ),
          )
              : InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildTradeButton(String type, Color color) {
    final isActive = _tradeType == type;
    return GestureDetector(
      onTap: () => setState(() => _tradeType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : Colors.grey,
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          type,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
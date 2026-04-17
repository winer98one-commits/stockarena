// 📄 lib/widgets/trade_mode_toggle.dart
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// 매매일지 / 투자 게임 모드
enum TradeMode {
  log,   // 매매일지
  game,  // 투자 게임
}

/// 상단에 쓰는 공통 토글 버튼
///
/// 사용 예:
/// TradeModeToggle(
///   mode: _currentMode,
///   onChanged: (mode) {
///     setState(() => _currentMode = mode);
///   },
/// )
class TradeModeToggle extends StatelessWidget {
  final TradeMode mode;
  final ValueChanged<TradeMode> onChanged;

  /// 여백/크기 조절 옵션(필요 없으면 기본값 사용)
  final EdgeInsetsGeometry margin;
  final double height;
  final double borderRadius;

  const TradeModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    this.margin = const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 8),
    this.height = 40,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isLog = mode == TradeMode.log;
    final isGame = mode == TradeMode.game;

    return Container(
      margin: margin,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 배경 + 두 버튼
          Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildItem(
                  label: AppLocalizations.of(context)!.tradeLogTab,
                  isActive: isLog,
                  activeColor: Colors.blue,
                  onTap: () => onChanged(TradeMode.log),
                  leftRadius: borderRadius,
                  rightRadius: 0,
                ),
                _buildItem(
                  label: AppLocalizations.of(context)!.investmentGameTab,
                  isActive: isGame,
                  activeColor: Colors.purple,
                  onTap: () => onChanged(TradeMode.game),
                  leftRadius: 0,
                  rightRadius: borderRadius,
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    required double leftRadius,
    required double rightRadius,
  }) {
    final bgColor = isActive ? activeColor : Colors.transparent;
    final textColor = isActive ? Colors.white : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(leftRadius),
        right: Radius.circular(rightRadius),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(leftRadius),
            right: Radius.circular(rightRadius),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ).copyWith(color: textColor),
        ),
      ),
    );
  }
}

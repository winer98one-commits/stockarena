// 📄 lib/widgets/kospi_autocomplete.dart  (서버 검색 연동 최종 버전)

import 'package:flutter/material.dart';
import '../utils/symbol_resolver.dart';   // ✅ searchAllWithYahoo 사용
import 'package:shared_preferences/shared_preferences.dart';

/// 통합 자동완성 위젯
/// - 주식(한국/미국) + 코인 + 선물 + 지수 + 미국 ETF
/// - 내부에서 searchAllWithYahoo() 호출
///   → 1) (지금은) 무조건 서버 /search (EODHD)검색
class KospiAutocomplete extends StatefulWidget {
  final void Function(String symbol, String name)? onSelected;

  const KospiAutocomplete({super.key, this.onSelected});

  @override
  State<KospiAutocomplete> createState() => _KospiAutocompleteState();
}

class _KospiAutocompleteState extends State<KospiAutocomplete> {
  static const String _recentSearchesKey = 'recent_searches_v1';
  static const int _maxRecent = 8;

  List<String> _recentSearches = [];
  String _currentText = '';
  bool _showOptions = true;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentSearchesKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _recentSearches = saved;
    });
  }

  Future<void> _saveRecentSearch(String item) async {
    final prefs = await SharedPreferences.getInstance();

    final updated = List<String>.from(_recentSearches);
    updated.remove(item);
    updated.insert(0, item);

    if (updated.length > _maxRecent) {
      updated.removeRange(_maxRecent, updated.length);
    }

    await prefs.setStringList(_recentSearchesKey, updated);

    if (!mounted) return;
    setState(() {
      _recentSearches = updated;
    });
  }

  Future<void> _removeRecentSearch(String item) async {
    final prefs = await SharedPreferences.getInstance();

    final updated = List<String>.from(_recentSearches)..remove(item);
    await prefs.setStringList(_recentSearchesKey, updated);

    if (!mounted) return;
    setState(() {
      _recentSearches = updated;
    });
  }

  List<String> _buildAutoCompleteOptions(String text) {
    final results = searchLocalStocks(text);
    final lower = text.toLowerCase();

    final filtered = results.where((r) {
      final rawSymbol = (r['symbol'] ?? '').toString();
      final rawName = (r['name'] ?? '').toString();

      final symbol = rawSymbol.toLowerCase();
      final name = rawName.toLowerCase();

      final symbolStartsWith = symbol.startsWith(lower);
      final nameStartsWith = name.startsWith(lower);

      return symbolStartsWith || nameStartsWith;
    }).toList();

    filtered.sort((a, b) {
      final rawSymbolA = (a['symbol'] ?? '').toString();
      final rawNameA = (a['name'] ?? '').toString();
      final rawSymbolB = (b['symbol'] ?? '').toString();
      final rawNameB = (b['name'] ?? '').toString();

      final symbolA = rawSymbolA.toLowerCase();
      final nameA = rawNameA.toLowerCase();
      final symbolB = rawSymbolB.toLowerCase();
      final nameB = rawNameB.toLowerCase();

      final aSymbolStarts = symbolA.startsWith(lower);
      final aNameStarts = nameA.startsWith(lower);
      final bSymbolStarts = symbolB.startsWith(lower);
      final bNameStarts = nameB.startsWith(lower);

      int scoreA;
      if (aSymbolStarts && aNameStarts) {
        scoreA = 1;
      } else if (aSymbolStarts) {
        scoreA = 2;
      } else if (aNameStarts) {
        scoreA = 3;
      } else {
        scoreA = 4;
      }

      int scoreB;
      if (bSymbolStarts && bNameStarts) {
        scoreB = 1;
      } else if (bSymbolStarts) {
        scoreB = 2;
      } else if (bNameStarts) {
        scoreB = 3;
      } else {
        scoreB = 4;
      }

      final primary = scoreA.compareTo(scoreB);
      if (primary != 0) return primary;

      return symbolA.compareTo(symbolB);
    });

    return filtered.map((r) {
      final name = (r['name'] ?? '').toString();
      final symbol = (r['symbol'] ?? '').toString();
      final exchange = (r['exchange'] ?? '').toString();
      return '$name|$symbol|$exchange';
    }).toList();
  }

  Future<void> _handleSelected(String item) async {
    final parts = item.split('|');
    final name = parts.isNotEmpty ? parts[0] : '';
    final symbol = parts.length > 1 ? parts[1] : '';

    try {
      final prefs = await SharedPreferences.getInstance();

      String normSym(String s) {
        final v = s.trim().toUpperCase();
        final i = v.indexOf('.');
        return (i >= 0) ? v.substring(0, i) : v; // AAPL.US -> AAPL
      }

      final sym = symbol.trim();
      final nm = name.trim();
      if (sym.isNotEmpty && nm.isNotEmpty) {
        await prefs.setString('symbol_name_$sym', nm);
        await prefs.setString('symbol_name_${normSym(sym)}', nm);
      }
    } catch (_) {}

    await _saveRecentSearch(item);

    if (widget.onSelected != null) {
      widget.onSelected!(symbol, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleList = _currentText.isEmpty
        ? _recentSearches
        : _buildAutoCompleteOptions(_currentText);

    final isRecentMode = _currentText.isEmpty;
    final shouldShowList = _showOptions && visibleList.isNotEmpty;

    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              style: const TextStyle(
                fontSize: 14,
              ),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '검색',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onTap: () {
                setState(() {
                  _showOptions = true;
                  _currentText = '';
                });
                setInnerState(() {});
              },
              onChanged: (value) {
                setState(() {
                  _showOptions = true;
                  _currentText = value.trim();
                });
                setInnerState(() {});
              },
            ),

            if (shouldShowList)
              Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      maxHeight: 320,
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: visibleList.length,
                      itemBuilder: (context, index) {
                        final item = visibleList[index];
                        final parts = item.split('|');
                        final name = parts.isNotEmpty ? parts[0] : '';
                        final symbol = parts.length > 1 ? parts[1] : '';
                        final exchange = parts.length > 2 ? parts[2] : '';

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isRecentMode ? Icons.history : Icons.search,
                            size: 20,
                            color: Colors.black54,
                          ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            symbol.isNotEmpty
                                ? (exchange.isNotEmpty
                                ? '$symbol  ·  $exchange'
                                : symbol)
                                : exchange,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: isRecentMode
                              ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () async {
                              await _removeRecentSearch(item);
                              setInnerState(() {});
                            },
                          )
                              : null,
                          onTap: () async {
                            await _handleSelected(item);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

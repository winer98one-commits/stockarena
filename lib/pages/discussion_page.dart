// 📄 pages/discussion_page.dart
import 'dart:convert'; // ✅ jsonDecode
import 'package:http/http.dart' as http; // ✅ http.get

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/game_server_api.dart';

import '../widgets/trade_mode_toggle.dart';
import 'trade_log_page.dart';
import 'admin_discussion_page.dart';

class DiscussionPage extends StatefulWidget {
  final String? uid;       // ✅ uid는 선택: AppShell이 못 주면 내부에서 확보
  final String symbolRaw;  // ✅ 선택한 종목 (예: AAPL.US)
  final String? symbolName;

  // ✅ AppShell에서 내려주는 현재 선택 종목/이름 (랭킹과 동일)
  final String? selectedSymbol;
  final String? selectedName;

  // ✅ 랭킹처럼 사이드바/즐겨찾기 콜백 받기
  final VoidCallback? onToggleFavoriteSidebar;
  final Function(String)? onAddFavorite;

  const DiscussionPage({
    super.key,
    this.uid,
    required this.symbolRaw,
    this.symbolName,
    this.selectedSymbol,
    this.selectedName,
    this.onToggleFavoriteSidebar,
    this.onAddFavorite,
  });

  @override
  State<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends State<DiscussionPage> {
  bool _loading = false;
  String? _error;

  final _controller = TextEditingController();
  List<Map<String, dynamic>> _items = [];

  String? _selectedSymbol;
  String? _selectedName;

// ✅ 관리자 표시용
  bool _isAdmin = false;

  String get _symbolKey =>
      (_selectedSymbol ?? widget.symbolRaw).trim().toUpperCase();

  @override
  void initState() {
    super.initState();

    // ✅ AppShell에서 전달된 선택 종목을 내부 상태로 초기화
    _selectedSymbol = widget.selectedSymbol ?? widget.symbolRaw;
    _selectedName = widget.selectedName ?? widget.symbolName;

    // ✅ 관리자 여부 확인
    _checkAdmin();

    // ✅ 초기 로딩
    if (_selectedSymbol != null && _selectedSymbol!.trim().isNotEmpty) {
      _loadPosts();
    }
  }

  void _showWarn(String message) {
    if (!mounted) return;

    const rules = [
      '• 300자 이하만 작성 가능',
      '• 링크/URL 입력 금지 (http, https, www, .com 등)',
      '• 욕설/비방/혐오 표현 금지 (금칙어 포함)',
      '• 너무 자주 작성 금지 (10초 간격 제한)',
    ];

    final rulesText = rules.join('\n');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알림'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              const Text(
                '토론 규칙',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                rulesText,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }



  String _friendlyError(Object e) {
    final raw = e.toString();

    // Flutter Web에서 자주 뜨는 네트워크/CORS/주소 문제
    if (raw.contains('Failed to fetch')) {
      return '서버에 연결할 수 없습니다. (주소/서버상태/CORS/방화벽 확인)';
    }

    // FastAPI HTTPException detail 형태를 최대한 뽑아냄
    // 1) JSON 형태: {"detail":"..."}
    final mJson = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(raw);
    if (mJson != null) return mJson.group(1)!;

    // 2) detail=... 형태
    final mDetailEq = RegExp(r'detail[=:]\s*([^\n\}]+)').firstMatch(raw);
    if (mDetailEq != null) return mDetailEq.group(1)!.trim();

    // 3) 불필요한 접두어 제거
    var msg = raw;
    msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
    msg = msg.replaceFirst(RegExp(r'^ClientException:\s*'), '');
    msg = msg.replaceFirst(RegExp(r'^HttpException:\s*'), '');
    msg = msg.trim();

    // ✅ "글 작성 실패: XXX" 같이 감싸진 형태면 XXX만 남김
    msg = msg.replaceFirst(RegExp(r'^글 작성 실패:\s*'), '').trim();

    return msg.isEmpty ? '알 수 없는 오류가 발생했습니다.' : msg;
  }



  @override
  void didUpdateWidget(covariant DiscussionPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newSymbol = (widget.selectedSymbol ?? widget.symbolRaw).trim();
    final newName = (widget.selectedName ?? widget.symbolName)?.trim();

    final oldSymbol = (oldWidget.selectedSymbol ?? oldWidget.symbolRaw).trim();
    final oldName = (oldWidget.selectedName ?? oldWidget.symbolName)?.trim();

    // ✅ AppShell에서 선택 종목이 바뀌면 토론 페이지 상태도 갱신 + 재조회
    if (newSymbol != oldSymbol || (newName ?? '') != (oldName ?? '')) {
      setState(() {
        _selectedSymbol = newSymbol;
        _selectedName = newName;
        _items = [];
        _error = null;
      });

      _loadPosts();
    }
  }



  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ✅ uid 확보: (1) widget.uid 우선 (2) SharedPreferences 후보 키 탐색 (3) 없으면 에러
  Future<String?> _resolveUid() async {
    final direct = (widget.uid ?? '').trim();
    if (direct.isNotEmpty) return direct;

    final prefs = await SharedPreferences.getInstance();

    // 프로젝트마다 키가 다를 수 있어서 여러 후보를 체크
    const keys = <String>[
      'uid',
      'user_uid',
      'user_id',
      'login_uid',
      'current_uid',
      'guest_uid',
    ];

    for (final k in keys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty) return v;
    }

    return null;
  }

  Future<void> _checkAdmin() async {
    try {
      final isAdmin = await GameServerApi.isCurrentUserAdmin();

      print('관리자 여부 확인 결과: $isAdmin');

      if (!mounted) return;

      setState(() {
        _isAdmin = isAdmin;
      });
    } catch (e) {
      print('관리자 여부 확인 에러: $e');

      if (!mounted) return;

      setState(() {
        _isAdmin = false;
      });
    }
  }

  void _openFavoriteSidebar() {
    final cb = widget.onToggleFavoriteSidebar;
    if (cb != null) {
      cb();
      return;
    }

    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.hasDrawer) {
      scaffold.openDrawer();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('즐겨찾기 메뉴 연결이 안 되어 있습니다. (콜백 전달 필요)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onSelectedSymbol(String symbol, String name) async {
    setState(() {
      _selectedSymbol = symbol.trim();
      _selectedName = name.trim();
      _error = null;
      _items = [];
    });

    await _loadPosts();
  }

  void _onAddFavoritePressed() {
    final symbol = (_selectedSymbol ?? '').trim();
    final name = (_selectedName ?? '').trim();

    if (symbol.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('종목을 먼저 선택한 뒤 즐겨찾기에 추가하세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // ✅ 메인/랭킹과 동일 포맷: "SYMBOL|NAME"
    widget.onAddFavorite?.call("$symbol|${name.isNotEmpty ? name : symbol}");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('즐겨찾기에 추가했습니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static const String _serverBaseUrl = "http://46.224.127.151:8000";

  Future<Map<String, int>> _fetchRankMap(String symbolUpper) async {
    final uri = Uri.parse('$_serverBaseUrl/game/ranking').replace(
      queryParameters: {
        'symbol': symbolUpper,
        'mode': 'game',
        'limit': '200',
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('랭킹 서버 오류: ${res.statusCode} ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> rows = (body['rows'] as List<dynamic>?) ?? [];

    final map = <String, int>{};
    for (final x in rows) {
      final m = Map<String, dynamic>.from(x as Map);
      final uid = (m['uid'] ?? '').toString().trim();
      final rank = (m['rank'] as num?)?.toInt() ?? 0;
      if (uid.isNotEmpty && rank > 0) {
        map[uid] = rank;
      }
    }
    return map;
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = await _resolveUid();
      if (uid == null || uid.isEmpty) {
        _showWarn('로그인 후 이용해주세요. (uid 없음)');
        return;
      }

      final items = await GameServerApi.fetchDiscussionPosts(
        uid: uid,
        symbol: _symbolKey,
        limit: 50,
      );

      // ✅ 토론 응답에 rank_no가 없거나(0)인 경우, 랭킹 API로 보강
      final needFill = items.any((m) {
        final v = m['rank_no'];
        final r = (v is num) ? v.toInt() : 0;
        return r <= 0;
      });

      if (needFill) {
        final rankMap = await _fetchRankMap(_symbolKey);

        for (final m in items) {
          final u = (m['uid'] ?? '').toString().trim();
          if (u.isEmpty) continue;

          final r = rankMap[u] ?? 0;
          if (r > 0) {
            m['rank_no'] = r; // ✅ UI는 rank_no를 읽으므로 여기 채움
          }
        }
      }

      setState(() => _items = items);
    } catch (e) {
      _showWarn(_friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }


  Future<void> _submit() async {
    final text = _controller.text.trim();

    // ✅ 0) 빈값 경고
    if (text.isEmpty) {
      _showWarn('내용을 입력하세요.');
      return;
    }

    // ✅ 1) 300자 제한 (앱에서도 즉시 차단)
    if (text.length > 300) {
      _showWarn('내용은 300자 이하만 가능합니다.');
      return;
    }

    // ✅ 2) 링크 금지 (앱에서도 즉시 차단)
    final lower = text.toLowerCase();
    const forbidden = [
      'http://',
      'https://',
      'www.',
      '.com',
      '.net',
      '.org',
      '.kr',
      '.io',
    ];
    for (final p in forbidden) {
      if (lower.contains(p)) {
        _showWarn('링크는 허용되지 않습니다.');
        return;
      }
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null; // ✅ 화면 표시 안 할 거지만 값은 유지해도 됨
    });

    try {
      final uid = await _resolveUid();
      if (uid == null || uid.isEmpty) {
        _showWarn('로그인 후 이용해주세요. (uid 없음)');
        return;
      }

      await GameServerApi.createDiscussionPost(
        uid: uid,
        symbol: _symbolKey,
        bodyText: text,
      );

      _controller.clear();
      await _loadPosts();
    } catch (e) {
      // ✅ 서버가 준 이유(detail)만 최대한 깔끔하게 팝업에 표시
      _showWarn(_friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }


  void _goToUserProfit(String targetUid) {
    // ✅ "현재 토론 페이지에서 선택된 종목" 기준으로 타인 거래 페이지 열기
    final symbol = (_selectedSymbol ?? widget.symbolRaw).trim();
    final name = (_selectedName ?? widget.symbolName ?? symbol).trim();

    if (symbol.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 종목을 선택하세요.')),
      );
      return;
    }

    if (targetUid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('UID가 비어있어 조회할 수 없습니다.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TradeLogPage(
          initialSymbol: symbol,
          initialName: name.isNotEmpty ? name : symbol,
          currentPrice: null,
          favorites: const [],
          folders: const [],
          overrideUid: targetUid,
          initialMode: TradeMode.game,
        ),
      ),
    );
  }

  Future<void> _showReportDialog(Map<String, dynamic> item) async {
    final targetUid = (item['uid'] ?? '').toString().trim();
    final nickname = (item['nickname'] ?? '').toString().trim();
    final body = (item['body'] ?? '').toString().trim();
    final postId = (item['id'] as num?)?.toInt() ?? 0;

    final displayName = nickname.isNotEmpty ? nickname : targetUid;

    if (postId <= 0) {
      _showWarn('댓글 ID가 없어 신고할 수 없습니다.');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 신고'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$displayName 님의 댓글을 신고하시겠습니까?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                body.isEmpty ? '(내용 없음)' : body,
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();

              try {
                final myUid = await _resolveUid();
                if (myUid == null || myUid.isEmpty) {
                  _showWarn('로그인 후 신고할 수 있습니다.');
                  return;
                }

                await GameServerApi.reportDiscussionPost(
                  uid: myUid,
                  postId: postId,
                );

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('신고가 접수되었습니다.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                _showWarn(_friendlyError(e));
              }
            },
            child: const Text('신고하기'),
          ),
        ],
      ),
    );
  }

  void _showCommentMenu(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
              title: const Text('신고하기'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showReportDialog(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAdminDiscussionPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminDiscussionPage(),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> m) {
    final uid = (m['uid'] ?? '').toString();
    final nickname = (m['nickname'] ?? '').toString().trim();
    final body = (m['body'] ?? '').toString();
    final rankNo = (m['rank_no'] is num) ? (m['rank_no'] as num).toInt() : 0;

    final createdAtRaw = (m['created_at'] ?? '').toString();

    String createdAt = '';
    try {
      if (createdAtRaw.isNotEmpty) {
        final dt = DateTime.parse(createdAtRaw).toLocal();
        createdAt =
        '${dt.year.toString().padLeft(4, '0')}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    final displayName = nickname.isNotEmpty ? nickname : uid;

    // ✅ 여백(위아래) 축소 + 카드/테두리 제거 (리스트 느낌)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ 1줄: 순위 - 닉네임 - 날짜
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (rankNo > 0)
                InkWell(
                  onTap: () => _goToUserProfit(uid),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.withOpacity(0.35)),
                    ),
                    child: Text(
                      '${rankNo}위',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Colors.deepPurple,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),

              if (rankNo > 0) const SizedBox(width: 8),

              Expanded(
                child: InkWell(
                  onTap: () => _goToUserProfit(uid),
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.0,
                    ),
                  ),
                ),
              ),

              if (createdAt.isNotEmpty) const SizedBox(width: 8),

              if (createdAt.isNotEmpty)
                Text(
                  createdAt,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    height: 1.0,
                  ),
                ),

              const SizedBox(width: 6),

              IconButton(
                onPressed: () => _showCommentMenu(context, m),
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: '댓글 메뉴',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // ✅ 다음 줄: 내용 (박스 없이)
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.25,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 6),

          // ✅ 구분선(가볍게) + 위아래 공간 절약
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openAdminDiscussionPage,
                    icon: const Icon(Icons.admin_panel_settings, size: 18),
                    label: const Text('관리자'),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _loading
                ? const Center(child: Text('불러오는 중...'))
                : (_items.isEmpty
                ? const Center(child: Text('아직 글이 없습니다.'))
                : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) => _buildRow(_items[i]),
            )),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              width: double.infinity,
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
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFF8D6E63),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "토론 내용은 사용자 개인 의견이며 투자 권유 또는 수익 보장을 의미하지 않습니다.\n"
                          "허위 정보, 비방, 과도한 선동 게시물은 제한될 수 있습니다.",
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

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      hintText: '토론 글을 입력하세요 (최대 300자)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: const Text('등록'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

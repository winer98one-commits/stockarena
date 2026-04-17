import 'package:flutter/material.dart';
import '../services/game_server_api.dart';

class AdminDiscussionPage extends StatefulWidget {
  const AdminDiscussionPage({super.key});

  @override
  State<AdminDiscussionPage> createState() => _AdminDiscussionPageState();
}

class _AdminDiscussionPageState extends State<AdminDiscussionPage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  String _friendlyError(Object e) {
    final raw = e.toString();

    final mJson = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(raw);
    if (mJson != null) return mJson.group(1)!;

    var msg = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return msg.isEmpty ? '알 수 없는 오류가 발생했습니다.' : msg;
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await GameServerApi.fetchAdminDiscussionReports(limit: 100);

      if (!mounted) return;
      setState(() {
        _items = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _hidePost(int postId, bool hidden) async {
    try {
      setState(() => _loading = true);

      await GameServerApi.adminHideDiscussionPost(
        postId: postId,
        hidden: hidden,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hidden ? '댓글을 숨김 처리했습니다.' : '댓글 숨김을 해제했습니다.'),
        ),
      );

      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteReport(int reportId) async {
    try {
      setState(() => _loading = true);

      await GameServerApi.adminDeleteDiscussionReport(reportId: reportId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고를 삭제했습니다.')),
      );

      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _moderateUser(String uid, String action) async {
    try {
      setState(() => _loading = true);

      await GameServerApi.adminModerateUser(
        uid: uid,
        action: action,
      );

      if (!mounted) return;

      String msg = '처리 완료';
      if (action == 'warn') msg = '경고를 부여했습니다.';
      if (action == 'ban_1d') msg = '1일 차단했습니다.';
      if (action == 'ban_7d') msg = '7일 차단했습니다.';
      if (action == 'perm_ban') msg = '영구 차단했습니다.';
      if (action == 'unban') msg = '차단을 해제했습니다.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );

      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final reportId = (item['report_id'] as num?)?.toInt() ?? 0;
    final postId = (item['post_id'] as num?)?.toInt() ?? 0;
    final symbol = (item['symbol'] ?? '').toString();
    final body = (item['body'] ?? '').toString();
    final targetUid = (item['post_uid'] ?? '').toString();
    final nickname = (item['post_nickname'] ?? '').toString().trim();
    final reportCount = (item['report_count'] as num?)?.toInt() ?? 0;
    final isHidden = item['is_hidden'] == true;
    final reason = (item['reason'] ?? '').toString().trim();

    final displayName = nickname.isNotEmpty ? nickname : targetUid;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$symbol | $displayName',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(body.isEmpty ? '(내용 없음)' : body),
            const SizedBox(height: 8),
            Text('댓글 ID: $postId'),
            Text('신고 ID: $reportId'),
            Text('신고 수: $reportCount'),
            Text('숨김 상태: ${isHidden ? "숨김" : "정상"}'),
            if (reason.isNotEmpty) Text('신고 사유: $reason'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _hidePost(postId, !isHidden),
                    child: Text(isHidden ? '숨김 해제' : '숨김'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => _deleteReport(reportId),
                    child: const Text('신고 삭제'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _loading ? null : () => _moderateUser(targetUid, 'warn'),
                  child: const Text('경고'),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : () => _moderateUser(targetUid, 'ban_1d'),
                  child: const Text('1일 차단'),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : () => _moderateUser(targetUid, 'ban_7d'),
                  child: const Text('7일 차단'),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : () => _moderateUser(targetUid, 'perm_ban'),
                  child: const Text('영구 차단'),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : () => _moderateUser(targetUid, 'unban'),
                  child: const Text('차단 해제'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadReports,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(child: Text('신고된 댓글이 없습니다.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) => _buildItem(_items[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('댓글 관리자'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadReports,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_loading && _items.isNotEmpty)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
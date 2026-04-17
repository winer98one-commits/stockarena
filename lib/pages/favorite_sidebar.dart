import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';

// ✅ PC 드래그로 옮길 때 전달할 데이터
class _DragFav {
  final String symbol;
  final String name;
  const _DragFav({required this.symbol, required this.name});
}

class FavoriteSidebar extends StatefulWidget {
  final List<String> favorites;
  final List<String> folders;
  final ValueChanged<String>? onAddFolder;
  final ValueChanged<String>? onSelectFolder;
  final void Function(String symbol, String name, String targetFolder)? onMoveToFolder;
  final Function(String, String) onSelect;
  final Function(String) onRemove;
  final VoidCallback onAdd;
  final VoidCallback? onToggleSidebar;

  const FavoriteSidebar({
    super.key,
    required this.favorites,
    required this.onSelect,
    required this.onRemove,
    required this.onAdd,
    this.onToggleSidebar,
    required this.folders,
    this.onAddFolder,
    this.onSelectFolder,
    this.onMoveToFolder,
  });

  @override
  State<FavoriteSidebar> createState() => _FavoriteSidebarState();
}

class _FavoriteSidebarState extends State<FavoriteSidebar> {
  String? _selectedFolder;

  String _prettyTitle(String symbol, String name) {
    final s = symbol.trim();
    final n = name.trim();

    if (s.isEmpty) return n.isEmpty ? '' : n;
    if (n.isEmpty) return s;

    // 1) name에 들어있는 symbol을 대소문자 무시하고 제거
    final re = RegExp(r'\b' + RegExp.escape(s) + r'\b', caseSensitive: false);
    var cleaned = n.replaceAll(re, ' ');

    // 2) 흔한 구분자/괄호 정리
    cleaned = cleaned
        .replaceAll(RegExp(r'[\(\)\[\]]'), ' ')
        .replaceAll(RegExp(r'[-_/|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 3) cleaned가 비었거나 symbol과 같으면 symbol만
    if (cleaned.isEmpty || cleaned.toUpperCase() == s.toUpperCase()) {
      return s;
    }

    // 4) 최종: "이름 (코드)"
    return '$cleaned ($s)';
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedFolder == null && widget.folders.isNotEmpty) {
      _selectedFolder = widget.folders.first;
    }

    return Container(
      width: 300,
      color: Colors.grey[100],
      child: Column(
        children: [

          Expanded(
            child: Row(
              children: [
                _buildFolderColumn(),
                const VerticalDivider(width: 1),
                _buildFavoriteList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= HEADER =================



  Future<void> _showAddFolderDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.addFolder),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.folderName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(AppLocalizations.of(context)!.add),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      widget.onAddFolder?.call(name);
    }
  }

  // ================= FOLDER COLUMN =================

  Widget _buildFolderColumn() {
    return SizedBox(
      width: 60,
      child: ListView.builder(
        itemCount: 10,
        itemBuilder: (context, i) {
          // ✅ 폴더가 리스트에 없더라도 1~10번은 "항상 존재"하도록 ID 생성
          final fallbackFolderId = '${i + 1}';
          final folderName =
          (i < widget.folders.length) ? widget.folders[i] : fallbackFolderId;

          final selected = (_selectedFolder == folderName);

          // ✅ 현재 폴더가 실제 목록에 있는지(=이미 생성된 폴더인지)
          final exists = widget.folders.contains(folderName);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
            child: DragTarget<_DragFav>(
              // ✅ 이제 항상 폴더가 있으므로 null 체크 제거
              onWillAccept: (data) => _isDesktop() && data != null,
              onAccept: (data) {
                // ✅ 드래그로 옮길 때도 폴더가 없으면 먼저 생성
                if (!exists) {
                  widget.onAddFolder?.call(folderName);
                }
                if (widget.onMoveToFolder != null) {
                  widget.onMoveToFolder!(data.symbol, data.name, folderName);
                }
              },
              builder: (context, candidate, rejected) {
                final isHover = candidate.isNotEmpty;

                return InkWell(
                  onTap: () {
                    setState(() => _selectedFolder = folderName);

                    // ✅ 클릭한 폴더가 아직 없으면 생성(=2~10번도 기능 살아남)
                    if (!exists) {
                      widget.onAddFolder?.call(folderName);
                    }

                    widget.onSelectFolder?.call(folderName);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.black
                          : (isHover ? Colors.orange.shade200 : Colors.white),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        topRight: Radius.circular(0),
                        bottomRight: Radius.circular(0),
                      ),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ================= FAVORITE LIST =================

  Widget _buildFavoriteList() {
    return Expanded(
      child: ListView.builder(
        itemCount: widget.favorites.length,
        itemBuilder: (context, index) {
          final raw = widget.favorites[index];
          final parts = raw.split('|');

          final symbol = parts.isNotEmpty ? parts[0] : '';
          final name = parts.length > 1 ? parts[1] : '';

          final title = _prettyTitle(symbol, name);

          final tile = GestureDetector(
            onTap: () => widget.onSelect(symbol, name),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6E6E6), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => widget.onRemove(symbol),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 18, color: Colors.black38),
                    ),
                  ),
                ],
              ),
            ),
          );

          if (_isDesktop() && widget.onMoveToFolder != null) {
            return Draggable<_DragFav>(
              data: _DragFav(symbol: symbol, name: name),
              feedback: Material(
                color: Colors.transparent,
                child: Text(_prettyTitle(symbol, name)),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: tile),
              child: tile,
            );
          }

          return tile;
        },
      ),
    );
  }

  bool _isMobile() {
    if (kIsWeb) return false;
    final p = Theme.of(context).platform;
    return p == TargetPlatform.android ||
        p == TargetPlatform.iOS;
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    final p = Theme.of(context).platform;
    return p == TargetPlatform.windows ||
        p == TargetPlatform.macOS ||
        p == TargetPlatform.linux;
  }
}
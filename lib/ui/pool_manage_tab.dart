import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../engine/config.dart';
import '../state/ranking_store.dart';

class PoolManageTab extends StatefulWidget {
  const PoolManageTab({super.key});
  @override
  State<PoolManageTab> createState() => _PoolManageTabState();
}

class _PoolManageTabState extends State<PoolManageTab> {
  bool _manageMode = false;
  final Set<String> _selected = {};
  final TextEditingController _addCtrl = TextEditingController();
  List<MapEntry<String, String>> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }



  Future<void> _searchCode(String query) async {
    if (query.isEmpty) {
      setState(() { _searchResults = []; });
      return;
    }
    final clean = query.replaceAll(RegExp(r'[^0-9]'), '');
    // Only send request when input is exactly 6 digits
    if (clean.length != 6) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() { _searching = true; });
    try {
      final store = context.read<RankingStore>();
      final names = await store.fetchCodeNames([clean]);
      if (!mounted) return;
      setState(() {
        _searchResults = names.entries.toList();
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _searching = false; });
    }
  }

  Future<void> _addFromSearch(String cleanCode, String name) async {
    final store = context.read<RankingStore>();
    final fullCode = RankingStore.attachSuffix(cleanCode);
    await store.addToPool([fullCode]);
    _addCtrl.clear();
    setState(() { _searchResults = []; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已添加: $name ($cleanCode)'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _importFromClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboard?.text == null || clipboard!.text!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('剪贴板为空'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // Extract 6-digit codes, avoiding parts of longer digit sequences
    final text = clipboard.text!;
    final codes = <String>{};
    // Match 6-digit numbers that aren't part of longer digit sequences
    final regex = RegExp(r'(?:^|\D)(\d{6})(?:\D|\$)');
    for (final m in regex.allMatches(text)) {
      codes.add(m.group(1)!);
    }
    // Also try pure 6-digit tokens (separated by whitespace/punctuation)
    for (final token in text.split(RegExp(r'[\s,;|\n\r]+'))) {
      if (RegExp(r'^\d{6}\$').hasMatch(token)) {
        codes.add(token);
      }
    }

    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('剪贴板中未识别到6位代码'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // Filter out already existing codes
    final store = context.read<RankingStore>();
    final existingClean = store.etfPool.map(Config.cleanCode).toSet();
    final newCodes = codes.where((c) => !existingClean.contains(c)).toList();

    if (newCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('剪贴板中的代码已全部在池中'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // Fetch names from Tencent API
    store.fetchCodeNames(newCodes).then((names) {
      if (!mounted) return;
      _showImportSheet(newCodes, names);
    });
  }

  void _showImportSheet(List<String> codes, Map<String, String> names) {
    final checked = <String, bool>{for (final c in codes) c: true};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final checkedCount = checked.values.where((v) => v).length;
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2),
                )),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('导入标的', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('$checkedCount/${codes.length} 已选', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ]),
                const SizedBox(height: 12),
                Flexible(child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: codes.length,
                  itemBuilder: (ctx, i) {
                    final code = codes[i];
                    final name = names[code] ?? '未知';
                    return CheckboxListTile(
                      value: checked[code],
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Row(children: [
                        Text(name, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(code, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                      subtitle: null,
                      onChanged: (v) {
                        setSheetState(() { checked[code] = v ?? false; });
                      },
                    );
                  },
                )),
                const SizedBox(height: 8),
                Row(children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: checkedCount == 0 ? null : () {
                      final selected = codes.where((c) => checked[c] == true).toList();
                      Navigator.of(ctx).pop();
                      _doImport(selected);
                    },
                    child: Text('确认导入 ($checkedCount)', style: TextStyle(
                      color: checkedCount > 0 ? const Color(0xFF16A34A) : Colors.grey,
                      fontWeight: FontWeight.w600,
                    )),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _doImport(List<String> cleanCodes) async {
    final store = context.read<RankingStore>();
    final fullCodes = cleanCodes.map(RankingStore.attachSuffix).toList();
    await store.addToPool(fullCodes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已导入 ${cleanCodes.length} 只标的'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _deleteSelected() {
    if (_selected.isEmpty) return;
    final store = context.read<RankingStore>();
    final codes = _selected.toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要从池中删除 ${codes.length} 只标的吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              store.removeFromPool(codes);
              setState(() { _manageMode = false; _selected.clear(); });
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _resetPool() {
    final store = context.read<RankingStore>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认池'),
        content: const Text('将恢复到默认的标的池，当前自定义的标的将被清除。确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              store.resetPool();
              setState(() { _manageMode = false; _selected.clear(); });
            },
            child: const Text('恢复', style: TextStyle(color: Color(0xFF16A34A))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingStore>(builder: (context, store, _) {
      final pool = store.etfPool;
      final isDefault = store.isPoolDefault;
      final isLoading = store.state.loading;

      return Column(children: [
        // Top bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Text('标的池', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDefault ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isDefault ? '默认 ${pool.length}只' : '自定义 ${pool.length}只',
                style: TextStyle(fontSize: 11, color: isDefault ? const Color(0xFF16A34A) : const Color(0xFFB45309)),
              ),
            ),
            const Spacer(),
            if (_manageMode) ...[
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: _selected.isEmpty ? null : _deleteSelected,
                tooltip: '删除选中',
              ),
              TextButton(
                onPressed: () => setState(() { _manageMode = false; _selected.clear(); }),
                child: const Text('完成'),
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.checklist, size: 20),
                onPressed: () => setState(() { _manageMode = true; }),
                tooltip: '管理',
              ),
              IconButton(
                icon: const Icon(Icons.restore, size: 20),
                onPressed: isDefault ? null : _resetPool,
                tooltip: '恢复默认',
              ),
            ],
          ]),
        ),

        // Search bar for adding
        if (!_manageMode)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    onChanged: (v) => _searchCode(v.trim()),
                    decoration: InputDecoration(
                      hintText: '输入6位代码添加标的...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.add_circle_outline, size: 18),
                      suffixIcon: _addCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _addCtrl.clear(); setState(() { _searchResults = []; }); })
                        : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      filled: true, fillColor: const Color(0xFFF8F8F8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.content_paste, size: 20),
                  onPressed: isLoading ? null : _importFromClipboard,
                  tooltip: '从剪贴板导入',
                ),
              ]),
              if (_searching)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
              if (_searchResults.isNotEmpty)
                ..._searchResults.map((e) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.add_circle, color: Color(0xFF16A34A), size: 20),
                  title: Text('${e.value} (${e.key})', style: const TextStyle(fontSize: 14)),
                  trailing: store.etfPool.any((p) => Config.cleanCode(p) == e.key)
                    ? const Text('已添加', style: TextStyle(fontSize: 12, color: Colors.grey))
                    : const Icon(Icons.add, size: 18, color: Color(0xFF16A34A)),
                  onTap: store.etfPool.any((p) => Config.cleanCode(p) == e.key)
                    ? null
                    : () => _addFromSearch(e.key, e.value),
                )),
            ]),
          ),

        const Divider(height: 1),

        // Pool list
        if (isLoading && pool.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.only(top: 4),
            itemCount: pool.length,
            itemBuilder: (context, index) {
              final code = pool[index];
              final clean = Config.cleanCode(code);
              final name = store.displayName(code);
              final isSmall = Config.isSmall(code);
              final isSelected = _selected.contains(code);

              if (_manageMode) {
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (v) => setState(() {
                    if (v == true) { _selected.add(code); } else { _selected.remove(code); }
                  }),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Row(children: [
                    Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isSmall ? const Color(0xFFDC2626) : Colors.black87)),
                    const SizedBox(width: 6),
                    Text(clean, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                );
              }

              return Dismissible(
                key: Key(code),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (dir) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除标的'),
                      content: Text('确定删除 $name ($clean) 吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ) ?? false;
                },
                onDismissed: (_) => store.removeFromPool([code]),
                child: ListTile(
                  dense: true,
                  leading: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: isSmall ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text('${index + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSmall ? const Color(0xFF16A34A) : Colors.grey.shade600)),
                  ),
                  title: Row(children: [
                    Flexible(child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isSmall ? const Color(0xFFDC2626) : Colors.black87), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    Text(clean, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                  trailing: isSmall
                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)), child: const Text('核心', style: TextStyle(fontSize: 9, color: Color(0xFFB45309))))
                    : null,
                ),
              );
            },
          )),
      ]);
    });
  }
}

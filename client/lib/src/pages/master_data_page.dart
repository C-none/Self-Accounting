import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage> {
  bool busy = false;
  String? error;
  final Map<String, List<String>> categoryOrderOverrides = {};
  List<String>? memberOrderOverride;
  List<String>? accountOrderOverride;

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.controller.bootstrapData;
    return Scaffold(
      appBar: AppBar(title: const Text('基础资料管理')),
      body: bootstrap == null
          ? const Center(child: Text('基础数据未加载'))
          : ResponsiveListView(
              maxWidth: 920,
              children: [
                if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (busy) const LinearProgressIndicator(),
                _CategorySection(
                  categories: bootstrap.categories,
                  orderOverrides: categoryOrderOverrides,
                  onAddTop: (type) => _editCategory(type: type),
                  onAddChild: (parent) =>
                      _editCategory(type: parent.type, parentId: parent.id),
                  onEdit: (category) => _editCategory(category: category),
                  onReorder: _reorderCategory,
                  onDelete: (category) => _confirmDelete(
                    '分类',
                    category.name,
                    () => _deleteCategory(category),
                  ),
                ),
                const SizedBox(height: 16),
                _MemberSection(
                  members: bootstrap.members,
                  orderOverride: memberOrderOverride,
                  onAdd: () => _editMember(),
                  onEdit: (member) => _editMember(member: member),
                  onReorder: _reorderMembers,
                  onDelete: (member) => _confirmDelete(
                    '使用人',
                    member.name,
                    () => _deleteMember(member),
                  ),
                ),
                const SizedBox(height: 16),
                _AccountSection(
                  accounts: bootstrap.accounts,
                  orderOverride: accountOrderOverride,
                  onAdd: () => _editAccount(),
                  onEdit: (account) => _editAccount(account: account),
                  onReorder: _reorderAccounts,
                  onDelete: (account) => _confirmDelete(
                    '账户',
                    account.displayName,
                    () => _deleteAccount(account),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _run(Future<void> Function(String token) action) async {
    final token = widget.controller.token;
    if (token == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action(token);
      await widget.controller.refreshBootstrap();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _editCategory({
    Category? category,
    String type = 'expense',
    String? parentId,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CategoryDialog(
        categories: widget.controller.bootstrapData?.categories ?? const [],
        category: category,
        initialType: category?.type ?? type,
        initialParentId: category?.parentId.isEmpty == true
            ? parentId
            : category?.parentId ?? parentId,
      ),
    );
    if (result == null) {
      return;
    }
    await _run((token) async {
      if (category == null) {
        await widget.controller.api.createCategory(token, result);
      } else {
        await widget.controller.api.patchCategory(token, category.id, result);
      }
    });
  }

  Future<void> _editMember({Member? member}) async {
    final result = await _nameDialog(
      title: member == null ? '新增使用人' : '编辑使用人',
      label: '使用人名称',
      initialValue: member?.name ?? '',
    );
    if (result == null) {
      return;
    }
    await _run((token) async {
      final body = {'name': result};
      if (member == null) {
        await widget.controller.api.createMember(token, body);
      } else {
        await widget.controller.api.patchMember(token, member.id, body);
      }
    });
  }

  Future<void> _editAccount({LedgerAccount? account}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AccountDialog(account: account),
    );
    if (result == null) {
      return;
    }
    await _run((token) async {
      if (account == null) {
        await widget.controller.api.createAccount(token, result);
      } else {
        await widget.controller.api.patchAccount(token, account.id, result);
      }
    });
  }

  Future<void> _deleteCategory(Category category) async {
    await _run(
      (token) => widget.controller.api.deleteCategory(token, category.id),
    );
  }

  Future<void> _deleteMember(Member member) async {
    await _run((token) => widget.controller.api.deleteMember(token, member.id));
  }

  Future<void> _deleteAccount(LedgerAccount account) async {
    await _run(
      (token) => widget.controller.api.deleteAccount(token, account.id),
    );
  }

  Future<void> _reorderCategory(
    String type,
    String parentId,
    List<String> orderedIds,
  ) async {
    final token = widget.controller.token;
    final scopeKey = _categoryScopeKey(type, parentId);
    final previous = categoryOrderOverrides[scopeKey];
    setState(() {
      categoryOrderOverrides[scopeKey] = orderedIds;
      busy = true;
      error = null;
    });
    if (token == null) {
      _restoreCategoryOrder(scopeKey, previous);
      return;
    }
    try {
      await widget.controller.api.reorderCategories(
        token,
        type: type,
        parentId: parentId.isEmpty ? null : parentId,
        orderedIds: orderedIds,
      );
      await widget.controller.refreshBootstrap();
      if (mounted) {
        setState(() => categoryOrderOverrides.remove(scopeKey));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (previous == null) {
            categoryOrderOverrides.remove(scopeKey);
          } else {
            categoryOrderOverrides[scopeKey] = previous;
          }
          error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void _restoreCategoryOrder(String scopeKey, List<String>? previous) {
    setState(() {
      if (previous == null) {
        categoryOrderOverrides.remove(scopeKey);
      } else {
        categoryOrderOverrides[scopeKey] = previous;
      }
      busy = false;
      error = '当前无网络，请联网后重试';
    });
  }

  Future<void> _reorderMembers(List<String> orderedIds) async {
    final token = widget.controller.token;
    final previous = memberOrderOverride;
    setState(() {
      memberOrderOverride = orderedIds;
      busy = true;
      error = null;
    });
    if (token == null) {
      setState(() {
        memberOrderOverride = previous;
        busy = false;
        error = '当前无网络，请联网后重试';
      });
      return;
    }
    try {
      await widget.controller.api.reorderMembers(token, orderedIds);
      await widget.controller.refreshBootstrap();
      if (mounted) {
        setState(() => memberOrderOverride = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          memberOrderOverride = previous;
          error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _reorderAccounts(List<String> orderedIds) async {
    final token = widget.controller.token;
    final previous = accountOrderOverride;
    setState(() {
      accountOrderOverride = orderedIds;
      busy = true;
      error = null;
    });
    if (token == null) {
      setState(() {
        accountOrderOverride = previous;
        busy = false;
        error = '当前无网络，请联网后重试';
      });
      return;
    }
    try {
      await widget.controller.api.reorderAccounts(token, orderedIds);
      await widget.controller.refreshBootstrap();
      if (mounted) {
        setState(() => accountOrderOverride = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          accountOrderOverride = previous;
          error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<String?> _nameDialog({
    required String title,
    required String label,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    String type,
    String name,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除$type'),
        content: Text('确认删除“$name”？如果已有交易引用，服务端会拒绝删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await action();
    }
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.categories,
    required this.orderOverrides,
    required this.onAddTop,
    required this.onAddChild,
    required this.onEdit,
    required this.onReorder,
    required this.onDelete,
  });

  final List<Category> categories;
  final Map<String, List<String>> orderOverrides;
  final ValueChanged<String> onAddTop;
  final ValueChanged<Category> onAddChild;
  final ValueChanged<Category> onEdit;
  final void Function(String type, String parentId, List<String> orderedIds)
  onReorder;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    const types = {'expense': '支出', 'income': '收入', 'transfer': '转账'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final entry in types.entries) ...[
          _CategoryDirectionSection(
            type: entry.key,
            label: entry.value,
            categories: categories,
            orderOverrides: orderOverrides,
            onAddTop: () => onAddTop(entry.key),
            onAddChild: onAddChild,
            onEdit: onEdit,
            onReorder: onReorder,
            onDelete: onDelete,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CategoryDirectionSection extends StatelessWidget {
  const _CategoryDirectionSection({
    required this.type,
    required this.label,
    required this.categories,
    required this.orderOverrides,
    required this.onAddTop,
    required this.onAddChild,
    required this.onEdit,
    required this.onReorder,
    required this.onDelete,
  });

  final String type;
  final String label;
  final List<Category> categories;
  final Map<String, List<String>> orderOverrides;
  final VoidCallback onAddTop;
  final ValueChanged<Category> onAddChild;
  final ValueChanged<Category> onEdit;
  final void Function(String type, String parentId, List<String> orderedIds)
  onReorder;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    final topCategories = _orderedItems(
      categories.where((c) => c.type == type && c.isTopLevel).toList(),
      orderOverrides[_categoryScopeKey(type, '')],
      (category) => category.id,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            OutlinedButton.icon(
              onPressed: onAddTop,
              icon: const Icon(Icons.add),
              label: const Text('新增'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (topCategories.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('暂无分类', style: Theme.of(context).textTheme.bodyMedium),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: topCategories.length,
            onReorderItem: (oldIndex, newIndex) {
              onReorder(
                type,
                '',
                _reorderedIdsForDrag(
                  topCategories.map((item) => item.id).toList(),
                  oldIndex,
                  newIndex,
                ),
              );
            },
            itemBuilder: (context, index) {
              final category = topCategories[index];
              final children = _orderedItems(
                categories.where((c) => c.parentId == category.id).toList(),
                orderOverrides[_categoryScopeKey(type, category.id)],
                (category) => category.id,
              );
              return _CategoryGroupItem(
                key: ValueKey('category-group-${category.id}'),
                category: category,
                children: children,
                index: index,
                onAddChild: () => onAddChild(category),
                onEdit: onEdit,
                onReorderChildren: (orderedIds) =>
                    onReorder(type, category.id, orderedIds),
                onDelete: onDelete,
              );
            },
          ),
      ],
    );
  }
}

class _CategoryGroupItem extends StatelessWidget {
  const _CategoryGroupItem({
    super.key,
    required this.category,
    required this.children,
    required this.index,
    required this.onAddChild,
    required this.onEdit,
    required this.onReorderChildren,
    required this.onDelete,
  });

  final Category category;
  final List<Category> children;
  final int index;
  final VoidCallback onAddChild;
  final ValueChanged<Category> onEdit;
  final ValueChanged<List<String>> onReorderChildren;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryCard(
          category: category,
          dragIndex: index,
          subtitle: children.isEmpty ? '无二级分类' : '${children.length} 个二级分类',
          onAddChild: onAddChild,
          onEdit: () => onEdit(category),
          onDelete: () => onDelete(category),
        ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              buildDefaultDragHandles: false,
              itemCount: children.length,
              onReorderItem: (oldIndex, newIndex) {
                onReorderChildren(
                  _reorderedIdsForDrag(
                    children.map((item) => item.id).toList(),
                    oldIndex,
                    newIndex,
                  ),
                );
              },
              itemBuilder: (context, index) {
                final child = children[index];
                return Padding(
                  key: ValueKey('category-child-${child.id}'),
                  padding: const EdgeInsets.only(top: 8),
                  child: _CategoryCard(
                    category: child,
                    dragIndex: index,
                    subtitle: '二级分类',
                    onEdit: () => onEdit(child),
                    onDelete: () => onDelete(child),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.dragIndex,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
    this.onAddChild,
  });

  final Category category;
  final int dragIndex;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onAddChild;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _DragHandle(index: dragIndex),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onAddChild != null)
              IconButton(
                tooltip: '新增二级分类',
                onPressed: onAddChild,
                icon: const Icon(Icons.add),
              ),
            IconButton(
              tooltip: '编辑',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.members,
    required this.orderOverride,
    required this.onAdd,
    required this.onEdit,
    required this.onReorder,
    required this.onDelete,
  });

  final List<Member> members;
  final List<String>? orderOverride;
  final VoidCallback onAdd;
  final ValueChanged<Member> onEdit;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<Member> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleSection<Member>(
      title: '使用人',
      items: members,
      orderOverride: orderOverride,
      itemId: (item) => item.id,
      itemTitle: (item) => item.name,
      onAdd: onAdd,
      onEdit: onEdit,
      onReorder: onReorder,
      onDelete: onDelete,
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.accounts,
    required this.orderOverride,
    required this.onAdd,
    required this.onEdit,
    required this.onReorder,
    required this.onDelete,
  });

  final List<LedgerAccount> accounts;
  final List<String>? orderOverride;
  final VoidCallback onAdd;
  final ValueChanged<LedgerAccount> onEdit;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<LedgerAccount> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleSection<LedgerAccount>(
      title: '账户',
      items: accounts,
      orderOverride: orderOverride,
      itemId: (item) => item.id,
      itemTitle: (item) => item.displayName,
      onAdd: onAdd,
      onEdit: onEdit,
      onReorder: onReorder,
      onDelete: onDelete,
    );
  }
}

class _SimpleSection<T> extends StatelessWidget {
  const _SimpleSection({
    required this.title,
    required this.items,
    required this.orderOverride,
    required this.itemId,
    required this.itemTitle,
    required this.onAdd,
    required this.onEdit,
    required this.onReorder,
    required this.onDelete,
  });

  final String title;
  final List<T> items;
  final List<String>? orderOverride;
  final String Function(T item) itemId;
  final String Function(T) itemTitle;
  final VoidCallback onAdd;
  final ValueChanged<T> onEdit;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<T> onDelete;

  @override
  Widget build(BuildContext context) {
    final orderedItems = _orderedItems(items, orderOverride, itemId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (orderedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '暂无$title',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: orderedItems.length,
            onReorderItem: (oldIndex, newIndex) {
              onReorder(
                _reorderedIdsForDrag(
                  orderedItems.map(itemId).toList(),
                  oldIndex,
                  newIndex,
                ),
              );
            },
            itemBuilder: (context, index) {
              final item = orderedItems[index];
              return Padding(
                key: ValueKey('$title-${itemId(item)}'),
                padding: EdgeInsets.only(
                  bottom: index == orderedItems.length - 1 ? 0 : 8,
                ),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        _DragHandle(index: index),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            itemTitle(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: '编辑',
                          onPressed: () => onEdit(item),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '删除',
                          onPressed: () => onDelete(item),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '长按拖动排序',
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: const SizedBox(width: 40, height: 40, child: Icon(Icons.menu)),
      ),
    );
  }
}

String _categoryScopeKey(String type, String parentId) => '$type|$parentId';

List<T> _orderedItems<T>(
  List<T> items,
  List<String>? orderedIds,
  String Function(T item) itemId,
) {
  if (orderedIds == null || orderedIds.isEmpty) {
    return items;
  }
  final byId = {for (final item in items) itemId(item): item};
  final usedIds = <String>{};
  final ordered = <T>[];
  for (final id in orderedIds) {
    final item = byId[id];
    if (item != null && usedIds.add(id)) {
      ordered.add(item);
    }
  }
  for (final item in items) {
    if (usedIds.add(itemId(item))) {
      ordered.add(item);
    }
  }
  return ordered;
}

List<String> _reorderedIdsForDrag(
  List<String> ids,
  int oldIndex,
  int newIndex,
) {
  final next = List<String>.from(ids);
  final item = next.removeAt(oldIndex);
  next.insert(newIndex, item);
  return next;
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.categories,
    required this.initialType,
    this.category,
    this.initialParentId,
  });

  final List<Category> categories;
  final Category? category;
  final String initialType;
  final String? initialParentId;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController nameController;
  late String type;
  String? parentId;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.category?.name ?? '');
    type = widget.initialType;
    parentId = widget.initialParentId?.isEmpty == true
        ? null
        : widget.initialParentId;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topCategories = widget.categories
        .where(
          (c) => c.type == type && c.isTopLevel && c.id != widget.category?.id,
        )
        .toList();
    return AlertDialog(
      title: Text(widget.category == null ? '新增分类' : '编辑分类'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: '分类名称'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: '方向'),
            items: const [
              DropdownMenuItem(value: 'expense', child: Text('支出')),
              DropdownMenuItem(value: 'income', child: Text('收入')),
              DropdownMenuItem(value: 'transfer', child: Text('转账')),
            ],
            onChanged: (value) => setState(() {
              type = value!;
              parentId = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('category-parent-$type-$parentId'),
            initialValue: parentId,
            decoration: const InputDecoration(labelText: '层级'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('一级分类')),
              ...topCategories.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text('二级分类，父级：${c.name}'),
                ),
              ),
            ],
            onChanged: (value) => setState(() => parentId = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              return;
            }
            Navigator.of(
              context,
            ).pop({'name': name, 'type': type, 'parent_id': parentId});
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.account});

  final LedgerAccount? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController nameController;
  late final TextEditingController maskedController;
  late final String accountType;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.account?.name ?? '');
    accountType = widget.account?.type.isNotEmpty == true
        ? widget.account!.type
        : 'bank';
    maskedController = TextEditingController(
      text: widget.account?.cardTail ?? '',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    maskedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.account == null ? '新增账户' : '编辑账户'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '银行名称',
              hintText: '如 工商银行',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: maskedController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: '银行卡尾号（可选）',
              hintText: '如 0973',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              return;
            }
            Navigator.of(context).pop({
              'name': name,
              'type': accountType,
              'masked_identifier': normalizeCardTail(maskedController.text),
            });
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

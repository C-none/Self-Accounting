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
                  onAddTop: (type) => _editCategory(type: type),
                  onAddChild: (parent) =>
                      _editCategory(type: parent.type, parentId: parent.id),
                  onEdit: (category) => _editCategory(category: category),
                  onDelete: (category) => _confirmDelete(
                    '分类',
                    category.name,
                    () => _deleteCategory(category),
                  ),
                ),
                const SizedBox(height: 16),
                _MemberSection(
                  members: bootstrap.members,
                  onAdd: () => _editMember(),
                  onEdit: (member) => _editMember(member: member),
                  onDelete: (member) => _confirmDelete(
                    '使用人',
                    member.name,
                    () => _deleteMember(member),
                  ),
                ),
                const SizedBox(height: 16),
                _AccountSection(
                  accounts: bootstrap.accounts,
                  onAdd: () => _editAccount(),
                  onEdit: (account) => _editAccount(account: account),
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
    required this.onAddTop,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Category> categories;
  final ValueChanged<String> onAddTop;
  final ValueChanged<Category> onAddChild;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    const types = {'expense': '支出', 'income': '收入', 'transfer': '转账'};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分类', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in types.entries)
                  OutlinedButton.icon(
                    onPressed: () => onAddTop(entry.key),
                    icon: const Icon(Icons.add),
                    label: Text('新增${entry.value}一级分类'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in types.entries) ...[
              Text(entry.value, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final top in categories.where(
                (c) => c.type == entry.key && c.isTopLevel,
              ))
                _CategoryTile(
                  category: top,
                  children: categories
                      .where((c) => c.parentId == top.id)
                      .toList(),
                  onAddChild: () => onAddChild(top),
                  onEdit: onEdit,
                  onDelete: onDelete,
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.children,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
  });

  final Category category;
  final List<Category> children;
  final VoidCallback onAddChild;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(category.name),
      subtitle: Text(children.isEmpty ? '无二级分类' : '${children.length} 个二级分类'),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: '新增二级分类',
            onPressed: onAddChild,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '编辑',
            onPressed: () => onEdit(category),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => onDelete(category),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      children: [
        for (final child in children)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 8),
            title: Text(child.name),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '编辑',
                  onPressed: () => onEdit(child),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: () => onDelete(child),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.members,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Member> members;
  final VoidCallback onAdd;
  final ValueChanged<Member> onEdit;
  final ValueChanged<Member> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleSection<Member>(
      title: '使用人',
      items: members,
      itemTitle: (item) => item.name,
      onAdd: onAdd,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.accounts,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<LedgerAccount> accounts;
  final VoidCallback onAdd;
  final ValueChanged<LedgerAccount> onEdit;
  final ValueChanged<LedgerAccount> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleSection<LedgerAccount>(
      title: '账户',
      items: accounts,
      itemTitle: (item) => item.displayName,
      onAdd: onAdd,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _SimpleSection<T> extends StatelessWidget {
  const _SimpleSection({
    required this.title,
    required this.items,
    required this.itemTitle,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final List<T> items;
  final String Function(T) itemTitle;
  final VoidCallback onAdd;
  final ValueChanged<T> onEdit;
  final ValueChanged<T> onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
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
            for (final item in items)
              ListTile(
                title: Text(itemTitle(item)),
                trailing: Wrap(
                  spacing: 4,
                  children: [
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
          ],
        ),
      ),
    );
  }
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

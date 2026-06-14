import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/pages/transaction_form_page.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final TextEditingController keywordController = TextEditingController();
  bool loading = true;
  String? error;
  String? direction = 'expense';
  String? categoryL1Id;
  String? memberId;
  String? accountId;
  late final DateTime defaultFromDate;
  late final DateTime defaultToDate;
  DateTime? fromDate;
  DateTime? toDate;
  TransactionPage? page;
  final Map<String, Uint8List> transactionThumbnails = {};
  final Set<String> collapsedDates = {};
  int loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    defaultToDate = DateTime(now.year, now.month, now.day);
    final from = defaultToDate.subtract(const Duration(days: 7));
    defaultFromDate = DateTime(from.year, from.month, from.day);
    _load();
  }

  @override
  void dispose() {
    keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.controller.bootstrapData;
    return Scaffold(
      appBar: AppBar(
        title: const Text('交易'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: bootstrap == null ? null : () => _openForm(null),
        icon: const Icon(Icons.add),
        label: const Text('新增'),
      ),
      body: bootstrap == null
          ? const Center(child: Text('基础数据未加载'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ResponsiveListView(
                bottomPadding: 104,
                children: [
                  _FilterPanel(
                    bootstrap: bootstrap,
                    direction: direction,
                    categoryL1Id: categoryL1Id,
                    memberId: memberId,
                    accountId: accountId,
                    keywordController: keywordController,
                    fromDate: fromDate,
                    toDate: toDate,
                    defaultFromDate: defaultFromDate,
                    defaultToDate: defaultToDate,
                    onChanged:
                        (nextDirection, nextCategory, nextMember, nextAccount) {
                          setState(() {
                            direction = nextDirection;
                            categoryL1Id = nextCategory;
                            memberId = nextMember;
                            accountId = nextAccount;
                          });
                          _load();
                        },
                    onDateChanged: (nextFrom, nextTo) {
                      setState(() {
                        fromDate = nextFrom;
                        toDate = nextTo;
                      });
                      _load();
                    },
                    onSearch: _load,
                  ),
                  const SizedBox(height: 12),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                  else if ((page?.items ?? const []).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('暂无交易')),
                    )
                  else
                    ..._transactionWidgets(bootstrap),
                ],
              ),
            ),
    );
  }

  Future<void> _load() async {
    final token = widget.controller.token;
    if (token == null) {
      return;
    }
    final requestId = ++loadRequestId;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final effectiveFrom = fromDate ?? defaultFromDate;
      final effectiveTo = toDate ?? defaultToDate;
      final next = await widget.controller.api.listTransactions(
        token,
        direction: direction,
        categoryL1Id: categoryL1Id,
        memberId: memberId,
        accountId: accountId,
        keyword: keywordController.text.trim(),
        from:
            DateTime(
              effectiveFrom.year,
              effectiveFrom.month,
              effectiveFrom.day,
            ).millisecondsSinceEpoch ~/
            1000,
        to:
            DateTime(
              effectiveTo.year,
              effectiveTo.month,
              effectiveTo.day,
              23,
              59,
              59,
            ).millisecondsSinceEpoch ~/
            1000,
      );
      if (mounted && requestId == loadRequestId) {
        setState(() {
          page = next;
          transactionThumbnails.clear();
        });
        unawaited(_loadThumbnailsFor(token, next.items, requestId));
      }
    } catch (e) {
      if (mounted && requestId == loadRequestId) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && requestId == loadRequestId) {
        setState(() => loading = false);
      }
    }
  }

  List<Widget> _transactionWidgets(BootstrapData bootstrap) {
    final widgets = <Widget>[];
    String? lastDate;
    for (final item in page!.items) {
      final date = formatDateOnly(
        DateTime.fromMillisecondsSinceEpoch(item.transactionTime * 1000),
      );
      if (date != lastDate) {
        lastDate = date;
        widgets.add(
          _DateDivider(
            date: date,
            collapsed: collapsedDates.contains(date),
            onToggle: () {
              setState(() {
                if (!collapsedDates.add(date)) {
                  collapsedDates.remove(date);
                }
              });
            },
          ),
        );
      }
      if (collapsedDates.contains(date)) {
        continue;
      }
      widgets.add(
        _TransactionTile(
          item: item,
          bootstrap: bootstrap,
          thumbnailBytes: transactionThumbnails[item.id],
          onTap: () => _openForm(item),
        ),
      );
    }
    return widgets;
  }

  Future<void> _loadThumbnailsFor(
    String token,
    List<LedgerTransaction> items,
    int requestId,
  ) async {
    for (final item in items) {
      if (!mounted || requestId != loadRequestId) {
        return;
      }
      try {
        final attachments = await widget.controller.api.listAttachments(
          token,
          item.id,
        );
        if (attachments.isEmpty) {
          continue;
        }
        final bytes = await widget.controller.api.attachmentBytes(
          token,
          attachments.first.id,
          thumbnail: true,
        );
        if (!mounted || requestId != loadRequestId) {
          return;
        }
        setState(() => transactionThumbnails[item.id] = bytes);
      } catch (_) {
        // Thumbnail failures must not block reading or editing transactions.
      }
    }
  }

  Future<void> _openForm(LedgerTransaction? item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionFormPage(
          controller: widget.controller,
          transaction: item,
        ),
      ),
    );
    if (changed == true) {
      _load();
    }
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.bootstrap,
    required this.direction,
    required this.categoryL1Id,
    required this.memberId,
    required this.accountId,
    required this.keywordController,
    required this.fromDate,
    required this.toDate,
    required this.defaultFromDate,
    required this.defaultToDate,
    required this.onChanged,
    required this.onDateChanged,
    required this.onSearch,
  });

  final BootstrapData bootstrap;
  final String? direction;
  final String? categoryL1Id;
  final String? memberId;
  final String? accountId;
  final TextEditingController keywordController;
  final DateTime? fromDate;
  final DateTime? toDate;
  final DateTime defaultFromDate;
  final DateTime defaultToDate;
  final void Function(String?, String?, String?, String?) onChanged;
  final void Function(DateTime?, DateTime?) onDateChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final categories = bootstrap.categories
        .where(
          (c) => c.isTopLevel && (direction == null || c.type == direction),
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spacing = constraints.maxWidth >= 560 ? 10.0 : 8.0;
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final controlWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final controls = [
              _DirectionDropdown(
                value: direction,
                onChanged: (value) =>
                    onChanged(value, null, memberId, accountId),
              ),
              _CategoryDropdown(
                value: categoryL1Id,
                categories: categories,
                onChanged: (value) =>
                    onChanged(direction, value, memberId, accountId),
              ),
              _MemberDropdown(
                value: memberId,
                members: bootstrap.members,
                onChanged: (value) =>
                    onChanged(direction, categoryL1Id, value, accountId),
              ),
              _AccountDropdown(
                value: accountId,
                accounts: bootstrap.accounts,
                onChanged: (value) =>
                    onChanged(direction, categoryL1Id, memberId, value),
              ),
            ];
            return Column(
              children: [
                Wrap(
                  spacing: spacing,
                  runSpacing: 8,
                  children: [
                    for (final control in controls)
                      SizedBox(width: controlWidth, child: control),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DateInputField(
                        label: '起始日期',
                        value: fromDate,
                        defaultDate: defaultFromDate,
                        onChanged: (date) => onDateChanged(date, toDate),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateInputField(
                        label: '结束日期',
                        value: toDate,
                        defaultDate: defaultToDate,
                        onChanged: (date) => onDateChanged(fromDate, date),
                      ),
                    ),
                    IconButton(
                      tooltip: '清除日期',
                      onPressed: fromDate == null && toDate == null
                          ? null
                          : () => onDateChanged(null, null),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keywordController,
                  decoration: InputDecoration(
                    labelText: '关键词',
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: onSearch,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => onSearch(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DateInputField extends StatelessWidget {
  const _DateInputField({
    required this.label,
    required this.value,
    required this.defaultDate,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final DateTime defaultDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label-${value?.millisecondsSinceEpoch ?? 0}'),
      initialValue: value == null ? '' : formatCompactDate(value!),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: formatCompactDate(defaultDate),
        suffixIcon: IconButton(
          tooltip: '选择$label',
          onPressed: () => _pickDate(context),
          icon: const Icon(Icons.arrow_drop_down),
        ),
      ),
      onChanged: (raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          onChanged(null);
          return;
        }
        final parsed = parseCompactDate(trimmed);
        if (parsed != null) {
          onChanged(parsed);
        }
      },
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final initial = value ?? defaultDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({
    required this.date,
    required this.collapsed,
    required this.onToggle,
  });

  final String date;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
          const SizedBox(width: 8),
          Text(date, style: Theme.of(context).textTheme.titleSmall),
          IconButton(
            tooltip: collapsed ? '展开$date' : '折叠$date',
            onPressed: onToggle,
            icon: Icon(
              collapsed
                  ? Icons.keyboard_arrow_right
                  : Icons.keyboard_arrow_down,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.item,
    required this.bootstrap,
    required this.thumbnailBytes,
    required this.onTap,
  });

  final LedgerTransaction item;
  final BootstrapData bootstrap;
  final Uint8List? thumbnailBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = nameOf(bootstrap.categories, item.categoryL1Id);
    final member = nameOf(bootstrap.members, item.memberId);
    final account = nameOf(bootstrap.accounts, item.accountId);
    final color = item.direction == 'income'
        ? Colors.green.shade700
        : item.direction == 'transfer'
        ? Colors.blueGrey
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: onTap,
          title: Text(
            item.counterparty.isEmpty ? category : item.counterparty,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${formatDateTime(item.transactionTime)} · $category · $member · $account',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thumbnailBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    thumbnailBytes!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                formatMoney(item.amountCent),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionDropdown extends StatelessWidget {
  const _DirectionDropdown({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('filter-direction-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '方向'),
      items: const [
        DropdownMenuItem(value: 'expense', child: Text('支出')),
        DropdownMenuItem(value: 'income', child: Text('收入')),
        DropdownMenuItem(value: 'transfer', child: Text('转账')),
      ],
      onChanged: onChanged,
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String? value;
  final List<Category> categories;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('filter-category-$value-${categories.length}'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '分类'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部')),
        ...categories.map(
          (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _MemberDropdown extends StatelessWidget {
  const _MemberDropdown({
    required this.value,
    required this.members,
    required this.onChanged,
  });

  final String? value;
  final List<Member> members;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('filter-member-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '使用人'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部')),
        ...members.map(
          (m) => DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final String? value;
  final List<LedgerAccount> accounts;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('filter-account-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '账户'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部')),
        ...accounts.map(
          (a) => DropdownMenuItem<String?>(
            value: a.id,
            child: Text(a.displayName),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

String nameOf<T>(List<T> items, String id) {
  for (final item in items) {
    if (item is Category && item.id == id) {
      return item.name;
    }
    if (item is Member && item.id == id) {
      return item.name;
    }
    if (item is LedgerAccount && item.id == id) {
      return item.displayName;
    }
  }
  return id;
}

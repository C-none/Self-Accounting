import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ledger_client/src/api_client.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/sms/sms_platform.dart';
import 'package:ledger_client/src/sms/sms_templates.dart';
import 'package:ledger_client/src/widgets/category_picker.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class SmsImportPage extends StatefulWidget {
  const SmsImportPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SmsImportPage> createState() => _SmsImportPageState();
}

class _SmsImportPageState extends State<SmsImportPage> {
  final SmsPlatformAdapter adapter = SmsPlatformAdapter();
  final SmsTemplateStore templateStore = SmsTemplateStore();
  final SmsImportedHashStore importedHashStore = SmsImportedHashStore();
  Timer? timer;
  bool loading = true;
  bool supported = false;
  bool hasPermission = false;
  bool selectionMode = false;
  bool importingSelected = false;
  String? error;
  String? notice;
  List<SmsCandidate> candidates = [];
  final Set<String> selectedHashes = <String>{};
  late DateTime filterFromDate;
  late DateTime filterToDate;
  String? bankNameFilter;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    filterToDate = DateTime(today.year, today.month, today.day);
    final from = filterToDate.subtract(const Duration(days: 7));
    filterFromDate = DateTime(from.year, from.month, from.day);
    _initialize();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('短信导入'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading || importingSelected ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ResponsiveListView(
        maxWidth: kFormMaxWidth,
        children: [
          if (loading)
            const LinearProgressIndicator()
          else if (!supported)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('当前平台不支持短信导入')),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: hasPermission || importingSelected
                      ? null
                      : _requestPermission,
                  icon: const Icon(Icons.verified_user),
                  label: const Text('短信权限'),
                ),
                FilledButton.icon(
                  onPressed: hasPermission && !importingSelected ? _scan : null,
                  icon: const Icon(Icons.sms),
                  label: const Text('重新扫描'),
                ),
                OutlinedButton.icon(
                  onPressed: loading || importingSelected
                      ? null
                      : _clearHiddenSmsRecords,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('清除本机短信隐藏记录'),
                ),
                if (candidates.isNotEmpty && !selectionMode)
                  OutlinedButton.icon(
                    onPressed: importingSelected ? null : _enterSelectionMode,
                    icon: const Icon(Icons.checklist),
                    label: const Text('多选'),
                  ),
                if (selectionMode) ...[
                  OutlinedButton.icon(
                    onPressed: importingSelected ? null : _toggleSelectAll,
                    icon: Icon(
                      _allVisibleSelected ? Icons.remove_done : Icons.done_all,
                    ),
                    label: Text(_allVisibleSelected ? '取消全选' : '全选'),
                  ),
                  FilledButton.icon(
                    onPressed: selectedHashes.isEmpty || importingSelected
                        ? null
                        : _importSelected,
                    icon: const Icon(Icons.file_upload),
                    label: Text(
                      importingSelected
                          ? '导入中'
                          : '导入选中(${selectedHashes.length})',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: importingSelected ? null : _exitSelectionMode,
                    icon: const Icon(Icons.close),
                    label: const Text('退出多选'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _SmsFilterPanel(
              bootstrap: widget.controller.bootstrapData,
              fromDate: filterFromDate,
              toDate: filterToDate,
              bankName: bankNameFilter,
              onChanged: (from, to, bank) {
                setState(() {
                  filterFromDate = from;
                  filterToDate = to;
                  bankNameFilter = bank;
                  candidates = [];
                  selectedHashes.clear();
                  selectionMode = false;
                  notice = null;
                });
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (notice != null) ...[
              const SizedBox(height: 12),
              Text(
                notice!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
            if (importingSelected) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('暂无候选短信')),
              )
            else
              ...candidates.map(
                (candidate) => _SmsCandidateTile(
                  candidate: candidate,
                  selectionMode: selectionMode,
                  selected: selectedHashes.contains(candidate.smsHash),
                  onTap: () => selectionMode
                      ? _toggleCandidate(candidate)
                      : _confirm(candidate),
                  onLongPress: () => _enterSelectionMode(candidate),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _initialize() async {
    setState(() {
      loading = true;
      error = null;
      notice = null;
    });
    try {
      supported = await adapter.isSupported();
      hasPermission = supported && await adapter.checkPermissions();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      loading = true;
      error = null;
      notice = null;
    });
    try {
      hasPermission = await adapter.requestPermissions();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _scan({bool setBusy = true}) async {
    final bootstrap = widget.controller.bootstrapData;
    if (bootstrap == null) {
      return;
    }
    if (setBusy) {
      setState(() {
        loading = true;
        error = null;
        notice = null;
      });
    }
    try {
      await widget.controller.refreshBootstrap();
      if (filterFromDate.isAfter(filterToDate)) {
        throw Exception('导入起始日期不能晚于结束日期');
      }
      final templates = await templateStore.load();
      final currentBootstrap = widget.controller.bootstrapData ?? bootstrap;
      final rows = await adapter.readRecentRows(
        fromDate: filterFromDate,
        limit: 200,
      );
      final rowCount = rows.where(_rowInFilterRange).length;
      final nonEmptyBodyCount = rows
          .where(_rowInFilterRange)
          .where((row) => (row['body']?.toString().trim() ?? '').isNotEmpty)
          .length;
      final icbcSenderCount = rows
          .where(_rowInFilterRange)
          .where(
            (row) =>
                normalizeSmsSender(row['sender']?.toString() ?? '') == '95588',
          )
          .length;
      final templateMatchCount = rows
          .where(_rowInFilterRange)
          .where(
            (row) =>
                matchEnabledSmsTemplateWithValues(
                  body: row['body']?.toString() ?? '',
                  sender: row['sender']?.toString() ?? '',
                  templates: templates,
                ) !=
                null,
          )
          .length;
      final next = parseSmsRows(
        rows,
        currentBootstrap,
        fromDate: filterFromDate,
        toDate: filterToDate,
        bankName: bankNameFilter,
        templates: templates,
        requireTemplate: true,
      );
      final importedHashes = await importedHashStore.load();
      final visible = next
          .where((candidate) => !importedHashes.contains(candidate.smsHash))
          .toList();
      final suggested = await _withCategorySuggestions(visible);
      final hiddenCount = next.length - visible.length;
      if (mounted) {
        setState(() {
          candidates = suggested;
          selectedHashes.clear();
          selectionMode = false;
          error = null;
          notice = suggested.isEmpty
              ? '扫描${formatCompactDate(filterFromDate)}-${formatCompactDate(filterToDate)}：读取${rows.length}条，范围内$rowCount条，95588 $icbcSenderCount条，正文$nonEmptyBodyCount条，模板${templates.length}个，匹配$templateMatchCount条，候选${next.length}条，隐藏$hiddenCount条'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (setBusy && mounted) {
        setState(() => loading = false);
      }
    }
  }

  bool _rowInFilterRange(Map<String, dynamic> row) {
    final dateMillis = (row['dateMillis'] as num?)?.toInt() ?? 0;
    final fromMillis = DateTime(
      filterFromDate.year,
      filterFromDate.month,
      filterFromDate.day,
    ).millisecondsSinceEpoch;
    final toMillis = DateTime(
      filterToDate.year,
      filterToDate.month,
      filterToDate.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;
    return dateMillis >= fromMillis && dateMillis <= toMillis;
  }

  Future<void> _poll() async {
    if (!hasPermission || loading) {
      return;
    }
    final bootstrap = widget.controller.bootstrapData;
    if (bootstrap == null) {
      return;
    }
    try {
      final templates = await templateStore.load();
      final next = await adapter.pollBroadcasts(
        bootstrap: bootstrap,
        fromDate: filterFromDate,
        toDate: filterToDate,
        bankName: bankNameFilter,
        templates: templates,
        requireTemplate: true,
      );
      final importedHashes = await importedHashStore.load();
      final visible = next
          .where((candidate) => !importedHashes.contains(candidate.smsHash))
          .toList();
      if (visible.isEmpty || !mounted) {
        return;
      }
      final suggested = await _withCategorySuggestions(visible);
      if (!mounted) {
        return;
      }
      final hashes = candidates.map((c) => c.smsHash).toSet();
      setState(() {
        candidates = [
          ...suggested.where((c) => hashes.add(c.smsHash)),
          ...candidates,
        ];
      });
    } catch (_) {}
  }

  Future<List<SmsCandidate>> _withCategorySuggestions(
    List<SmsCandidate> values,
  ) async {
    final token = widget.controller.token;
    if (token == null || values.isEmpty) {
      return values;
    }
    try {
      final suggestions = await widget.controller.api.suggestCategories(
        token,
        categorySuggestionItemsForSms(values),
      );
      return applyCategorySuggestions(values, suggestions);
    } catch (_) {
      return values;
    }
  }

  Future<void> _clearHiddenSmsRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机短信隐藏记录'),
        content: const Text('已导入交易不会删除。清除后可重新扫描短信。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await importedHashStore.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        candidates = [];
        selectedHashes.clear();
        selectionMode = false;
        error = null;
        notice = '已清除本机短信隐藏记录，请重新扫描';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          notice = null;
        });
      }
    }
  }

  Future<void> _confirm(SmsCandidate candidate) async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SmsConfirmPage(controller: widget.controller, candidate: candidate),
      ),
    );
    if (imported == true && mounted) {
      await importedHashStore.addAll([candidate.smsHash]);
      setState(() {
        candidates = candidates
            .where((c) => c.smsHash != candidate.smsHash)
            .toList();
        selectedHashes.remove(candidate.smsHash);
      });
    }
  }

  bool get _allVisibleSelected =>
      candidates.isNotEmpty &&
      candidates.every((c) => selectedHashes.contains(c.smsHash));

  void _enterSelectionMode([SmsCandidate? initial]) {
    setState(() {
      selectionMode = true;
      notice = null;
      if (initial != null) {
        selectedHashes.add(initial.smsHash);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      selectionMode = false;
      selectedHashes.clear();
      notice = null;
    });
  }

  void _toggleCandidate(SmsCandidate candidate) {
    setState(() {
      if (!selectedHashes.add(candidate.smsHash)) {
        selectedHashes.remove(candidate.smsHash);
      }
      notice = null;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allVisibleSelected) {
        selectedHashes.clear();
      } else {
        selectedHashes
          ..clear()
          ..addAll(candidates.map((c) => c.smsHash));
      }
      notice = null;
    });
  }

  Future<void> _importSelected() async {
    final token = widget.controller.token;
    if (token == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    final selected = candidates
        .where((candidate) => selectedHashes.contains(candidate.smsHash))
        .toList();
    if (selected.isEmpty) {
      return;
    }
    setState(() {
      importingSelected = true;
      error = null;
      notice = null;
    });

    var importedCount = 0;
    var duplicateCount = 0;
    final handledHashes = <String>{};
    try {
      for (final candidate in selected) {
        try {
          await widget.controller.api.importSms(
            token,
            smsImportBody(candidate),
          );
          importedCount++;
          handledHashes.add(candidate.smsHash);
        } catch (e) {
          if (e is ApiException && e.code == 'duplicate_sms_import') {
            duplicateCount++;
            handledHashes.add(candidate.smsHash);
            continue;
          }
          rethrow;
        }
      }
      if (handledHashes.isNotEmpty) {
        await importedHashStore.addAll(handledHashes);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        candidates = candidates
            .where((candidate) => !handledHashes.contains(candidate.smsHash))
            .toList();
        selectedHashes.removeAll(handledHashes);
        if (selectedHashes.isEmpty) {
          selectionMode = false;
        }
        final parts = <String>[];
        if (importedCount > 0) {
          parts.add('已导入 $importedCount 条');
        }
        if (duplicateCount > 0) {
          parts.add('跳过重复 $duplicateCount 条');
        }
        notice = parts.isEmpty ? null : parts.join('，');
      });
    } catch (e) {
      if (handledHashes.isNotEmpty) {
        await importedHashStore.addAll(handledHashes);
      }
      if (mounted) {
        setState(() {
          candidates = candidates
              .where((candidate) => !handledHashes.contains(candidate.smsHash))
              .toList();
          selectedHashes.removeAll(handledHashes);
          error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => importingSelected = false);
      }
    }
  }
}

class _SmsFilterPanel extends StatelessWidget {
  const _SmsFilterPanel({
    required this.bootstrap,
    required this.fromDate,
    required this.toDate,
    required this.bankName,
    required this.onChanged,
  });

  final BootstrapData? bootstrap;
  final DateTime fromDate;
  final DateTime toDate;
  final String? bankName;
  final void Function(DateTime from, DateTime to, String? bank) onChanged;

  @override
  Widget build(BuildContext context) {
    final bankNames = <String>[];
    for (final account in bootstrap?.accounts ?? const <LedgerAccount>[]) {
      final name = account.name.trim();
      if (name.isNotEmpty &&
          !bankNames.any((item) => bankNameMatches(item, name))) {
        bankNames.add(name);
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('导入过滤', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ResponsiveFieldGrid(
              children: [
                _SmsDateInputField(
                  label: '起始日期',
                  value: fromDate,
                  onChanged: (value) => onChanged(value, toDate, bankName),
                ),
                _SmsDateInputField(
                  label: '结束日期',
                  value: toDate,
                  onChanged: (value) => onChanged(fromDate, value, bankName),
                ),
                DropdownButtonFormField<String?>(
                  key: ValueKey('sms-bank-$bankName-${bankNames.length}'),
                  initialValue: bankName,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '导入银行'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('全部银行'),
                    ),
                    ...bankNames.map(
                      (name) => DropdownMenuItem<String?>(
                        value: name,
                        child: Text(name),
                      ),
                    ),
                  ],
                  onChanged: (value) => onChanged(fromDate, toDate, value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsDateInputField extends StatelessWidget {
  const _SmsDateInputField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('sms-$label-${value.millisecondsSinceEpoch}'),
      initialValue: formatCompactDate(value),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYYMMDD',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: IconButton(
          tooltip: '选择$label',
          onPressed: () => _pickDate(context),
          icon: const Icon(Icons.arrow_drop_down),
        ),
      ),
      onChanged: (raw) {
        final parsed = parseCompactDate(raw);
        if (parsed != null) {
          onChanged(parsed);
        }
      },
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }
}

class _SmsCandidateTile extends StatelessWidget {
  const _SmsCandidateTile({
    required this.candidate,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final SmsCandidate candidate;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          leading: selectionMode
              ? Checkbox(value: selected, onChanged: (_) => onTap())
              : null,
          title: Text(
            candidate.counterparty.isEmpty ? '短信候选' : candidate.counterparty,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              '${formatDateTime(candidate.smsTime)} · ${candidate.bankName} ${candidate.accountHint}'
                  .trim(),
              '短信原文：${candidate.rawBody}',
            ].join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(formatMoney(candidate.amountCent)),
        ),
      ),
    );
  }
}

class SmsConfirmPage extends StatefulWidget {
  const SmsConfirmPage({
    super.key,
    required this.controller,
    required this.candidate,
  });

  final AppController controller;
  final SmsCandidate candidate;

  @override
  State<SmsConfirmPage> createState() => _SmsConfirmPageState();
}

class _SmsConfirmPageState extends State<SmsConfirmPage> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController counterpartyController;
  late final TextEditingController descriptionController;
  late String direction;
  late String categoryL1Id;
  String? categoryL2Id;
  late String memberId;
  late String accountId;
  bool submitting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    direction = c.direction;
    categoryL1Id = c.categoryL1Id;
    categoryL2Id = c.categoryL2Id;
    memberId = c.memberId;
    accountId = c.accountId;
    amountController = TextEditingController(
      text: (c.amountCent / 100).toStringAsFixed(2),
    );
    counterpartyController = TextEditingController(text: c.counterparty);
    descriptionController = TextEditingController(text: c.description);
  }

  @override
  void dispose() {
    amountController.dispose();
    counterpartyController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.controller.bootstrapData!;
    return Scaffold(
      appBar: AppBar(title: const Text('确认短信')),
      body: Form(
        key: formKey,
        child: ResponsiveListView(
          maxWidth: kFormMaxWidth,
          children: [
            ResponsiveFieldGrid(
              children: [
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: '金额 RMB'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => parseAmountCent(value ?? '') == null
                      ? '请输入正数金额，最多两位小数'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '方向'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('支出')),
                    DropdownMenuItem(value: 'income', child: Text('收入')),
                    DropdownMenuItem(value: 'transfer', child: Text('转账')),
                  ],
                  onChanged: submitting
                      ? null
                      : (value) {
                          setState(() {
                            direction = value!;
                            categoryL1Id =
                                bootstrap.categories
                                    .where(
                                      (c) =>
                                          c.isTopLevel && c.type == direction,
                                    )
                                    .firstOrNull
                                    ?.id ??
                                '';
                            categoryL2Id = null;
                          });
                        },
                ),
                CategoryPickerField(
                  key: ValueKey(
                    'sms-category-$direction-$categoryL1Id-$categoryL2Id',
                  ),
                  categories: bootstrap.categories,
                  direction: direction,
                  categoryL1Id: categoryL1Id,
                  categoryL2Id: categoryL2Id,
                  enabled: !submitting,
                  onChanged: (selection) {
                    setState(() {
                      categoryL1Id = selection.categoryL1Id;
                      categoryL2Id = selection.categoryL2Id;
                    });
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: memberId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '使用人'),
                  items: bootstrap.members
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: submitting
                      ? null
                      : (value) => setState(() => memberId = value!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '账户'),
                  items: bootstrap.accounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: submitting
                      ? null
                      : (value) => setState(() => accountId = value!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: counterpartyController,
              decoration: const InputDecoration(labelText: '交易对象'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: '详细描述'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: widget.candidate.rawBody,
              readOnly: true,
              decoration: const InputDecoration(labelText: '短信原文（本地）'),
              maxLines: 4,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: submitting ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('确认导入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    final token = widget.controller.token;
    if (token == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    final c = widget.candidate;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.controller.api.importSms(
        token,
        smsImportBody(
          c,
          amountCent: parseAmountCent(amountController.text)!,
          direction: direction,
          counterparty: counterpartyController.text.trim(),
          accountId: accountId,
          categoryL1Id: categoryL1Id,
          categoryL2Id: categoryL2Id,
          memberId: memberId,
          description: descriptionController.text.trim(),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (e is ApiException && e.code == 'duplicate_sms_import') {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }
}

Map<String, dynamic> smsImportBody(
  SmsCandidate candidate, {
  int? amountCent,
  String? direction,
  String? counterparty,
  String? accountId,
  String? categoryL1Id,
  String? categoryL2Id,
  String? memberId,
  String? description,
}) {
  return {
    'sms_hash': candidate.smsHash,
    'sender_masked': candidate.senderMasked,
    'sms_received_at_ms': candidate.smsReceivedAtMs,
    'sms_time': candidate.smsTime,
    'amount_cent': amountCent ?? candidate.amountCent,
    'direction': direction ?? candidate.direction,
    'counterparty': counterparty ?? candidate.counterparty,
    'account_hint': candidate.accountHint,
    'account_id': accountId ?? candidate.accountId,
    'category_l1_id': categoryL1Id ?? candidate.categoryL1Id,
    'category_l2_id': categoryL2Id ?? candidate.categoryL2Id,
    'member_id': memberId ?? candidate.memberId,
    'description': description ?? candidate.description,
  };
}

List<Map<String, dynamic>> categorySuggestionItemsForSms(
  Iterable<SmsCandidate> candidates,
) {
  return candidates
      .map(
        (candidate) => {
          'client_ref': candidate.smsHash,
          'direction': candidate.direction,
          'amount_cent': candidate.amountCent,
          'transaction_time': candidate.smsTime,
          'account_id': candidate.accountId,
          'counterparty': candidate.counterparty,
          'description': candidate.description,
        },
      )
      .toList();
}

const double kCategorySuggestionMinConfidence = 0.65;
const double kCategorySuggestionMinMargin = 0.15;

List<SmsCandidate> applyCategorySuggestions(
  List<SmsCandidate> candidates,
  List<CategorySuggestion> suggestions,
) {
  final byRef = {for (final item in suggestions) item.clientRef: item};
  return candidates.map((candidate) {
    final suggestion = byRef[candidate.smsHash];
    if (suggestion == null || !categorySuggestionIsUsable(suggestion)) {
      return candidate;
    }
    return candidate.copyWith(
      categoryL1Id: suggestion.categoryL1Id,
      categoryL2Id: suggestion.categoryL2Id,
    );
  }).toList();
}

bool categorySuggestionIsUsable(CategorySuggestion suggestion) {
  if (suggestion.method != 'nb' || suggestion.categoryL1Id.isEmpty) {
    return false;
  }
  if (suggestion.confidence < kCategorySuggestionMinConfidence) {
    return false;
  }
  final alternatives = [...suggestion.alternatives]
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  final second = alternatives.length > 1 ? alternatives[1].confidence : 0.0;
  return suggestion.confidence - second >= kCategorySuggestionMinMargin;
}

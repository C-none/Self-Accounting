import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/sms/sms_templates.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class SmsTemplatePage extends StatefulWidget {
  const SmsTemplatePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SmsTemplatePage> createState() => _SmsTemplatePageState();
}

class _SmsTemplatePageState extends State<SmsTemplatePage> {
  final SmsTemplateStore store = SmsTemplateStore();
  late final TextEditingController senderController;
  late final TextEditingController patternController;
  String? accountId;
  String? editingTemplateId;
  List<SmsTemplate> templates = [];
  bool loading = true;
  String? error;
  String? notice;

  @override
  void initState() {
    super.initState();
    senderController = TextEditingController();
    patternController = TextEditingController();
    accountId = widget.controller.bootstrapData?.accounts.firstOrNull?.id;
    _load();
  }

  @override
  void dispose() {
    senderController.dispose();
    patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.controller.bootstrapData;
    final accounts = bootstrap?.accounts ?? const <LedgerAccount>[];
    final account = _selectedAccount(accounts);
    final scopedTemplates = _scopedTemplates(account);
    return Scaffold(
      appBar: AppBar(title: const Text('短信模板')),
      body: ResponsiveListView(
        maxWidth: 820,
        children: [
          if (loading)
            const LinearProgressIndicator()
          else if (bootstrap == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('基础数据未加载')),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('模板范围', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ResponsiveFieldGrid(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: accountId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '账户'),
                          items: accounts
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.displayName),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            accountId = value;
                            editingTemplateId = null;
                            notice = null;
                            error = null;
                          }),
                        ),
                        TextFormField(
                          controller: senderController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\-\s]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: '发送号码',
                            hintText: '如 95588',
                          ),
                          onChanged: (_) => setState(() {
                            editingTemplateId = null;
                            notice = null;
                            error = null;
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('手动模板', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    const Text(
                      '规则：固定文字按短信原样输入，需要提取的片段写成 {字段}。扫描时只匹配已启用模板，并按大括号字段提取内容。',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '字段：{amount}=交易金额，{balance}=余额，{date_time}=短信中的时间占位，{merchant}=商户，{counterparty}=交易对方，{card_tail}=银行卡尾号，{bank}=银行名，{direction}=收入或支出方向。',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '示例：{bank}尾号{card_tail}卡于{date_time}向{merchant}支付RMB{amount}，对方{counterparty}，方向{direction}，余额{balance}。',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final word in smsTemplateSlotWords)
                          ActionChip(
                            label: Text('{$word}'),
                            onPressed: () => _insertSlot(word),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: patternController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '模板内容',
                        hintText: '把短信复制进来，再把金额、时间、商户等替换成 {amount}',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setState(() {
                        notice = null;
                        error = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: account == null ? null : _saveTemplate,
                          icon: Icon(
                            editingTemplateId == null
                                ? Icons.add
                                : Icons.save_outlined,
                          ),
                          label: Text(
                            editingTemplateId == null ? '新增模板' : '保存模板',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _clearEditor,
                          icon: const Icon(Icons.clear),
                          label: const Text('清空'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
            const SizedBox(height: 16),
            Text(
              '已设置 ${scopedTemplates.length} 个模板',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (scopedTemplates.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无模板')),
                ),
              )
            else
              for (var i = 0; i < scopedTemplates.length; i++)
                _SmsTemplateTile(
                  index: i + 1,
                  template: scopedTemplates[i],
                  onChanged: (enabled) =>
                      _setTemplateEnabled(scopedTemplates[i], enabled),
                  onEdit: () => _editTemplate(scopedTemplates[i]),
                  onDelete: () => _deleteTemplate(scopedTemplates[i]),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      templates = await store.load();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _saveTemplate() async {
    final account = _selectedAccount(
      widget.controller.bootstrapData?.accounts ?? const [],
    );
    final sender = senderController.text.trim();
    final pattern = patternController.text.trim();
    if (account == null) {
      setState(() => error = '请选择账户');
      return;
    }
    if (sender.isEmpty) {
      setState(() => error = '请输入发送号码');
      return;
    }
    final validationError = validateManualSmsTemplatePattern(pattern);
    if (validationError != null) {
      setState(() => error = validationError);
      return;
    }

    final draft = createManualSmsTemplate(
      account: account,
      sender: sender,
      pattern: pattern,
    );
    SmsTemplate? prior;
    for (final item in templates) {
      if (item.id == editingTemplateId || item.id == draft.id) {
        prior = item;
        break;
      }
    }
    final saved = createManualSmsTemplate(
      account: account,
      sender: sender,
      pattern: pattern,
      prior: prior,
      enabled: prior?.enabled ?? true,
    );
    setState(() {
      templates = [
        ...templates.where(
          (item) => item.id != editingTemplateId && item.id != saved.id,
        ),
        saved,
      ];
      editingTemplateId = null;
      patternController.clear();
      notice = '模板已保存';
      error = null;
    });
    await store.save(templates);
  }

  void _clearEditor() {
    setState(() {
      editingTemplateId = null;
      patternController.clear();
      notice = null;
      error = null;
    });
  }

  void _insertSlot(String word) {
    final token = '{$word}';
    final text = patternController.text;
    final selection = patternController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, token);
    patternController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {
      notice = null;
      error = null;
    });
  }

  Future<void> _setTemplateEnabled(SmsTemplate template, bool enabled) async {
    setState(() {
      templates = templates
          .map(
            (item) =>
                item.id == template.id ? item.copyWith(enabled: enabled) : item,
          )
          .toList();
      notice = enabled ? '模板已启用' : '模板已停用';
      error = null;
    });
    await store.save(templates);
  }

  void _editTemplate(SmsTemplate template) {
    setState(() {
      accountId = template.accountId;
      senderController.text = template.sender;
      patternController.text = template.pattern;
      editingTemplateId = template.id;
      notice = null;
      error = null;
    });
  }

  Future<void> _deleteTemplate(SmsTemplate template) async {
    setState(() {
      templates = templates.where((item) => item.id != template.id).toList();
      if (editingTemplateId == template.id) {
        editingTemplateId = null;
        patternController.clear();
      }
      notice = '模板已删除';
      error = null;
    });
    await store.save(templates);
  }

  LedgerAccount? _selectedAccount(List<LedgerAccount> accounts) {
    for (final account in accounts) {
      if (account.id == accountId) {
        return account;
      }
    }
    return accounts.firstOrNull;
  }

  List<SmsTemplate> _scopedTemplates(LedgerAccount? account) {
    if (account == null) {
      return const [];
    }
    final sender = normalizeSmsSender(senderController.text);
    final scoped = templates
        .where(
          (item) =>
              item.accountId == account.id &&
              (sender.isEmpty || item.sender == sender),
        )
        .toList();
    scoped.sort((a, b) {
      final enabled = (b.enabled ? 1 : 0).compareTo(a.enabled ? 1 : 0);
      if (enabled != 0) {
        return enabled;
      }
      final updated = b.updatedAt.compareTo(a.updatedAt);
      return updated != 0 ? updated : a.pattern.compareTo(b.pattern);
    });
    return scoped;
  }
}

class _SmsTemplateTile extends StatelessWidget {
  const _SmsTemplateTile({
    required this.index,
    required this.template,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final SmsTemplate template;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final slots = template.slots.isEmpty ? '无字段' : template.slots.join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Column(
          children: [
            SwitchListTile(
              value: template.enabled,
              onChanged: onChanged,
              title: Text('模板 $index · ${template.enabled ? '已启用' : '未启用'}'),
              subtitle: Text('发送号码 ${template.sender} · 字段 $slots'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      template.pattern,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑模板',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '删除模板',
                    onPressed: onDelete,
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

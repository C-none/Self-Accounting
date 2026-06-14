import 'package:flutter/material.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/pages/master_data_page.dart';
import 'package:ledger_client/src/pages/sms_template_page.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? pairingCode;
  String? message;
  bool messageIsError = false;
  bool loadingLogs = false;
  List<AuditLogEntry>? auditLogs;
  bool editingServiceAddress = false;
  final _serviceHostController = TextEditingController();
  final _servicePortController = TextEditingController();

  @override
  void dispose() {
    _serviceHostController.dispose();
    _servicePortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.controller.bootstrapData?.device;
    final isAdmin = device?.isAdmin ?? false;
    final showSmsTemplates =
        widget.controller.bootstrapData?.features['sms'] ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ResponsiveListView(
        maxWidth: 720,
        children: [
          if (device != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.devices),
                title: Text(device.name),
                subtitle: Text(
                  '${device.platform}${device.isAdmin ? ' · 管理员' : ''}',
                ),
                trailing: IconButton(
                  tooltip: '修改设备名',
                  onPressed: widget.controller.busy
                      ? null
                      : () => _editDeviceName(device.name),
                  icon: const Icon(Icons.edit),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('服务地址'),
                  subtitle: SelectableText(
                    widget.controller.api.displayBaseUrl,
                  ),
                  trailing: IconButton(
                    tooltip: editingServiceAddress ? '收起服务地址' : '修改服务地址',
                    onPressed: widget.controller.busy
                        ? null
                        : editingServiceAddress
                        ? _cancelServiceAddressEdit
                        : _beginServiceAddressEdit,
                    icon: Icon(
                      editingServiceAddress ? Icons.close : Icons.edit_outlined,
                    ),
                  ),
                ),
                if (editingServiceAddress)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _serviceHostController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: '服务 IP/主机',
                            hintText: '如 https://example.com 或 10.0.2.2',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _servicePortController,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            hintText: '如 8080',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveServiceAddress(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _cancelServiceAddressEdit,
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saveServiceAddress,
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MasterDataPage(controller: widget.controller),
              ),
            ),
            icon: const Icon(Icons.tune),
            label: const Text('基础资料管理'),
          ),
          if (showSmsTemplates) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SmsTemplatePage(controller: widget.controller),
                ),
              ),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('短信模板'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.controller.busy ? null : _startPairing,
            icon: const Icon(Icons.password),
            label: const Text('生成新设备配对码'),
          ),
          if (pairingCode != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              '新设备配对码：$pairingCode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                color: messageIsError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (isAdmin) ...[
            const Divider(height: 32),
            _AuditLogCard(
              logs: auditLogs,
              loading: loadingLogs,
              onRefresh: loadingLogs ? null : _loadAuditLogs,
            ),
          ],
          const Divider(height: 32),
          OutlinedButton.icon(
            onPressed: widget.controller.busy ? null : widget.controller.logout,
            icon: const Icon(Icons.logout),
            label: const Text('清除本机 token'),
          ),
        ],
      ),
    );
  }

  Future<void> _startPairing() async {
    try {
      final result = await widget.controller.startPairing();
      setState(() {
        pairingCode = result.pairingCode;
        message = result.isConsoleOnly ? '已请求服务端在命令行打印配对码。' : null;
        messageIsError = false;
      });
    } catch (e) {
      setState(() {
        message = e.toString();
        messageIsError = true;
      });
    }
  }

  Future<void> _editDeviceName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改设备名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '设备名'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = nextName?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }
    try {
      await widget.controller.updateCurrentDeviceName(trimmed);
      if (auditLogs != null) {
        await _loadAuditLogs();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        message = '设备名已保存';
        messageIsError = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        message = e.toString();
        messageIsError = true;
      });
    }
  }

  void _beginServiceAddressEdit() {
    _serviceHostController.text = widget.controller.api.displayHost;
    _servicePortController.text = widget.controller.api.displayPort;
    setState(() {
      editingServiceAddress = true;
      message = null;
      messageIsError = false;
    });
  }

  void _cancelServiceAddressEdit() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => editingServiceAddress = false);
  }

  Future<void> _saveServiceAddress() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final host = _serviceHostController.text;
    final port = _servicePortController.text;
    try {
      await widget.controller.updateServiceEndpoint(host: host, port: port);
      if (!mounted) {
        return;
      }
      setState(() {
        editingServiceAddress = false;
        message = '服务地址已保存，后续请求将使用新地址';
        messageIsError = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        message = e.toString();
        messageIsError = true;
      });
    }
  }

  Future<void> _loadAuditLogs() async {
    final token = widget.controller.token;
    if (token == null) {
      return;
    }
    setState(() {
      loadingLogs = true;
      message = null;
      messageIsError = false;
    });
    try {
      final logs = await widget.controller.api.listAuditLogs(token, limit: 20);
      if (!mounted) {
        return;
      }
      setState(() => auditLogs = logs);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        message = e.toString();
        messageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => loadingLogs = false);
      }
    }
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({
    required this.logs,
    required this.loading,
    required this.onRefresh,
  });

  final List<AuditLogEntry>? logs;
  final bool loading;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final currentLogs = logs;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('最近日志'),
            trailing: IconButton(
              tooltip: '查询日志',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: LinearProgressIndicator(),
            )
          else if (currentLogs == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.search),
                  label: const Text('查询日志'),
                ),
              ),
            )
          else if (currentLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('暂无日志'),
              ),
            )
          else
            ...currentLogs.map((log) => _AuditLogTile(log: log)),
        ],
      ),
    );
  }

  static String _entityLabel(String value) {
    return switch (value) {
      'transaction' => '交易',
      'category' => '分类',
      'member' => '成员',
      'account' => '账户',
      'attachment' => '附件',
      'backup' => '备份',
      'device' => '设备',
      _ => value,
    };
  }

  static String _actionLabel(String value) {
    return switch (value) {
      'create' => '新增',
      'create_sms' => '短信导入',
      'update' => '修改',
      'update_name' => '改名',
      'delete' => '删除',
      _ => value,
    };
  }

  static String _deviceLabel(AuditLogEntry log) {
    if (log.deviceName.isNotEmpty) {
      return log.deviceName;
    }
    return _shortId(log.deviceId);
  }

  static String _shortId(String value) {
    if (value.length <= 14) {
      return value;
    }
    return '${value.substring(0, 10)}...';
  }
}

class _AuditLogTile extends StatelessWidget {
  const _AuditLogTile({required this.log});

  final AuditLogEntry log;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: PageStorageKey<String>('audit-log-${log.id}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
      dense: true,
      title: Text(
        '${formatDateTime(log.createdAt)} · '
        '${_AuditLogCard._entityLabel(log.entityType)} · '
        '${_AuditLogCard._actionLabel(log.action)}',
      ),
      subtitle: Text(
        '${_AuditLogCard._deviceLabel(log)} · '
        '${_AuditLogCard._shortId(log.entityId)}',
      ),
      children: [
        _AuditDetailRow(label: '时间', value: formatDateTime(log.createdAt)),
        _AuditDetailRow(label: '实体', value: log.entityType),
        _AuditDetailRow(label: '动作', value: log.action),
        _AuditDetailRow(label: '实体ID', value: log.entityId),
        _AuditDetailRow(label: '设备名', value: log.deviceName),
        _AuditDetailRow(label: '设备ID', value: log.deviceId),
        _AuditDetailRow(label: '日志ID', value: log.id),
      ],
    );
  }
}

class _AuditDetailRow extends StatelessWidget {
  const _AuditDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = value.isEmpty ? '-' : value;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(label, style: textTheme.bodySmall)),
          Expanded(child: Text(displayValue, style: textTheme.bodySmall)),
        ],
      ),
    );
  }
}

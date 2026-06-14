import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final TextEditingController codeController = TextEditingController();
  final TextEditingController hostController = TextEditingController();
  final TextEditingController portController = TextEditingController();
  final TextEditingController nameController = TextEditingController(
    text: kIsWeb ? 'Web 浏览器' : 'Android 手机',
  );
  String? message;

  @override
  void initState() {
    super.initState();
    hostController.text = widget.controller.api.displayHost;
    portController.text = widget.controller.api.displayPort;
  }

  @override
  void dispose() {
    codeController.dispose();
    hostController.dispose();
    portController.dispose();
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备配对')),
      body: SafeArea(
        child: ResponsiveListView(
          maxWidth: kNarrowFormMaxWidth,
          topPadding: isDesktopWidth(context) ? 72 : 20,
          children: [
            Text('小小记账', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              '输入一次性配对码后保存设备 token。未配对设备不能在页面直接获得配对码，只能请求服务端在命令行打印配对码。',
            ),
            const SizedBox(height: 20),
            ResponsiveFieldGrid(
              children: [
                TextField(
                  controller: hostController,
                  decoration: const InputDecoration(
                    labelText: '服务 IP/主机',
                    hintText: '如 10.0.2.2 或 192.168.1.10',
                  ),
                ),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '如 8080',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '当前服务地址：${widget.controller.api.displayBaseUrl}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '设备名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: '配对码'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.controller.busy ? null : _confirm,
              icon: const Icon(Icons.link),
              label: const Text('完成配对'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.controller.busy ? null : _startPairing,
              icon: const Icon(Icons.password),
              label: const Text('请求生成配对码'),
            ),
            if (message != null || widget.controller.lastError != null) ...[
              const SizedBox(height: 16),
              Text(
                message ?? widget.controller.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startPairing() async {
    try {
      await _saveServiceEndpoint();
      final result = await widget.controller.startPairing();
      setState(() {
        if (result.isConsoleOnly) {
          message = '已请求服务端在命令行打印配对码；如果已有未过期配对码，服务端会重新打印。';
        } else {
          codeController.text = result.pairingCode!;
          message = '已生成配对码。';
        }
      });
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _confirm() async {
    final code = codeController.text.trim();
    final name = nameController.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => message = '设备名称和配对码不能为空');
      return;
    }
    try {
      await _saveServiceEndpoint();
      await widget.controller.confirmPairing(
        code: code,
        deviceName: name,
        platform: kIsWeb ? 'web' : 'android',
      );
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _saveServiceEndpoint() async {
    if (hostController.text.trim().isEmpty &&
        portController.text.trim().isEmpty) {
      return;
    }
    await widget.controller.updateServiceEndpoint(
      host: hostController.text,
      port: portController.text,
    );
  }
}

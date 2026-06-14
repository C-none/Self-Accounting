import 'package:flutter/material.dart';

class SmsPlaceholderPage extends StatelessWidget {
  const SmsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('短信导入')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('短信扫描将在 Phase 3 实现；当前不会读取或上传短信原文。'),
        ),
      ),
    );
  }
}

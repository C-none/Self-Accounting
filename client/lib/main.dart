import 'package:flutter/material.dart';
import 'package:ledger_client/src/api_client.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/pages/home_shell.dart';
import 'package:ledger_client/src/pages/pairing_page.dart';

void main() {
  runApp(const LedgerApp());
}

class LedgerApp extends StatefulWidget {
  const LedgerApp({super.key});

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(ApiClient());
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小小记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xff1f7a5a),
              brightness: Brightness.light,
            ).copyWith(
              surface: Colors.white,
              surfaceContainer: const Color(0xfff6f8f7),
              surfaceContainerHighest: const Color(0xffe7eeeb),
            ),
        scaffoldBackgroundColor: const Color(0xfff2f5f4),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xffd7dfdc)),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _Root(controller: controller),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!controller.isPaired) {
      return PairingPage(controller: controller);
    }
    return HomeShell(controller: controller);
  }
}

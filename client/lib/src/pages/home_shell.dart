import 'package:flutter/material.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/pages/settings_page.dart';
import 'package:ledger_client/src/pages/sms_import_page.dart';
import 'package:ledger_client/src/pages/stats_page.dart';
import 'package:ledger_client/src/pages/transactions_page.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final showSms = widget.controller.bootstrapData?.features['sms'] ?? false;
    final pages = [
      TransactionsPage(controller: widget.controller),
      StatsPage(controller: widget.controller),
      if (showSms) SmsImportPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
    ];
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.receipt_long), label: '交易'),
      const NavigationDestination(icon: Icon(Icons.query_stats), label: '统计'),
      if (showSms)
        const NavigationDestination(icon: Icon(Icons.sms), label: '短信'),
      const NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
    ];
    final railDestinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.receipt_long),
        label: Text('交易'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.query_stats),
        label: Text('统计'),
      ),
      if (showSms)
        const NavigationRailDestination(
          icon: Icon(Icons.sms),
          label: Text('短信'),
        ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings),
        label: Text('设置'),
      ),
    ];
    if (selectedIndex >= pages.length) {
      selectedIndex = 0;
    }
    if (isDesktopWidth(context)) {
      final extended =
          MediaQuery.sizeOf(context).width >= kWideDesktopBreakpoint;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => selectedIndex = index),
              extended: extended,
              minExtendedWidth: 184,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: const SizedBox(height: 12),
              destinations: railDestinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[selectedIndex]),
          ],
        ),
      );
    }
    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: destinations,
      ),
    );
  }
}

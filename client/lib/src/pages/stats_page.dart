import 'package:flutter/material.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/widgets/charts.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool loading = true;
  String? error;
  String direction = 'expense';
  String compareBy = 'category_l1';
  String bucket = 'day';
  String? memberId;
  String? categoryL1Id;
  String? categoryL2Id;
  String? bankName;
  DateTime? fromDate;
  DateTime? toDate;
  List<CategoryStat> categoryStats = [];
  List<TimelineSeries> timelineSeries = [];

  @override
  void initState() {
    super.initState();
    final dateRange = defaultStatsDateRange();
    fromDate = dateRange.fromDate;
    toDate = dateRange.toDate;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.controller.bootstrapData;
    final allCategories = bootstrap?.categories ?? const <Category>[];
    final categories = allCategories
        .where((c) => c.isTopLevel && c.type == direction)
        .toList();
    final subCategories = allCategories
        .where(
          (c) =>
              !c.isTopLevel &&
              c.type == direction &&
              (categoryL1Id == null || c.parentId == categoryL1Id),
        )
        .toList();
    final members = bootstrap?.members ?? const <Member>[];
    final bankNames = _bankNames(
      bootstrap?.accounts ?? const <LedgerAccount>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ResponsiveListView(
          children: [
            _StatsFilterCard(
              direction: direction,
              compareBy: compareBy,
              bucket: bucket,
              memberId: memberId,
              categoryL1Id: categoryL1Id,
              categoryL2Id: categoryL2Id,
              bankName: bankName,
              fromDate: fromDate,
              toDate: toDate,
              members: members,
              categories: categories,
              subCategories: subCategories,
              bankNames: bankNames,
              onDirectionChanged: (value) {
                if (value == null) {
                  return;
                }
                _changeFilters(() {
                  direction = value;
                  categoryL1Id = null;
                  categoryL2Id = null;
                });
              },
              onCompareByChanged: (value) {
                if (value == null) {
                  return;
                }
                _changeFilters(() {
                  compareBy = value;
                  _clearConflictingFilters();
                });
              },
              onBucketChanged: (value) {
                if (value == null) {
                  return;
                }
                _changeFilters(() => bucket = value);
              },
              onMemberChanged: (value) =>
                  _changeFilters(() => memberId = value),
              onCategoryChanged: (value) => _changeFilters(() {
                categoryL1Id = value;
                categoryL2Id = null;
              }),
              onSubCategoryChanged: (value) =>
                  _changeFilters(() => categoryL2Id = value),
              onBankChanged: (value) => _changeFilters(() => bankName = value),
              onFromChanged: (value) => _changeFilters(() => fromDate = value),
              onToChanged: (value) => _changeFilters(() => toDate = value),
              onClear: () {
                _changeFilters(() {
                  final dateRange = defaultStatsDateRange();
                  direction = 'expense';
                  compareBy = 'category_l1';
                  bucket = 'day';
                  memberId = null;
                  categoryL1Id = null;
                  categoryL2Id = null;
                  bankName = null;
                  fromDate = dateRange.fromDate;
                  toDate = dateRange.toDate;
                });
              },
            ),
            const SizedBox(height: 16),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else ...[
              _StatsSections(
                bucket: bucket,
                compareBy: compareBy,
                categoryStats: categoryStats,
                timelineSeries: timelineSeries,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _changeFilters(VoidCallback change) {
    setState(change);
    _load();
  }

  void _clearConflictingFilters() {
    switch (compareBy) {
      case 'category_l1':
        categoryL1Id = null;
        categoryL2Id = null;
        break;
      case 'category_l2':
        categoryL2Id = null;
        break;
      case 'member':
        memberId = null;
        break;
      case 'bank':
        bankName = null;
        break;
    }
  }

  Future<void> _load() async {
    final token = widget.controller.token;
    if (token == null) {
      return;
    }
    if (fromDate != null && toDate != null && fromDate!.isAfter(toDate!)) {
      setState(() {
        loading = false;
        error = '起始日期不能晚于结束日期';
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final from = _startOfDaySeconds(fromDate);
    final to = _endOfDaySeconds(toDate);
    final filterCategoryL1Id = compareBy == 'category_l1' ? null : categoryL1Id;
    final filterCategoryL2Id =
        compareBy == 'category_l1' || compareBy == 'category_l2'
        ? null
        : categoryL2Id;
    final filterMemberId = compareBy == 'member' ? null : memberId;
    final filterBankName = compareBy == 'bank' ? null : bankName;
    try {
      final nextCategory = await widget.controller.api.categoryStats(
        token,
        direction: direction,
        compareBy: compareBy,
        memberId: filterMemberId,
        categoryL1Id: filterCategoryL1Id,
        categoryL2Id: filterCategoryL2Id,
        bankName: filterBankName,
        from: from,
        to: to,
      );
      final nextTimeline = await widget.controller.api.timelineStats(
        token,
        direction: direction,
        compareBy: compareBy,
        bucket: bucket,
        memberId: filterMemberId,
        categoryL1Id: filterCategoryL1Id,
        categoryL2Id: filterCategoryL2Id,
        bankName: filterBankName,
        from: from,
        to: to,
      );
      if (mounted) {
        setState(() {
          categoryStats = nextCategory;
          timelineSeries = nextTimeline.series;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }
}

class _StatsFilterCard extends StatelessWidget {
  const _StatsFilterCard({
    required this.direction,
    required this.compareBy,
    required this.bucket,
    required this.memberId,
    required this.categoryL1Id,
    required this.categoryL2Id,
    required this.bankName,
    required this.fromDate,
    required this.toDate,
    required this.members,
    required this.categories,
    required this.subCategories,
    required this.bankNames,
    required this.onDirectionChanged,
    required this.onCompareByChanged,
    required this.onBucketChanged,
    required this.onMemberChanged,
    required this.onCategoryChanged,
    required this.onSubCategoryChanged,
    required this.onBankChanged,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClear,
  });

  final String direction;
  final String compareBy;
  final String bucket;
  final String? memberId;
  final String? categoryL1Id;
  final String? categoryL2Id;
  final String? bankName;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<Member> members;
  final List<Category> categories;
  final List<Category> subCategories;
  final List<String> bankNames;
  final ValueChanged<String?> onDirectionChanged;
  final ValueChanged<String?> onCompareByChanged;
  final ValueChanged<String?> onBucketChanged;
  final ValueChanged<String?> onMemberChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onSubCategoryChanged;
  final ValueChanged<String?> onBankChanged;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final defaultDateRange = defaultStatsDateRange();
    final canFilterCategoryL1 = compareBy != 'category_l1';
    final canFilterCategoryL2 =
        compareBy != 'category_l1' && compareBy != 'category_l2';
    final canFilterMember = compareBy != 'member';
    final canFilterBank = compareBy != 'bank';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统计过滤', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: _DirectionDropdown(
                        value: direction,
                        onChanged: onDirectionChanged,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _CompareByDropdown(
                        value: compareBy,
                        onChanged: onCompareByChanged,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _BucketDropdown(
                        value: bucket,
                        onChanged: onBucketChanged,
                      ),
                    ),
                    if (canFilterCategoryL1)
                      SizedBox(
                        width: fieldWidth,
                        child: _CategoryDropdown(
                          value: categoryL1Id,
                          categories: categories,
                          onChanged: onCategoryChanged,
                        ),
                      ),
                    if (canFilterCategoryL2)
                      SizedBox(
                        width: fieldWidth,
                        child: _SubCategoryDropdown(
                          value: categoryL2Id,
                          categories: subCategories,
                          onChanged: onSubCategoryChanged,
                        ),
                      ),
                    if (canFilterMember)
                      SizedBox(
                        width: fieldWidth,
                        child: _MemberDropdown(
                          value: memberId,
                          members: members,
                          onChanged: onMemberChanged,
                        ),
                      ),
                    if (canFilterBank)
                      SizedBox(
                        width: fieldWidth,
                        child: _BankDropdown(
                          value: bankName,
                          bankNames: bankNames,
                          onChanged: onBankChanged,
                        ),
                      ),
                    SizedBox(
                      width: fieldWidth,
                      child: _StatsDateField(
                        label: '起始日期',
                        value: fromDate,
                        defaultDate: defaultDateRange.fromDate,
                        onChanged: onFromChanged,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _StatsDateField(
                        label: '结束日期',
                        value: toDate,
                        defaultDate: defaultDateRange.toDate,
                        onChanged: onToChanged,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: onClear,
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('清除过滤'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class StatsDateRange {
  const StatsDateRange({required this.fromDate, required this.toDate});

  final DateTime fromDate;
  final DateTime toDate;
}

StatsDateRange defaultStatsDateRange([DateTime? now]) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  return StatsDateRange(fromDate: _addMonthsClamped(today, -1), toDate: today);
}

DateTime _addMonthsClamped(DateTime date, int months) {
  final targetMonthStart = DateTime(date.year, date.month + months);
  final lastTargetDay = DateTime(
    targetMonthStart.year,
    targetMonthStart.month + 1,
    0,
  ).day;
  final targetDay = date.day > lastTargetDay ? lastTargetDay : date.day;
  return DateTime(targetMonthStart.year, targetMonthStart.month, targetDay);
}

class _StatsSections extends StatelessWidget {
  const _StatsSections({
    required this.bucket,
    required this.compareBy,
    required this.categoryStats,
    required this.timelineSeries,
  });

  final String bucket;
  final String compareBy;
  final List<CategoryStat> categoryStats;
  final List<TimelineSeries> timelineSeries;

  @override
  Widget build(BuildContext context) {
    final compareLabel = _compareByLabel(compareBy);
    final hasTimelineData = timelineSeries.any(
      (item) => item.points.isNotEmpty,
    );
    final categorySection = _Section(
      title: '占比统计（$compareLabel）',
      child: categoryStats.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                SizedBox(
                  height: 220,
                  child: CategoryPieChart(items: categoryStats),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < categoryStats.length; i++)
                  _StatRow(item: categoryStats[i], colorIndex: i),
              ],
            ),
    );
    final timelineSection = _Section(
      title: '时间趋势（${_bucketLabel(bucket)} · $compareLabel）',
      child: !hasTimelineData
          ? const _EmptyChart()
          : Column(
              children: [
                SizedBox(
                  height: 240,
                  child: TimelineLineChart(series: timelineSeries),
                ),
                const SizedBox(height: 12),
                _SeriesLegend(series: timelineSeries),
              ],
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: categorySection),
              const SizedBox(width: 16),
              Expanded(child: timelineSection),
            ],
          );
        }
        return Column(
          children: [
            categorySection,
            const SizedBox(height: 16),
            timelineSection,
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.item, required this.colorIndex});

  final CategoryStat item;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final color = statColorForIndex(Theme.of(context).colorScheme, colorIndex);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _LegendSwatch(color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('${item.percent.toStringAsFixed(1)}%'),
          const SizedBox(width: 16),
          Text(formatMoney(item.amountCent)),
        ],
      ),
    );
  }
}

class _SeriesLegend extends StatelessWidget {
  const _SeriesLegend({required this.series});

  final List<TimelineSeries> series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (var i = 0; i < series.length; i++)
          if (series[i].points.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendSwatch(color: statColorForIndex(scheme, i)),
                const SizedBox(width: 6),
                Text(series[i].groupName),
              ],
            ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 180, child: Center(child: Text('暂无统计数据')));
  }
}

class _DirectionDropdown extends StatelessWidget {
  const _DirectionDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('stats-direction-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '统计方向'),
      items: const [
        DropdownMenuItem(value: 'expense', child: Text('支出')),
        DropdownMenuItem(value: 'income', child: Text('收入')),
        DropdownMenuItem(value: 'transfer', child: Text('转账')),
      ],
      onChanged: onChanged,
    );
  }
}

class _CompareByDropdown extends StatelessWidget {
  const _CompareByDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('stats-compare-by-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '比较属性'),
      items: const [
        DropdownMenuItem(value: 'category_l1', child: Text('一级分类')),
        DropdownMenuItem(value: 'category_l2', child: Text('二级分类')),
        DropdownMenuItem(value: 'member', child: Text('使用人')),
        DropdownMenuItem(value: 'bank', child: Text('银行')),
      ],
      onChanged: onChanged,
    );
  }
}

class _BucketDropdown extends StatelessWidget {
  const _BucketDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('stats-bucket-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '折线粒度'),
      items: const [
        DropdownMenuItem(value: 'day', child: Text('按日')),
        DropdownMenuItem(value: 'week', child: Text('按周')),
        DropdownMenuItem(value: 'month', child: Text('按月')),
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
    final safeValue = categories.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('stats-category-$safeValue-${categories.length}'),
      initialValue: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '一级分类'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部一级分类')),
        ...categories.map(
          (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _SubCategoryDropdown extends StatelessWidget {
  const _SubCategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String? value;
  final List<Category> categories;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = categories.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('stats-sub-category-$safeValue-${categories.length}'),
      initialValue: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '二级分类'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部二级分类')),
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
    final safeValue = members.any((m) => m.id == value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('stats-member-$safeValue-${members.length}'),
      initialValue: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '使用人'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部使用人')),
        ...members.map(
          (m) => DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _BankDropdown extends StatelessWidget {
  const _BankDropdown({
    required this.value,
    required this.bankNames,
    required this.onChanged,
  });

  final String? value;
  final List<String> bankNames;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = bankNames.contains(value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('stats-bank-$safeValue-${bankNames.length}'),
      initialValue: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '银行'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部银行')),
        ...bankNames.map(
          (name) => DropdownMenuItem<String?>(value: name, child: Text(name)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _StatsDateField extends StatelessWidget {
  const _StatsDateField({
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
      key: ValueKey('stats-$label-${value?.millisecondsSinceEpoch ?? 0}'),
      initialValue: value == null ? '' : formatCompactDate(value!),
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: formatCompactDate(defaultDate),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              IconButton(
                tooltip: '清除$label',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              tooltip: '选择$label',
              onPressed: () => _pickDate(context),
              icon: const Icon(Icons.arrow_drop_down),
            ),
          ],
        ),
      ),
      onTap: () => _pickDate(context),
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

List<String> _bankNames(List<LedgerAccount> accounts) {
  final names = <String>[];
  final seen = <String>{};
  for (final account in accounts) {
    final name = account.name.trim();
    if (name.isEmpty) {
      continue;
    }
    final key = normalizeBankName(name);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    names.add(name);
  }
  return names;
}

int? _startOfDaySeconds(DateTime? value) {
  if (value == null) {
    return null;
  }
  return DateTime(value.year, value.month, value.day).millisecondsSinceEpoch ~/
      1000;
}

int? _endOfDaySeconds(DateTime? value) {
  if (value == null) {
    return null;
  }
  return DateTime(
            value.year,
            value.month,
            value.day + 1,
          ).millisecondsSinceEpoch ~/
          1000 -
      1;
}

String _bucketLabel(String bucket) {
  return switch (bucket) {
    'week' => '按周',
    'month' => '按月',
    _ => '按日',
  };
}

String _compareByLabel(String compareBy) {
  return switch (compareBy) {
    'category_l2' => '二级分类',
    'member' => '使用人',
    'bank' => '银行',
    _ => '一级分类',
  };
}

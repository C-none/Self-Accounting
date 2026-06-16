import 'package:flutter/material.dart';
import 'package:ledger_client/src/models.dart';

class CategorySelection {
  const CategorySelection({required this.categoryL1Id, this.categoryL2Id});

  final String categoryL1Id;
  final String? categoryL2Id;
}

class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.categories,
    required this.direction,
    required this.categoryL1Id,
    required this.categoryL2Id,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Category> categories;
  final String direction;
  final String? categoryL1Id;
  final String? categoryL2Id;
  final bool enabled;
  final ValueChanged<CategorySelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final topCategories = categories
        .where((c) => c.isTopLevel && c.type == direction)
        .toList();
    final canOpen = enabled && topCategories.isNotEmpty;
    final display = categoryL1Id == null || categoryL1Id!.isEmpty
        ? ''
        : categoryDisplayName(categories, categoryL1Id!, categoryL2Id ?? '');
    return FormField<CategorySelection>(
      validator: (_) =>
          categoryL1Id == null || categoryL1Id!.isEmpty ? '请选择分类' : null,
      builder: (state) {
        return InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: canOpen
              ? () async {
                  final picked = await showCategoryPicker(
                    context: context,
                    categories: categories,
                    direction: direction,
                    categoryL1Id: categoryL1Id,
                    categoryL2Id: categoryL2Id,
                  );
                  if (picked == null || !context.mounted) {
                    return;
                  }
                  state.didChange(picked);
                  onChanged(picked);
                }
              : null,
          child: InputDecorator(
            isEmpty: display.isEmpty,
            decoration: InputDecoration(
              labelText: '分类',
              enabled: canOpen,
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              display.isEmpty ? '请选择分类' : display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: display.isEmpty
                  ? TextStyle(color: Theme.of(context).hintColor)
                  : null,
            ),
          ),
        );
      },
    );
  }
}

Future<CategorySelection?> showCategoryPicker({
  required BuildContext context,
  required List<Category> categories,
  required String direction,
  required String? categoryL1Id,
  required String? categoryL2Id,
}) {
  return showModalBottomSheet<CategorySelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _CategoryPickerSheet(
      categories: categories,
      direction: direction,
      categoryL1Id: categoryL1Id,
      categoryL2Id: categoryL2Id,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.direction,
    required this.categoryL1Id,
    required this.categoryL2Id,
  });

  final List<Category> categories;
  final String direction;
  final String? categoryL1Id;
  final String? categoryL2Id;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  static const _rowHeight = 48.0;
  static const _dividerHeight = 10.0;

  final ScrollController _leftController = ScrollController();
  final ScrollController _rightController = ScrollController();
  var _groupOffsets = <double>[];
  late String _selectedTopId;
  bool _programmaticScroll = false;

  List<Category> get _topCategories => widget.categories
      .where((c) => c.isTopLevel && c.type == widget.direction)
      .toList();

  @override
  void initState() {
    super.initState();
    final topCategories = _topCategories;
    _selectedTopId =
        widget.categoryL1Id ??
        (topCategories.isEmpty ? '' : topCategories.first.id);
    _rightController.addListener(_syncLeftSelection);
  }

  @override
  void dispose() {
    _rightController.removeListener(_syncLeftSelection);
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topCategories = _topCategories;
    _groupOffsets = _buildGroupOffsets(topCategories);
    final height = (MediaQuery.sizeOf(context).height * 0.56)
        .clamp(320.0, 520.0)
        .toDouble();
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text('分类', style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Row(
                children: [
                  SizedBox(
                    width: 116,
                    child: ListView.builder(
                      controller: _leftController,
                      itemCount: topCategories.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (context, index) {
                        final category = topCategories[index];
                        final selected = category.id == _selectedTopId;
                        return Material(
                          color: selected
                              ? theme.colorScheme.secondaryContainer
                              : theme.colorScheme.surface,
                          child: InkWell(
                            onTap: () => _jumpToGroup(index, category.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: selected
                                      ? TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSecondaryContainer,
                                          fontWeight: FontWeight.w700,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      controller: _rightController,
                      children: [
                        for (final top in topCategories)
                          ..._rightGroup(context, top),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rightGroup(BuildContext context, Category top) {
    final children = widget.categories
        .where((c) => c.parentId == top.id && c.type == widget.direction)
        .toList();
    return [
      _CategoryOptionRow(
        label: '仅${top.name}',
        selected:
            widget.categoryL1Id == top.id &&
            (widget.categoryL2Id == null || widget.categoryL2Id!.isEmpty),
        onTap: () => Navigator.of(
          context,
        ).pop(CategorySelection(categoryL1Id: top.id, categoryL2Id: null)),
      ),
      for (final child in children)
        _CategoryOptionRow(
          label: child.name,
          selected: widget.categoryL2Id == child.id,
          onTap: () => Navigator.of(context).pop(
            CategorySelection(categoryL1Id: top.id, categoryL2Id: child.id),
          ),
        ),
      Divider(
        height: _dividerHeight,
        thickness: 1.4,
        indent: 16,
        endIndent: 16,
      ),
    ];
  }

  List<double> _buildGroupOffsets(List<Category> topCategories) {
    var offset = 0.0;
    final offsets = <double>[];
    for (final top in topCategories) {
      offsets.add(offset);
      final childCount = widget.categories
          .where((c) => c.parentId == top.id && c.type == widget.direction)
          .length;
      offset += (childCount + 1) * _rowHeight + _dividerHeight;
    }
    return offsets;
  }

  void _jumpToGroup(int index, String topId) {
    setState(() => _selectedTopId = topId);
    if (index >= _groupOffsets.length) {
      return;
    }
    _programmaticScroll = true;
    _rightController
        .animateTo(
          _groupOffsets[index],
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _programmaticScroll = false);
  }

  void _syncLeftSelection() {
    if (_programmaticScroll || _groupOffsets.isEmpty) {
      return;
    }
    final topCategories = _topCategories;
    final offset = _rightController.offset + 4;
    var nextIndex = 0;
    for (var i = 0; i < _groupOffsets.length; i++) {
      if (_groupOffsets[i] <= offset) {
        nextIndex = i;
      } else {
        break;
      }
    }
    if (nextIndex >= topCategories.length) {
      return;
    }
    final nextId = topCategories[nextIndex].id;
    if (nextId != _selectedTopId) {
      setState(() => _selectedTopId = nextId);
    }
  }
}

class _CategoryOptionRow extends StatelessWidget {
  const _CategoryOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _CategoryPickerSheetState._rowHeight,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? Icon(Icons.check, color: theme.colorScheme.primary)
            : null,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

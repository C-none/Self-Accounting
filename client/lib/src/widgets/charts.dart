import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ledger_client/src/models.dart';

Color statColorForIndex(ColorScheme scheme, int index) {
  return _statPalette[index % _statPalette.length];
}

int statColorIndexForGroup(
  Map<String, int> colorIndexes,
  String groupId,
  int fallbackIndex,
) {
  return colorIndexes[groupId] ?? fallbackIndex;
}

const _statPalette = [
  Color(0xFF2563EB),
  Color(0xFFDC2626),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF4D7C0F),
  Color(0xFFEA580C),
  Color(0xFF475569),
  Color(0xFF0F766E),
  Color(0xFF9333EA),
];

class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({
    super.key,
    required this.items,
    this.colorIndexes = const {},
  });

  final List<CategoryStat> items;
  final Map<String, int> colorIndexes;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(items, colorIndexes, Theme.of(context).colorScheme),
      child: const SizedBox.expand(),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.items, this.colorIndexes, this.scheme);

  final List<CategoryStat> items;
  final Map<String, int> colorIndexes;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final total = items.fold<int>(0, (sum, item) => sum + item.amountCent);
    if (total <= 0) {
      return;
    }
    final radius = math.min(size.width, size.height) * 0.36;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final separatorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = scheme.surface.withValues(alpha: 0.92);
    for (var i = 0; i < items.length; i++) {
      final sweep = (items[i].amountCent / total) * math.pi * 2;
      final colorIndex = statColorIndexForGroup(
        colorIndexes,
        items[i].groupId,
        i,
      );
      paint.color = statColorForIndex(scheme, colorIndex);
      canvas.drawArc(rect, start, sweep, true, paint);
      canvas.drawArc(rect, start, sweep, true, separatorPaint);
      start += sweep;
    }
    final inner = Paint()..color = scheme.surface;
    canvas.drawCircle(center, radius * 0.52, inner);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.items != items || oldDelegate.colorIndexes != colorIndexes;
}

class TimelineLineChart extends StatelessWidget {
  const TimelineLineChart({
    super.key,
    required this.series,
    this.colorIndexes = const {},
    this.selectedGroupId,
  });

  final List<TimelineSeries> series;
  final Map<String, int> colorIndexes;
  final String? selectedGroupId;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        series,
        colorIndexes,
        selectedGroupId,
        Theme.of(context).colorScheme,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(
    this.series,
    this.colorIndexes,
    this.selectedGroupId,
    this.scheme,
  );

  final List<TimelineSeries> series;
  final Map<String, int> colorIndexes;
  final String? selectedGroupId;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final dates = <String>{};
    for (final item in series) {
      for (final point in item.points) {
        dates.add(point.date);
      }
    }
    if (dates.isEmpty) {
      return;
    }
    final sortedDates = dates.toList()..sort();
    const left = 48.0;
    const top = 34.0;
    const right = 18.0;
    const bottom = 40.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final axisPaint = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.bottomLeft, chart.topLeft, axisPaint);

    var maxAmount = 0;
    for (final item in series) {
      for (final point in item.points) {
        if (point.amountCent > maxAmount) {
          maxAmount = point.amountCent;
        }
      }
    }
    if (maxAmount <= 0) {
      return;
    }
    for (var seriesIndex = 0; seriesIndex < series.length; seriesIndex++) {
      final item = series[seriesIndex];
      if (item.points.isEmpty) {
        continue;
      }
      final byDate = {for (final point in item.points) point.date: point};
      final color = statColorForIndex(
        scheme,
        statColorIndexForGroup(colorIndexes, item.groupId, seriesIndex),
      );
      final path = Path();
      for (var i = 0; i < sortedDates.length; i++) {
        final amount = byDate[sortedDates[i]]?.amountCent ?? 0;
        final x = sortedDates.length == 1
            ? chart.left + chart.width / 2
            : chart.left + chart.width * i / (sortedDates.length - 1);
        final y = chart.bottom - chart.height * amount / maxAmount;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);

      final dotPaint = Paint()..color = color;
      for (var i = 0; i < sortedDates.length; i++) {
        final amount = byDate[sortedDates[i]]?.amountCent ?? 0;
        final x = sortedDates.length == 1
            ? chart.left + chart.width / 2
            : chart.left + chart.width * i / (sortedDates.length - 1);
        final y = chart.bottom - chart.height * amount / maxAmount;
        final offset = Offset(x, y);
        canvas.drawCircle(offset, 3.2, dotPaint);
        if (selectedGroupId == item.groupId) {
          _drawPointValue(
            canvas,
            size,
            offset,
            formatMoney(amount),
            color,
            seriesIndex,
          );
        }
      }
    }

    _drawLabel(
      canvas,
      Offset(chart.left, chart.bottom + 18),
      sortedDates.first,
      scheme.onSurface,
    );
    if (sortedDates.length > 1) {
      _drawLabel(
        canvas,
        Offset(chart.right - 76, chart.bottom + 18),
        sortedDates.last,
        scheme.onSurface,
      );
    }
  }

  void _drawLabel(Canvas canvas, Offset offset, String text, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 84);
    painter.paint(canvas, offset);
  }

  void _drawPointValue(
    Canvas canvas,
    Size size,
    Offset point,
    String text,
    Color color,
    int seriesIndex,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 72);
    final row = seriesIndex % 4;
    final above = seriesIndex.isEven;
    final dx = ((row % 2) == 0 ? -0.5 : -0.1) * painter.width;
    final dy = above ? -painter.height - 8 - row * 3 : 8 + row * 3;
    final x = (point.dx + dx).clamp(0.0, size.width - painter.width);
    final y = (point.dy + dy).clamp(0.0, size.height - painter.height);
    final rect = Rect.fromLTWH(
      x - 3,
      y - 1,
      painter.width + 6,
      painter.height + 2,
    );
    final backgroundPaint = Paint()
      ..color = scheme.surface.withValues(alpha: 0.78);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      backgroundPaint,
    );
    painter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.colorIndexes != colorIndexes ||
      oldDelegate.selectedGroupId != selectedGroupId;
}

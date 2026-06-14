import 'dart:math' as math;

import 'package:flutter/material.dart';

const double kDesktopBreakpoint = 700;
const double kWideDesktopBreakpoint = 1000;
const double kContentMaxWidth = 1160;
const double kFormMaxWidth = 860;
const double kNarrowFormMaxWidth = 560;

bool isDesktopWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

double responsiveHorizontalPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= kWideDesktopBreakpoint) {
    return 40;
  }
  if (width >= kDesktopBreakpoint) {
    return 28;
  }
  return 16;
}

class ResponsiveListView extends StatelessWidget {
  const ResponsiveListView({
    super.key,
    required this.children,
    this.maxWidth = kContentMaxWidth,
    this.bottomPadding = 32,
    this.topPadding,
  });

  final List<Widget> children;
  final double maxWidth;
  final double bottomPadding;
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    final horizontal = responsiveHorizontalPadding(context);
    final top = topPadding ?? (isDesktopWidth(context) ? 24.0 : 16.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          0.0,
          math.min(maxWidth, constraints.maxWidth - horizontal * 2),
        );
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontal,
            top,
            horizontal,
            bottomPadding,
          ),
          children: [
            Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ResponsiveFieldGrid extends StatelessWidget {
  const ResponsiveFieldGrid({
    super.key,
    required this.children,
    this.breakpoint = 760,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }
        final fieldWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: fieldWidth, child: child),
          ],
        );
      },
    );
  }
}

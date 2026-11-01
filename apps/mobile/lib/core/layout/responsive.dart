import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const double kCompactMaxWidth = 600;
const double kExpandedMinWidth = 1024;
const double kPhoneContentWidth = 720;
const double kLargeContentWidth = 1100;
const double kGutterPhone = 16;
const double kGutterTablet = 24;
const double kGutterLarge = 32;

// NOTE: kRadiusSm and kRadiusLg are defined in app_theme.dart.
// They are NOT defined here to avoid "imported from both" ambiguity
// when screens import both responsive.dart and app_theme.dart.
// Use kRadiusSm/kRadiusLg from app_theme.dart (via mentor_desk_design.dart).

double _widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

bool isPhone(BuildContext context) => _widthOf(context) < kCompactMaxWidth;
bool isTablet(BuildContext context) {
  final w = _widthOf(context);
  return w >= kCompactMaxWidth && w < kExpandedMinWidth;
}
bool isLarge(BuildContext context) => _widthOf(context) >= kExpandedMinWidth;

int columnsFor(BuildContext context, {int min = 1, int max = 3, int? itemCount}) {
  var columns = isLarge(context) ? 3 : (isTablet(context) ? 2 : 1);
  if (columns < min) columns = min;
  if (columns > max) columns = max;
  if (itemCount != null && itemCount > 0 && columns > itemCount) columns = itemCount;
  return columns;
}

double horizontalGutter(BuildContext context) {
  if (isLarge(context)) return kGutterLarge;
  if (isTablet(context)) return kGutterTablet;
  return kGutterPhone;
}

double contentWidth(BuildContext context) =>
    isPhone(context) ? kPhoneContentWidth : kLargeContentWidth;

class AdaptivePage extends StatelessWidget {
  final Widget child;
  final bool center;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool respectTopSafeArea;
  final bool respectBottomSafeArea;

  const AdaptivePage({
    super.key,
    required this.child,
    this.center = true,
    this.maxWidth,
    this.padding,
    this.respectTopSafeArea = false,
    this.respectBottomSafeArea = false,
  });

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: padding ?? EdgeInsets.symmetric(horizontal: horizontalGutter(context)),
      child: child,
    );

    Widget content = padded;
    if (center) {
      final cap = maxWidth ?? contentWidth(context);
      content = LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.hasBoundedWidth ? constraints.maxWidth.clamp(0.0, cap) : null;
          return Align(
            alignment: Alignment.topCenter,
            child: width == null ? padded : SizedBox(width: width, child: padded),
          );
        },
      );
    }

    if (respectTopSafeArea || respectBottomSafeArea) {
      content = SafeArea(
        top: respectTopSafeArea,
        bottom: respectBottomSafeArea,
        child: content,
      );
    }

    return content;
  }
}

class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int? columns;
  final int minColumns;
  final int maxColumns;
  final double itemExtent;
  final double spacing;
  final bool scrollable;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.columns,
    this.minColumns = 1,
    this.maxColumns = 3,
    this.itemExtent = 120,
    this.spacing = 12,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final count = columns ??
        columnsFor(
          context,
          min: minColumns,
          max: maxColumns,
          itemCount: children.length,
        );

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final extent = itemExtent * (1 + (scale - 1) * 0.5);

    return GridView.count(
      crossAxisCount: count,
      mainAxisExtent: extent,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      primary: false,
      children: children,
    );
  }
}

class MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final TierAccent accent;

  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent.solid, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent.solid,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink600,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

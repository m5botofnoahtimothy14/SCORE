// Adaptive layout primitives.
//
// One set of width breakpoints for the whole app, so a small phone, a large
// phone, a foldable and a tablet all get the *same* visual language at the
// right density. Nothing here changes a colour, a radius or a typeface — it
// only decides how many things sit side by side and how wide a column of text
// may grow before it starts reading badly.
import 'package:flutter/material.dart';

/// Material window size classes, expressed as widths.
const double kCompactMaxWidth = 600; // phones, and narrow foldables
const double kExpandedMinWidth = 1024; // large tablets and desktop windows

/// Reading comfort: a text column wider than this gets hard to track.
const double kPhoneContentWidth = 720;
const double kLargeContentWidth = 1100;

/// Horizontal gutter at each size class. Phones keep today's 16 so nothing
/// moves; wider screens breathe a little more.
const double kGutterPhone = 16;
const double kGutterTablet = 24;
const double kGutterLarge = 32;

double _widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

/// Compact: a single-column, thumb-first layout.
bool isPhone(BuildContext context) => _widthOf(context) < kCompactMaxWidth;

/// Medium: a two-column layout with room for a side rail.
bool isTablet(BuildContext context) {
  final w = _widthOf(context);
  return w >= kCompactMaxWidth && w < kExpandedMinWidth;
}

/// Expanded: three columns and a permanently extended navigation rail.
bool isLarge(BuildContext context) => _widthOf(context) >= kExpandedMinWidth;

/// How many cards fit side by side at this width: 1 / 2 / 3.
///
/// [min] and [max] let a caller hold a specific look (for example the two
/// dashboard metric tiles stay paired on every device) and [itemCount] stops
/// the last row from being a lonely tile.
int columnsFor(BuildContext context, {int min = 1, int max = 3, int? itemCount}) {
  var columns = isLarge(context) ? 3 : (isTablet(context) ? 2 : 1);
  if (columns < min) columns = min;
  if (columns > max) columns = max;
  if (itemCount != null && itemCount > 0 && columns > itemCount) columns = itemCount;
  return columns;
}

/// Horizontal gutter that scales with the size class.
double horizontalGutter(BuildContext context) {
  if (isLarge(context)) return kGutterLarge;
  if (isTablet(context)) return kGutterTablet;
  return kGutterPhone;
}

/// Upper bound on the width of a screen's content. Beyond this, lines get too
/// long to read comfortably and dashboards start to look like a stretched
/// phone — so they are centred instead.
double contentWidth(BuildContext context) =>
    isPhone(context) ? kPhoneContentWidth : kLargeContentWidth;

/// Wraps a screen body with responsive padding and an optional max width.
///
/// Use it as the outermost widget of a `Scaffold.body`:
///
/// ```dart
/// Scaffold(body: AdaptivePage(child: myScrollView))
/// ```
///
/// [center] caps the content at [maxWidth] (or [contentWidth]) and centres it;
/// pass `center: false` for surfaces that are meant to be edge-to-edge.
/// Safe-area handling is opt-in because a `Scaffold` already consumes padding
/// for its app bar and bottom bar — only enable it where there is neither.
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
          // A tight width keeps the child's own layout intact — a Column, a
          // ListView and a bare SizedBox all end up the same width.
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

/// A grid of equally sized tiles that reflows with the window and is safe to
/// drop inside a scrolling parent.
///
/// Tiles are measured with [itemExtent] rather than an aspect ratio, so they
/// never squash on an unusual width or under a large text scale. The grid
/// shrink-wraps and refuses to scroll by default, which is what you want
/// inside a `CustomScrollView`/`ListView`; pass `scrollable: true` when the
/// grid *is* the scrollable.
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int? columns;
  final int minColumns;
  final int maxColumns;

  /// Logical height of one tile, before text scaling.
  final double itemExtent;
  final double spacing;

  /// When true the grid scrolls on its own instead of shrinking to fit.
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

    // Larger text needs a little more room; scale halfway so the grid does not
    // balloon, but never let a tile outgrow its content.
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
      // Nested grids must not grab the ambient PrimaryScrollController.
      primary: false,
      children: children,
    );
  }
}
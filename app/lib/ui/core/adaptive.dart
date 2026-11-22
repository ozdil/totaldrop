// SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:material_ui/material_ui.dart';

/// Material 3 window width classes for responsive phone, foldable, and tablet
/// layouts.
enum WindowSizeClass {
  /// Compact phones, folded cover screens, and narrow split-screen halves.
  compact,

  /// Unfolded square-ish foldables (600..839 dp) and small tablets.
  medium,

  /// Wide unfolded foldables, landscape tablets, and desktop windowing
  /// (>= 840 dp).
  expanded,
}

/// Physical posture reported by [DisplayFeature] folding features.
enum FoldPosture {
  /// No separating fold or hinge splits the window.
  flat,

  /// Vertical fold or hinge separating start and end panes (book posture or
  /// physical dual-screen hinge).
  book,

  /// Horizontal fold or hinge separating top and bottom panes (tabletop / flex
  /// posture on clamshell and book foldables).
  tabletop,
}

/// Derived window geometry and foldable posture for a screen.
///
/// Built solely from Flutter's [MediaQueryData] (`size`, `displayFeatures`,
/// `viewInsets`), keeping zero third-party dependencies while supporting
/// Android's Jetpack WindowManager folding features exposed by
/// `FlutterActivity`.
@immutable
class AdaptiveMetrics {
  const AdaptiveMetrics({
    required this.size,
    required this.sizeClass,
    required this.posture,
    required this.hinge,
    required this.flatVerticalCreaseX,
    required this.keyboardBlockingTabletop,
  });

  /// Logical size of the app window.
  final Size size;

  /// Material 3 width class of [size].
  final WindowSizeClass sizeClass;

  /// Active physical fold posture.
  final FoldPosture posture;

  /// Bounds of the separating fold or hinge in window coordinates, or null when
  /// [posture] is [FoldPosture.flat].
  final Rect? hinge;

  /// Horizontal position of a continuous flat vertical fold crease in window
  /// coordinates when fully unfolded, used to align two-pane gutters cleanly
  /// over the crease so interactive controls never straddle it.
  final double? flatVerticalCreaseX;

  /// True when the on-screen keyboard leaves too little vertical room below a
  /// horizontal fold for a usable tabletop control pane.
  final bool keyboardBlockingTabletop;

  /// Minimum pane width required on each side of a vertical split.
  static const double minPaneWidth = 220;

  /// Minimum height required for the lower tabletop control pane when an IME
  /// is visible.
  static const double minTabletopControlHeight = 180;

  /// Ultra-narrow foldable cover screens (such as 320–344 dp outer displays).
  bool get isNarrowCover => size.width < 340;

  /// Horizontal screen margin, tightened on narrow cover displays so 200% text
  /// scale and long translations keep breathing room.
  double get horizontalPadding => isNarrowCover ? 16 : 24;

  /// Side-by-side two-pane layout is active in book posture or on unfolded
  /// medium/expanded flat windows.
  bool get useBookLayout =>
      posture == FoldPosture.book ||
      (posture == FoldPosture.flat && sizeClass != WindowSizeClass.compact);

  /// Upper-display / lower-control layout is active in tabletop posture when
  /// the soft keyboard does not crowd out the lower half.
  bool get useTabletopLayout =>
      posture == FoldPosture.tabletop && !keyboardBlockingTabletop;

  /// Derives [AdaptiveMetrics] from [context]'s [MediaQuery].
  static AdaptiveMetrics of(BuildContext context, {Size? availableSize}) =>
      fromMediaQuery(MediaQuery.of(context), availableSize: availableSize);

  /// Pure computation from [mediaQuery], exposed for unit testing.
  ///
  /// When [availableSize] is provided (for instance from a [LayoutBuilder]
  /// inside a multi-window or split-screen surface), width classification uses
  /// the tighter of the window width and the available layout width so narrow
  /// viewports never attempt a cramped side-by-side layout.
  static AdaptiveMetrics fromMediaQuery(
    MediaQueryData mediaQuery, {
    Size? availableSize,
  }) {
    final windowSize = mediaQuery.size;
    final effectiveWidth = availableSize == null
        ? windowSize.width
        : math.min(windowSize.width, availableSize.width);
    final effectiveHeight = availableSize == null
        ? windowSize.height
        : math.min(windowSize.height, availableSize.height);
    final size = Size(effectiveWidth, effectiveHeight);
    final sizeClass = size.width >= 840
        ? WindowSizeClass.expanded
        : size.width >= 600
        ? WindowSizeClass.medium
        : WindowSizeClass.compact;

    FoldPosture posture = FoldPosture.flat;
    Rect? hinge;
    double? flatVerticalCreaseX;

    for (final feature in mediaQuery.displayFeatures) {
      if (!_isFoldingFeature(feature)) continue;
      final bounds = feature.bounds;
      final separating =
          feature.type == DisplayFeatureType.hinge ||
          bounds.shortestSide > 0 ||
          feature.state == DisplayFeatureState.postureHalfOpened;

      final isVertical =
          bounds.height >= bounds.width &&
          bounds.height >= windowSize.height * 0.75 &&
          bounds.left > 0 &&
          bounds.right < windowSize.width;
      final isHorizontal =
          bounds.width > bounds.height &&
          bounds.width >= windowSize.width * 0.75 &&
          bounds.top > 0 &&
          bounds.bottom < windowSize.height;

      if (isVertical && separating) {
        if (bounds.left >= minPaneWidth &&
            windowSize.width - bounds.right >= minPaneWidth &&
            size.width >= minPaneWidth * 2) {
          posture = FoldPosture.book;
          hinge = bounds;
          break;
        }
      } else if (isHorizontal && separating) {
        posture = FoldPosture.tabletop;
        hinge = bounds;
        break;
      } else if (isVertical &&
          !separating &&
          bounds.left >= windowSize.width * 0.3 &&
          bounds.left <= windowSize.width * 0.7) {
        flatVerticalCreaseX = bounds.left;
      }
    }

    var keyboardBlockingTabletop = false;
    if (posture == FoldPosture.tabletop && hinge != null) {
      final bottomRoom =
          windowSize.height - hinge.bottom - mediaQuery.viewInsets.bottom;
      if (mediaQuery.viewInsets.bottom > 0 &&
          bottomRoom < minTabletopControlHeight) {
        keyboardBlockingTabletop = true;
      }
    }

    return AdaptiveMetrics(
      size: size,
      sizeClass: sizeClass,
      posture: posture,
      hinge: hinge,
      flatVerticalCreaseX: flatVerticalCreaseX,
      keyboardBlockingTabletop: keyboardBlockingTabletop,
    );
  }

  static bool _isFoldingFeature(DisplayFeature feature) =>
      feature.type == DisplayFeatureType.hinge ||
      feature.type == DisplayFeatureType.fold;
}

/// Scales the Köşe mark proportionally for tight panes (narrow cover screens or
/// half-height tabletop upper panes) while preserving its 1:1 aspect ratio and
/// clear space.
double adaptiveMarkSize(
  BuildContext context,
  double base, {
  double minSize = 56,
}) {
  final metrics = AdaptiveMetrics.of(context);
  if (metrics.useTabletopLayout) {
    final topHeight = metrics.hinge?.top ?? (metrics.size.height / 2);
    if (topHeight < 300) {
      return math.max(minSize, math.min(base, topHeight * 0.34));
    }
    return math.max(minSize, math.min(base, 104));
  }
  if (metrics.isNarrowCover) {
    return math.max(minSize, math.min(base, 88));
  }
  return base;
}

/// Constrains single-stream screens (status, errors, simple confirmations) to a
/// comfortable reading width on unfolded foldables and tablets while staying
/// clear of any separating hinge or fold.
class ReadableColumn extends StatelessWidget {
  const ReadableColumn({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.avoidHinge = true,
  });

  final Widget child;
  final double maxWidth;
  final bool avoidHinge;

  @override
  Widget build(BuildContext context) {
    final constrained = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
    if (!avoidHinge) return constrained;
    final metrics = AdaptiveMetrics.of(context);
    if (metrics.posture == FoldPosture.flat ||
        metrics.keyboardBlockingTabletop) {
      return constrained;
    }
    return DisplayFeatureSubScreen(child: constrained);
  }
}

/// Canonical two-pane adaptive layout for phones, cover screens, unfolded
/// foldables, book posture, tabletop/flex posture, and tablets.
///
/// - On compact flat windows (phones and folded cover displays), builds
///   [compactBuilder] directly so single-column ergonomics stay unchanged.
/// - In book posture or unfolded medium/expanded windows, places [primary] and
///   [secondary] side by side via [Row] (which mirrors automatically in RTL
///   languages) and keeps every pixel out of the physical hinge or crease.
/// - In tabletop posture, places [tabletopPrimary] (or [primary]) in the upper
///   display half and [tabletopSecondary] (or [secondary]) in the lower
///   ergonomic control half, aligned to the physical horizontal fold in window
///   coordinates even below an [AppBar].
class AdaptivePaneLayout extends StatelessWidget {
  const AdaptivePaneLayout({
    super.key,
    required this.compactBuilder,
    required this.primary,
    required this.secondary,
    this.tabletopPrimary,
    this.tabletopSecondary,
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
    this.maxFlatWidth = 1080,
    this.showDivider = true,
    this.splitFlatWide = true,
  });

  /// Layout used on compact flat screens (phones, narrow cover screens, or
  /// tabletop fallback while the keyboard covers the bottom pane).
  final WidgetBuilder compactBuilder;

  /// Start pane in book / wide flat layouts (and default upper pane in
  /// tabletop posture).
  final Widget primary;

  /// End pane in book / wide flat layouts (and default lower pane in tabletop
  /// posture).
  final Widget secondary;

  /// Optional upper pane override for tabletop posture (e.g., showing the
  /// transfer code on the tilted display half).
  final Widget? tabletopPrimary;

  /// Optional lower pane override for tabletop posture.
  final Widget? tabletopSecondary;

  /// Relative flex weight of [primary] when splitting a flat wide window
  /// without a physical crease.
  final int primaryFlex;

  /// Relative flex weight of [secondary] when splitting a flat wide window
  /// without a physical crease.
  final int secondaryFlex;

  /// Maximum combined width of the two panes on very wide flat tablets or
  /// desktop windows without a physical hinge.
  final double maxFlatWidth;

  /// Whether to draw a quiet 1 px hairline along the pane boundary (matching
  /// TotalDrop's shadowless design system).
  final bool showDivider;

  /// Whether unfolded flat medium/expanded screens should split into two panes.
  /// When false, flat wide screens use [compactBuilder] (typically constrained
  /// to a readable column) while physical book/tabletop hinges still split.
  final bool splitFlatWide;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final appBarHeight = Scaffold.maybeOf(context)?.appBarMaxHeight ?? 0;

    return SafeArea(
      child: LayoutBuilder(
        builder: (safeContext, constraints) {
          final metrics = AdaptiveMetrics.fromMediaQuery(
            mq,
            availableSize: constraints.biggest,
          );
          if (metrics.useTabletopLayout && metrics.hinge != null) {
            return _TabletopLayout(
              hinge: metrics.hinge!,
              windowTopOffset: appBarHeight + mq.padding.top,
              showDivider: showDivider,
              top: tabletopPrimary ?? primary,
              bottom: tabletopSecondary ?? secondary,
              fallbackBuilder: compactBuilder,
            );
          }
          final useSideBySide =
              metrics.posture == FoldPosture.book ||
              (splitFlatWide && metrics.useBookLayout);
          if (useSideBySide) {
            return _BookOrWideLayout(
              metrics: metrics,
              windowLeftInset: mq.padding.left,
              primaryFlex: primaryFlex,
              secondaryFlex: secondaryFlex,
              maxFlatWidth: maxFlatWidth,
              showDivider: showDivider,
              primary: primary,
              secondary: secondary,
            );
          }
          return compactBuilder(safeContext);
        },
      ),
    );
  }
}

class _BookOrWideLayout extends StatelessWidget {
  const _BookOrWideLayout({
    required this.metrics,
    required this.windowLeftInset,
    required this.primaryFlex,
    required this.secondaryFlex,
    required this.maxFlatWidth,
    required this.showDivider,
    required this.primary,
    required this.secondary,
  });

  final AdaptiveMetrics metrics;
  final double windowLeftInset;
  final int primaryFlex;
  final int secondaryFlex;
  final double maxFlatWidth;
  final bool showDivider;
  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final hinge = metrics.hinge;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        // Physical vertical hinge or half-opened vertical fold: pin exact
        // start/end pane widths around the hinge so zero pixels overlap it.
        if (metrics.posture == FoldPosture.book && hinge != null) {
          final localLeft = (hinge.left - windowLeftInset).clamp(
            0.0,
            totalWidth,
          );
          final localRight = (hinge.right - windowLeftInset).clamp(
            localLeft,
            totalWidth,
          );
          final physicalGap = localRight - localLeft;
          final gap = math.min(totalWidth, math.max(physicalGap, 16.0));
          final pad = (gap - physicalGap) / 2;
          final physicalLeft = (localLeft - pad).clamp(0.0, totalWidth - gap);
          final physicalRight = math.max(0.0, totalWidth - physicalLeft - gap);
          final startWidth = isRtl ? physicalRight : physicalLeft;
          final endWidth = isRtl ? physicalLeft : physicalRight;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: startWidth, child: primary),
              SizedBox(
                width: gap,
                child: showDivider && physicalGap == 0
                    ? const Center(child: VerticalDivider(width: 1))
                    : null,
              ),
              SizedBox(width: endWidth, child: secondary),
            ],
          );
        }

        // Unfolded flat foldable with a known center crease: align the gutter
        // straight over the crease so cards and controls stay completely off it.
        final creaseX = metrics.flatVerticalCreaseX;
        if (creaseX != null) {
          final gutter = math.min(totalWidth, 24.0);
          final localCrease = (creaseX - windowLeftInset).clamp(
            0.0,
            totalWidth,
          );
          final physicalLeft = (localCrease - gutter / 2).clamp(
            0.0,
            totalWidth - gutter,
          );
          final physicalRight = math.max(
            0.0,
            totalWidth - physicalLeft - gutter,
          );
          if (physicalLeft >= AdaptiveMetrics.minPaneWidth &&
              physicalRight >= AdaptiveMetrics.minPaneWidth) {
            final startWidth = isRtl ? physicalRight : physicalLeft;
            final endWidth = isRtl ? physicalLeft : physicalRight;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: startWidth, child: primary),
                SizedBox(
                  width: gutter,
                  child: showDivider
                      ? const Center(child: VerticalDivider(width: 1))
                      : null,
                ),
                SizedBox(width: endWidth, child: secondary),
              ],
            );
          }
        }

        // Flat medium / expanded window (tablets, desktop windowing, foldables
        // without a reported flat crease): balanced two-pane layout centered up
        // to [maxFlatWidth].
        const gutter = 24.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxFlatWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: primaryFlex, child: primary),
                SizedBox(
                  width: gutter,
                  child: showDivider
                      ? const Center(child: VerticalDivider(width: 1))
                      : null,
                ),
                Expanded(flex: secondaryFlex, child: secondary),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabletopLayout extends StatelessWidget {
  const _TabletopLayout({
    required this.hinge,
    required this.windowTopOffset,
    required this.showDivider,
    required this.top,
    required this.bottom,
    required this.fallbackBuilder,
  });

  final Rect hinge;
  final double windowTopOffset;
  final bool showDivider;
  final Widget top;
  final Widget bottom;
  final WidgetBuilder fallbackBuilder;

  static const double _minHalfHeight = 110;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final localTop = (hinge.top - windowTopOffset).clamp(0.0, totalHeight);
        final localBottom = (hinge.bottom - windowTopOffset).clamp(
          localTop,
          totalHeight,
        );
        final physicalGap = localBottom - localTop;
        final gap = math.min(totalHeight, math.max(physicalGap, 16.0));
        final pad = (gap - physicalGap) / 2;
        final topHeight = (localTop - pad).clamp(0.0, totalHeight - gap);
        final bottomHeight = math.max(0.0, totalHeight - topHeight - gap);

        if (topHeight < _minHalfHeight || bottomHeight < _minHalfHeight) {
          return fallbackBuilder(context);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topHeight, child: top),
            SizedBox(
              height: gap,
              child: showDivider && physicalGap == 0
                  ? const Center(child: Divider(height: 1))
                  : null,
            ),
            SizedBox(height: bottomHeight, child: bottom),
          ],
        );
      },
    );
  }
}

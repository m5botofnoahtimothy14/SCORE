// The opening screen.
//
// This is ONE screen, not two. The brand mark and the CRIMSON X NOAH TIMOTHY
// KEBA lockup are shown together, on one surface, for the whole of the
// splash. The window is used to finish the boot sequence (session restore,
// identity load, push-token registration, presence) so the user lands in a
// READY app rather than a screen that still has to fetch everything.
//
// Two rules shape this file:
//   1. It must never strand the user. The handoff sits in a `finally` block,
//      so a cancelled ticker, a missing router or a failed animation still
//      lands on the next screen — and a slow backend cannot hold the app
//      hostage because the boot sequence has its own hard timeout.
//   2. It must respect the OS "reduce motion" setting. When animations are
//      disabled the composition is shown fully formed, with no looping effect,
//      and the handoff still happens after a short static pause.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../startup/startup_coordinator.dart';
import '../theme/app_theme.dart';

/// The opening screen runs for this long. The brand moment is deliberate:
/// the app uses the window to restore the session, resolve the identity,
/// register the push token and warm the connection, so the user lands in a
/// READY app rather than a screen that still has to fetch everything.
const Duration _kSplashDuration = Duration(seconds: 15);

/// How long the composition animates in.
const Duration _kIntro = Duration(milliseconds: 2200);

/// Static pause used when animations are disabled.
const Duration _kStaticDwell = Duration(milliseconds: 1500);

/// The composed splash: mark above, lockup below, both on one surface.
class SplashSequence extends StatefulWidget {
  const SplashSequence({super.key});

  @override
  State<SplashSequence> createState() => _SplashSequenceState();
}

class _SplashSequenceState extends State<SplashSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _kTimeline);

  /// The whole animation timeline: the composition rises in, holds while the
  /// boot sequence runs, then the screen fades out just before the handoff.
  static Duration get _kTimeline => _kSplashDuration;

  /// Brand mark + rule + lockup rise and fade in together, across the first
  /// part of the timeline. The composition is fully opaque from then on —
  /// it must never sit at zero alpha, or the screen would read as blank.
  late final Animation<double> _intro = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      0,
      _kIntro.inMilliseconds / _kSplashDuration.inMilliseconds,
      curve: Curves.easeOutCubic,
    ),
  );

  /// The whole composition fades out at the very end. The curve runs 1 -> 0
  /// across the last slice of the timeline, so the composition is fully
  /// opaque for the whole of the intro and the hold.
  late final Animation<double> _wholeFade = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.9, 1.0, curve: Curves.easeInOut),
    ),
  );

  /// Drives the determinate progress bar.
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 1, curve: Curves.linear),
  );

  /// One curve per letter of the signature, staggered across the lockup.
  late final List<CurvedAnimation> _letters = _staggerLetters();

  bool _started = false;
  bool _reduceMotion = false;
  StartupResult _result = StartupResult.empty;

  List<CurvedAnimation> _staggerLetters() {
    final glyphs = AppConfig.signatureName.split('');
    final count = glyphs.where((g) => g.trim().isNotEmpty).length;
    if (count == 0) return <CurvedAnimation>[];
    // The letters land inside the intro window, so the lockup is fully
    // formed well before the fade-out begins.
    final window = _kIntro.inMilliseconds / _kSplashDuration.inMilliseconds;
    final step = window / count;
    final curves = <CurvedAnimation>[];
    var index = 0;
    for (final glyph in glyphs) {
      if (glyph.trim().isEmpty) continue;
      final begin = index * step;
      curves.add(CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, (begin + step * 2.2).clamp(0.0, 1.0), curve: Curves.easeOut),
      ));
      index++;
    }
    return curves;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_started) return;
    _started = true;
    unawaited(_play());
  }

  @override
  void dispose() {
    for (final curve in _letters) {
      curve.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  /// Runs the boot sequence and the animation together, then hands off.
  Future<void> _play() async {
    // The boot work runs alongside the animation — never after it.
    final boot = StartupCoordinator.run().timeout(
      startupTimeout,
      onTimeout: () => StartupResult.empty,
    );

    try {
      if (_reduceMotion) {
        await Future<void>.delayed(_kStaticDwell);
      } else {
        await _controller.forward().orCancel;
      }
    } catch (_) {
      // Ticker cancelled or animation unavailable. Falling through is the
      // whole point: the handoff below still happens.
    } finally {
      _result = await boot;
      _goNext();
    }
  }

  void _goNext() {
    if (!mounted) return;
    try {
      GoRouter.of(context).go(_destination());
    } catch (error) {
      debugPrint('[CRIMSON] Splash handoff failed: $error');
    }
  }

  /// Where to go next.
  ///
  /// The boot result decides: a signed-in, onboarded user continues into the
  /// app; a signed-in user without a membership goes back to the school
  /// picker to finish enrollment; everyone else starts at the school picker.
  /// The router's own guard has the final say either way.
  String _destination() {
    try {
      if (_result.signedIn && _result.onboarded) return '/home';
      return '/auth/school-select';
    } catch (_) {
      return '/auth/school-select';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final onSurface = theme.textTheme.titleLarge?.color ?? AppColors.ink900;

    final composition = _Composition(
      letters: _reduceMotion ? null : _letters,
      onSurface: onSurface,
      progress: _reduceMotion ? null : _progress,
    );

    if (_reduceMotion) {
      // Everything shown fully formed, nothing moving, no loops.
      return Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: composition,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _wholeFade,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: FadeTransition(
                opacity: _intro,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(_intro),
                  child: composition,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole splash content as one column: mark, rule, lockup, credits and
/// the progress bar.
class _Composition extends StatelessWidget {
  final List<Animation<double>>? letters;
  final Color onSurface;
  final Animation<double>? progress;

  const _Composition({
    required this.letters,
    required this.onSurface,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animations = letters;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _BrandMark(),
        const SizedBox(height: 28),
        Container(
          width: 44,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: AppColors.brand.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 20),
        // The per-glyph spans below render as placeholder characters when a
        // screen reader walks the tree, so the phrase is announced once here
        // instead of as a string of broken fragments. `container: true` makes
        // this widget own that phrase as its own semantics node.
        Semantics(
          label: AppConfig.signatureLine,
          excludeSemantics: true,
          container: true,
          child: _LockupPanel(
            letters: animations,
            onSurface: onSurface,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Developed by ${AppConfig.developerName}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          '${AppConfig.appName}™ · secure school communication',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        if (progress != null) ...[
          const SizedBox(height: 30),
          _ProgressBar(progress: progress!),
          const SizedBox(height: 12),
          Text(
            'Preparing your school workspace…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              letterSpacing: 0.4,
              color: (onSurface == AppColors.ink900 ? Colors.white : onSurface)
                  .withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

/// The determinate progress bar under the lockup.
class _ProgressBar extends StatelessWidget {
  final Animation<double> progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);
    final fill = AppColors.brand.withValues(alpha: 0.85);

    return SizedBox(
      width: 180,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 3, color: track),
                FractionallySizedBox(
                  widthFactor: progress.value.clamp(0.0, 1.0),
                  child: Container(height: 3, color: fill),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The shield: a glossy gradient tile carrying the graduation cap, plus a
/// looping shine sweep that is skipped entirely when motion is reduced.
class _BrandMark extends StatefulWidget {
  const _BrandMark();

  @override
  State<_BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<_BrandMark> {
  late final bool _motionAllowed =
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  Widget build(BuildContext context) {
    return _ShineSweep(
      enabled: _motionAllowed,
      child: Container(
        width: 118,
        height: 118,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brand, AppColors.brandDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withValues(alpha: 0.32),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: const Icon(Icons.school_rounded, size: 56, color: Colors.white),
      ),
    );
  }
}

/// A slow diagonal light sweep across its child. Disabled means no controller
/// runs and the sweep never moves.
class _ShineSweep extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const _ShineSweep({required this.enabled, required this.child});

  @override
  State<_ShineSweep> createState() => _ShineSweepState();
}

class _ShineSweepState extends State<_ShineSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _shine.repeat();
  }

  @override
  void didUpdateWidget(_ShineSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _shine.repeat();
    } else {
      _shine.stop();
      _shine.value = 0;
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _shine,
      child: widget.child,
      builder: (context, child) {
        final t = _shine.value;
        return ShaderMask(
          blendMode: BlendMode.plus,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-2.0 + t * 3.4, -1.1),
            end: Alignment(-0.8 + t * 3.4, 1.1),
            colors: const [
              Color(0x00FFFFFF),
              Color(0x4DFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

/// The signature lockup, stacked.
///
/// CRIMSON sits above the cross, the name below it. The name is the widest
/// element, so it is scaled down to fit the narrowest phone rather than
/// wrapping onto a second line.
class _LockupPanel extends StatelessWidget {
  final List<Animation<double>>? letters;
  final Color onSurface;

  const _LockupPanel({required this.letters, required this.onSurface});

  static const topStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: 5.0,
    height: 1.2,
  );

  static const crossStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    height: 1.2,
  );

  static const nameStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    final animations = letters;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // CRIMSON
        Text(
          AppConfig.signatureTop,
          textAlign: TextAlign.center,
          style: topStyle.copyWith(color: onSurface),
        ),
        const SizedBox(height: 4),
        // the cross
        Text(
          AppConfig.signatureCross,
          textAlign: TextAlign.center,
          style: crossStyle.copyWith(color: AppColors.brand),
        ),
        const SizedBox(height: 6),
        // NOAH TIMOTHY KEBA
        FittedBox(
          fit: BoxFit.scaleDown,
          child: animations == null
              ? Text(
                  AppConfig.signatureName,
                  textAlign: TextAlign.center,
                  style: nameStyle.copyWith(color: onSurface),
                )
              : Text.rich(
                  spans(animations, onSurface),
                  textAlign: TextAlign.center,
                ),
        ),
      ],
    );
  }

  /// One [WidgetSpan] per glyph of the name. The signature text is preserved
  /// exactly, so screen readers still announce a single coherent phrase.
  static InlineSpan spans(List<Animation<double>> animations, Color color) {
    final spans = <InlineSpan>[];
    var index = 0;
    for (final glyph in AppConfig.signatureName.split('')) {
      if (glyph.trim().isEmpty) {
        spans.add(TextSpan(text: glyph, style: nameStyle));
        continue;
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _LetterIn(
            animation: animations[index],
            child: Text(glyph, style: nameStyle.copyWith(color: color)),
          ),
        ),
      );
      index++;
    }
    return TextSpan(style: nameStyle, children: spans);
  }
}

/// One glyph fading and lifting into place.
class _LetterIn extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _LetterIn({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.45),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

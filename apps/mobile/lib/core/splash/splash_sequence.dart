// Opening sequence: brand mark, then the CRIMSON X NOAH TIMOTHY KEBA lockup,
// then a short fade out into the app.
//
// Two rules shape this file:
//   1. It must never strand the user. The handoff sits in a `finally` block, so
//      a cancelled ticker, a missing router or a failed animation still lands
//      on the next screen.
//   2. It must respect the OS "reduce motion" setting. When animations are
//      disabled both panels are shown fully formed, with no looping effect,
//      and the handoff still happens after a short static pause.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// How long panel one holds before the cross-fade begins.
const Duration _kHold = Duration(milliseconds: 1600);

/// Length of the cross-fade between the two panels.
const Duration _kCrossFade = Duration(milliseconds: 500);

/// Whole-screen fade out at the very end.
const Duration _kFadeOut = Duration(milliseconds: 400);

/// Static pause used when animations are disabled.
const Duration _kStaticDwell = Duration(milliseconds: 900);

Duration get _kTotal => _kHold + _kCrossFade + _kFadeOut;

double _at(Duration offset) => offset.inMilliseconds / _kTotal.inMilliseconds;

class SplashSequence extends StatefulWidget {
  const SplashSequence({super.key});

  @override
  State<SplashSequence> createState() => _SplashSequenceState();
}

class _SplashSequenceState extends State<SplashSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _kTotal);

  /// Mark: scale + fade in over the first half, fade out at the handoff.
  late final Animation<double> _markIn = CurvedAnimation(
    parent: _controller,
    curve: Interval(0.0, _at(const Duration(milliseconds: 900)), curve: Curves.easeOutCubic),
  );

  late final Animation<double> _markOut = CurvedAnimation(
    parent: _controller,
    curve: Interval(_at(_kHold), 1.0, curve: Curves.easeInCubic),
  );

  /// Lockup: starts 200ms before the mark begins leaving, so the cross-fade
  /// overlaps instead of cutting.
  late final Animation<double> _lockupIn = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _at(_kHold - const Duration(milliseconds: 200)),
      _at(_kHold + _kCrossFade),
      curve: Curves.easeOut,
    ),
  );

  late final Animation<double> _wholeFade = CurvedAnimation(
    parent: _controller,
    curve: Interval(_at(_kHold + _kCrossFade), 1.0, curve: Curves.easeInOut),
  );

  /// One curve per letter of the signature, staggered across panel two.
  late final List<CurvedAnimation> _letters = _staggerLetters();

  bool _started = false;
  bool _reduceMotion = false;

  List<CurvedAnimation> _staggerLetters() {
    final glyphs = AppConfig.signatureLine.split('');
    final count = glyphs.where((g) => g.trim().isNotEmpty).length;
    final step = 0.6 / count;
    final curves = <CurvedAnimation>[];
    var index = 0;
    for (final glyph in glyphs) {
      if (glyph.trim().isEmpty) continue;
      final begin = index * step;
      curves.add(CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, begin + step * 2.2, curve: Curves.easeOut),
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

  /// Runs the sequence, then navigates onward whatever happened.
  Future<void> _play() async {
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

  /// Signed-in users continue into the app; everyone else lands on the school
  /// picker. The router's own guard has the final say either way.
  String _destination() {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      return session == null ? '/auth/school-select' : '/home';
    } catch (_) {
      return '/auth/school-select';
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;

    if (_reduceMotion) {
      // Both panels, fully formed, nothing moving, no loops.
      return Scaffold(
        backgroundColor: background,
        body: const SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: _BrandPanel(entry: null)),
              Center(child: _LockupPanel(letters: null)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _wholeFade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FadeTransition(
                opacity: _markOut,
                child: Center(
                  child: _BrandPanel(entry: _markIn),
                ),
              ),
              FadeTransition(
                opacity: _lockupIn,
                child: Center(child: _LockupPanel(letters: _letters)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel one: the TeachCross shield, scaling and fading in with a slow shine.
/// A null [entry] renders the final state immediately (reduce motion).
class _BrandPanel extends StatelessWidget {
  final Animation<double>? entry;

  const _BrandPanel({required this.entry});

  @override
  Widget build(BuildContext context) {
    final mark = _BrandMark(animated: entry != null);
    final animation = entry;
    if (animation == null) return mark;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.86, end: 1.0).animate(animation),
      child: FadeTransition(opacity: animation, child: mark),
    );
  }
}

/// The shield: a glossy gradient tile carrying the graduation cap, plus a
/// looping shine sweep that is skipped entirely when motion is reduced.
class _BrandMark extends StatelessWidget {
  final bool animated;

  const _BrandMark({required this.animated});

  @override
  Widget build(BuildContext context) {
    return _ShineSweep(
      enabled: animated,
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
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
        child: const Icon(Icons.school_rounded, size: 62, color: Colors.white),
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

/// Panel two: the signature lockup, letter by letter. A null [letters] list
/// renders the whole string as plain static text — one coherent string for
/// screen readers and for reduce-motion users.
class _LockupPanel extends StatelessWidget {
  final List<Animation<double>>? letters;

  const _LockupPanel({required this.letters});

  static const _headStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    height: 1.5,
  );

  static const _subStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.6,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.textTheme.titleLarge?.color ?? AppColors.ink900;
    final animations = letters;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: AppColors.brand.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 26),
          // The per-glyph spans below render as placeholder characters when a
          // screen reader walks the tree, so the phrase is announced once here
          // instead of as a string of broken fragments.
          Semantics(
            label: AppConfig.signatureLine,
            excludeSemantics: true,
            child: animations == null
                ? Text(
                    AppConfig.signatureLine,
                    textAlign: TextAlign.center,
                    style: _headStyle.copyWith(color: onSurface),
                  )
                : Text.rich(
                    _lockupSpans(animations, onSurface),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }

  /// One [WidgetSpan] per glyph. The signature text is preserved exactly, so
  /// screen readers still announce a single coherent phrase.
  InlineSpan _lockupSpans(List<Animation<double>> animations, Color color) {
    final spans = <InlineSpan>[];
    var index = 0;
    for (final glyph in AppConfig.signatureLine.split('')) {
      if (glyph.trim().isEmpty) {
        spans.add(TextSpan(text: glyph, style: _headStyle));
        continue;
      }
      // Alternate sizes so "CRIMSON X" and "NOAH TIMOTHY KEBA" read as two
      // halves of one lockup rather than a run-on shout.
      final style = index.isEven ? _headStyle : _subStyle;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _LetterIn(
            animation: animations[index],
            child: Text(glyph, style: style.copyWith(color: color)),
          ),
        ),
      );
      index++;
    }
    return TextSpan(style: _headStyle, children: spans);
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

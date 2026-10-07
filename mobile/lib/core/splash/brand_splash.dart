import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/branding.dart';

/// Brand moment on cold start: the lollipop head pops in, the stick draws
/// down, the five sound-wave bars rise one after another, the wordmark
/// and tagline lift in under it, then the whole overlay fades to reveal
/// the app -- which has been building underneath the entire time, so
/// nothing is delayed beyond the animation itself.
///
/// Lives in Flutter rather than Android's splash API because the OS
/// dismisses its splash on Flutter's first frame (about 300 ms warm),
/// too soon for any animation to be seen. The OS splash is a plain
/// brand-plum screen (android res/values/colors.xml, same colour as
/// AppTheme.plum), so the hand-over into this overlay is seamless.
///
/// Plays once per process. Start-up rebuilds (the MaterialApp re-rooting
/// as auth state resolves) recreate this widget; a fresh instance resumes
/// from the elapsed wall-clock time instead of replaying or skipping.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, required this.child, this.duration = defaultDuration});

  final Widget child;
  final Duration duration;

  static const Duration defaultDuration = Duration(milliseconds: 2600);

  static DateTime? _startedAt;

  /// Wall clock, overridable so tests can simulate a later process time
  /// (the widget-test clock does not move DateTime.now()).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Tests: forget the shared start time so the sequence plays again.
  @visibleForTesting
  static void resetForTesting() {
    _startedAt = null;
    clock = DateTime.now;
  }

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final startedAt = BrandSplash._startedAt ??= BrandSplash.clock();
    final elapsed = BrandSplash.clock().difference(startedAt);
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (elapsed >= widget.duration) {
      _done = true;
      return;
    }
    _controller.forward(from: elapsed.inMilliseconds / widget.duration.inMilliseconds).whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => BrandSplashOverlay(t: _controller.value),
        ),
      ],
    );
  }
}

/// The overlay at a given point [t] (0..1) of the sequence. Public and
/// stateless so it can be rendered at a fixed frame in tests and tooling.
class BrandSplashOverlay extends StatelessWidget {
  const BrandSplashOverlay({super.key, required this.t});

  final double t;

  double _seg(double from, double to, [Curve curve = Curves.easeOut]) {
    final v = ((t - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final mark = _seg(0.00, 0.62, Curves.linear);
    final word = _seg(0.42, 0.62, Curves.easeOutCubic);
    final tagline = _seg(0.56, 0.76);
    final fade = 1 - _seg(0.88, 1.00, Curves.easeIn);

    // Material ancestor: this overlay sits above the Navigator, and Text
    // without one renders with the yellow double underline.
    return IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: brandGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LollyMark(size: 148, progress: mark, style: LollyMarkStyle.onGradient),
                  const SizedBox(height: AppSpacing.lg),
                  Opacity(
                    opacity: word,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - word)),
                      child: const AppWordmark(fontSize: 42, color: Colors.white, accentColor: AppTheme.peach),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Opacity(
                    opacity: tagline,
                    child: Text(
                      kAppTagline,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 16,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

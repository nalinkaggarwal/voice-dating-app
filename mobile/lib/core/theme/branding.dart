import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The product line, used on the splash and the auth hero.
const String kAppTagline = 'Hear before you see.';

/// The brand gradient (plum to magenta) for hero surfaces: splash, auth
/// header, match screen, launcher-icon background. Same two stops as
/// android/.../drawable/ic_launcher_background.xml.
LinearGradient brandGradient({
  AlignmentGeometry begin = Alignment.topLeft,
  AlignmentGeometry end = Alignment.bottomRight,
}) =>
    LinearGradient(begin: begin, end: end, colors: const [AppTheme.plum, AppTheme.magenta]);

/// Which surface the mark sits on. Only the stick changes: white on the
/// gradient, plum on a light surface. Head and sound wave are constant.
enum LollyMarkStyle { onGradient, onSurface }

/// The Lolly mark: a lollipop whose head holds a sound wave -- the name
/// and the motto in one shape. Drawn in code (not an asset) so the
/// splash, app bar, match screen and the launcher icon (rendered from
/// this same painter by tool/brand/render_launcher_icons_test.dart) can
/// never drift apart.
///
/// [progress] (0..1) plays the build-in used by the splash: the head pops,
/// the stick draws down, the five bars rise one after another.
class LollyMark extends StatelessWidget {
  const LollyMark({
    super.key,
    this.size = 48,
    this.progress = 1,
    this.style = LollyMarkStyle.onSurface,
    this.withBackground = false,
    this.cornerRadiusFactor = 0.22,
    this.inset = 0,
  });

  final double size;
  final double progress;
  final LollyMarkStyle style;

  /// Paint the brand gradient behind the mark in a rounded square (the
  /// legacy launcher icon look; also the drawer/hero tile).
  final bool withBackground;
  final double cornerRadiusFactor;

  /// Fraction of each edge left empty around the mark (adaptive-icon
  /// safe zone, or just breathing room).
  final double inset;

  @override
  Widget build(BuildContext context) {
    final painter = LollyMarkPainter(
      progress: progress,
      stickColor: style == LollyMarkStyle.onGradient ? Colors.white : AppTheme.plum,
      inset: inset,
    );
    final mark = CustomPaint(size: Size.square(size), painter: painter);
    if (!withBackground) return SizedBox.square(dimension: size, child: mark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: brandGradient(),
        borderRadius: BorderRadius.circular(size * cornerRadiusFactor),
      ),
      child: mark,
    );
  }
}

class LollyMarkPainter extends CustomPainter {
  LollyMarkPainter({
    required this.progress,
    required this.stickColor,
    this.headColor = AppTheme.coral,
    this.headHighlight = AppTheme.coralLight,
    this.barColor = Colors.white,
    this.inset = 0,
  });

  final double progress;
  final Color stickColor;
  final Color headColor;
  final Color headHighlight;
  final Color barColor;
  final double inset;

  /// Bar heights as a fraction of the head radius, centre bar tallest.
  static const List<double> barHeights = [0.55, 0.95, 1.3, 0.95, 0.55];

  double _seg(double from, double to, [Curve curve = Curves.easeOut]) {
    final v = ((progress - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide * (1 - 2 * inset);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);

    final center = Offset(0.5 * s, 0.40 * s);
    final r = 0.29 * s;

    // Stick first so the head covers its top end.
    final stickT = _seg(0.15, 0.50, Curves.easeOutCubic);
    if (stickT > 0) {
      final w = 0.08 * s;
      final top = center.dy + r * 0.55;
      final fullLength = 0.94 * s - top;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - w / 2, top, w, fullLength * stickT),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(rect, Paint()..color = stickColor);
    }

    final headT = _seg(0.0, 0.35, Curves.easeOutBack);
    if (headT > 0) {
      final radius = r * headT;
      final headPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [headHighlight, headColor],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, headPaint);
    }

    // Sound wave: five bars, staggered.
    final barW = 0.17 * r;
    final gap = 0.14 * r;
    final barPaint = Paint()..color = barColor;
    for (var i = 0; i < barHeights.length; i++) {
      final t = _seg(0.30 + 0.07 * i, 0.62 + 0.07 * i, Curves.easeOutBack);
      if (t <= 0) continue;
      final h = barHeights[i] * r * t;
      final cx = center.dx + (i - 2) * (barW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, center.dy), width: barW, height: h),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rect, barPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(LollyMarkPainter old) =>
      old.progress != progress ||
      old.stickColor != stickColor ||
      old.headColor != headColor ||
      old.barColor != barColor ||
      old.inset != inset;
}

/// "Lolly.ai" set as a wordmark: heavy "Lolly", the ".ai" lighter and in
/// the coral accent, so the name reads as a brand rather than a label.
class AppWordmark extends StatelessWidget {
  const AppWordmark({
    super.key,
    this.fontSize = 22,
    this.color,
    this.accentColor = AppTheme.coral,
    this.withMark = false,
    this.markSize,
    this.markStyle = LollyMarkStyle.onSurface,
  });

  final double fontSize;
  final Color? color;
  final Color accentColor;
  final bool withMark;
  final double? markSize;
  final LollyMarkStyle markStyle;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.onSurface;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Lolly',
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: base, letterSpacing: -0.6),
          ),
          TextSpan(
            text: '.ai',
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: accentColor, letterSpacing: -0.3),
          ),
        ],
      ),
    );
    if (!withMark) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LollyMark(size: markSize ?? fontSize * 1.4, style: markStyle),
        SizedBox(width: fontSize * 0.4),
        text,
      ],
    );
  }
}

/// A row of bars that breathe while [active] -- the app's recurring cue
/// for "a voice is playing / this is a voice". Static, low bars when idle.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.active,
    this.barCount = 7,
    this.height = 28,
    this.barWidth = 4,
    this.gap = 3,
    this.color,
  });

  final bool active;
  final int barCount;
  final double height;
  final double barWidth;
  final double gap;
  final Color? color;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Idle silhouette: a gentle centre-weighted hump.
  double _idleFraction(int i) {
    final mid = (widget.barCount - 1) / 2;
    final d = (i - mid).abs() / (mid == 0 ? 1 : mid);
    return 0.25 + 0.45 * (1 - d);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.barCount; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                _bar(i, t, color),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _bar(int i, double t, Color color) {
    final idle = _idleFraction(i);
    final fraction = widget.active
        ? 0.2 + 0.8 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + i * 0.13))) * (0.5 + idle)
        : idle;
    return Container(
      width: widget.barWidth,
      height: widget.height * fraction.clamp(0.12, 1.0),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(widget.barWidth / 2)),
    );
  }
}

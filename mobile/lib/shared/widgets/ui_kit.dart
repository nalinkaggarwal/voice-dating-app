import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/branding.dart';

/// Shared "Midnight Bloom" building blocks (see AppTheme). Screens compose
/// these instead of styling raw Material widgets, so every surface gets
/// the same glow, gradient and spacing.

/// The ink canvas with two soft, blurred colour blooms behind [child] --
/// the ambient light every full-screen surface sits in.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child, this.intensity = 1});

  final Widget child;

  /// 0..1 -- dial the glow down on content-heavy screens (chat, lists).
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Radial falloff instead of a blur filter: same soft bloom, no
    // per-frame BackdropFilter cost on scrolling screens.
    Widget blob(Color color, double diameter, double alpha) => IgnorePointer(
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color.withValues(alpha: alpha * intensity), color.withValues(alpha: 0)],
                stops: const [0, 1],
              ),
            ),
          ),
        );

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppTheme.ink)),
        Positioned(
          top: -size.width * 0.35,
          left: -size.width * 0.3,
          child: blob(AppTheme.plum, size.width * 0.95, 0.42),
        ),
        Positioned(
          top: -size.width * 0.15,
          right: -size.width * 0.45,
          child: blob(AppTheme.magenta, size.width * 0.85, 0.30),
        ),
        Positioned(
          bottom: -size.width * 0.5,
          left: size.width * 0.1,
          child: blob(AppTheme.coral, size.width * 0.8, 0.12),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// The one primary action per screen: a pill filled with the Bloom
/// gradient and a soft glow. Disabled -> flat surface, no glow.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.height = 58,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        gradient: enabled || loading ? brandGradient(begin: Alignment.centerLeft, end: Alignment.centerRight) : null,
        color: enabled || loading ? null : AppTheme.surface3,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppTheme.magenta.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: -6,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(height),
          onTap: enabled ? onPressed : null,
          // Crossfade label/spinner changes (e.g. "Send my code" <-> "Log in"
          // when the auth toggle slides) instead of snapping.
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: loading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    key: ValueKey(label),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: enabled ? Colors.white : AppTheme.textMuted, size: 22),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          letterSpacing: 0.1,
                          color: enabled ? Colors.white : AppTheme.textMuted,
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

/// A frosted card: translucent surface, hairline border. [selected] swaps
/// the border for the Bloom gradient and warms the fill.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md + 4),
    this.selected = false,
    this.onTap,
    this.radius = AppRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final inner = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius - (selected ? 1.5 : 0)),
        color: selected ? const Color(0xFF26142A) : AppTheme.surface1.withValues(alpha: 0.78),
        border: selected ? null : Border.all(color: AppTheme.stroke),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (!selected) return inner;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: brandGradient(),
        boxShadow: [
          BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.25), blurRadius: 24, spreadRadius: -8),
        ],
      ),
      child: inner,
    );
  }
}

/// A selectable pill (multi- or single-select chips). Selected -> Bloom
/// gradient fill with a check.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: selected ? brandGradient() : null,
          color: selected ? null : AppTheme.surface2,
          border: Border.all(color: selected ? Colors.transparent : AppTheme.stroke),
          boxShadow: selected
              ? [BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -6)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: selected
                  ? const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.sm),
                      child: Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A large single-choice option: emoji badge, title, subtitle, radio dot.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final compact = isCompactHeight(context);
    final badge = compact ? 42.0 : 52.0;
    return GlassCard(
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md + 4, vertical: compact ? 14 : AppSpacing.md + 4),
      child: Row(
        children: [
          Container(
            width: badge,
            height: badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(emoji, style: TextStyle(fontSize: compact ? 22 : 26)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected ? brandGradient() : null,
              border: selected ? null : Border.all(color: const Color(0x40FFFFFF), width: 2),
            ),
            child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
          ),
        ],
      ),
    );
  }
}

/// Label on the left, a highlighted value badge on the right -- heads a
/// slider or a settings group.
class LabeledValue extends StatelessWidget {
  const LabeledValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: textTheme.titleMedium)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.magenta.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFF8AC2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small rounded error banner, used in place of bare red text.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontFamily: AppTheme.fontFamily, color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented progress bar: [current] of [total] segments lit with the
/// Bloom gradient.
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({super.key, required this.current, required this.total});

  /// 1-based.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: i < current ? brandGradient(begin: Alignment.centerLeft, end: Alignment.centerRight) : null,
                color: i < current ? null : AppTheme.surface3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Phones shorter than this (logical px) get the compact layout: smaller
/// headline, tighter gaps -- so steps fit without scrolling where they can.
const double kCompactHeight = 760;

bool isCompactHeight(BuildContext context) => MediaQuery.sizeOf(context).height < kCompactHeight;

/// The shared onboarding step layout: progress bar + step counter on top,
/// headline (emoji inline, to save a line) and subtitle, a body that is
/// laid out to fit without scrolling where possible, and the primary
/// action pinned to the bottom.
///
/// When the body genuinely needs to scroll (small phone, long AI draft,
/// keyboard open) it never just gets cut off: the clipped edge fades out,
/// a slim gradient scrollbar shows position, and a "More below" pill
/// bobs at the bottom until the user reaches the end (tap = scroll down).
class OnboardingScaffold extends StatefulWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.child,
    this.subtitle,
    this.emoji,
    this.primaryLabel,
    this.onPrimary,
    this.primaryIcon,
    this.loading = false,
    this.errorMessage,
    this.secondary,
    this.trailing,
  });

  final int step;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final String? emoji;
  final Widget child;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? primaryIcon;
  final bool loading;
  final String? errorMessage;

  /// Optional extra action under the primary button (e.g. "Re-record").
  final Widget? secondary;

  /// Optional widget at the right of the top bar (e.g. log out).
  final Widget? trailing;

  @override
  State<OnboardingScaffold> createState() => _OnboardingScaffoldState();
}

class _OnboardingScaffoldState extends State<OnboardingScaffold> {
  @override
  Widget build(BuildContext context) {
    final w = widget;
    final textTheme = Theme.of(context).textTheme;
    final compact = isCompactHeight(context);
    final titleStyle = compact ? textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800) : textTheme.headlineMedium;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              if (w.emoji != null) TextSpan(text: '${w.emoji}  '),
              TextSpan(text: w.title),
            ],
          ),
          style: titleStyle,
        ),
        if (w.subtitle != null) ...[
          SizedBox(height: compact ? 6 : AppSpacing.sm),
          Text(
            w.subtitle!,
            style: (compact ? textTheme.bodyMedium : textTheme.bodyLarge)?.copyWith(color: AppTheme.textMuted),
          ),
        ],
        SizedBox(height: compact ? AppSpacing.md + 4 : AppSpacing.lg + 4),
        w.child,
        if (w.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(w.errorMessage!),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, compact ? AppSpacing.sm : AppSpacing.md, AppSpacing.lg, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const LollyMark(size: 24),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Step ${w.step} of ${w.totalSteps}',
                          style: textTheme.labelLarge?.copyWith(color: AppTheme.textMuted),
                        ),
                        const Spacer(),
                        if (w.trailing != null) w.trailing!,
                      ],
                    ),
                    SizedBox(height: compact ? AppSpacing.sm + 2 : AppSpacing.md),
                    StepProgressBar(current: w.step, total: w.totalSteps),
                  ],
                ),
              ),
              Expanded(
                child: FadingScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    compact ? AppSpacing.md : AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: body,
                ),
              ),
              if (w.primaryLabel != null || w.secondary != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, compact ? AppSpacing.sm : AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (w.primaryLabel != null)
                        GradientButton(
                          label: w.primaryLabel!,
                          icon: w.primaryIcon,
                          loading: w.loading,
                          onPressed: w.onPrimary,
                          height: compact ? 52 : 58,
                        ),
                      if (w.secondary != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        w.secondary!,
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scroll view that never just cuts content off: while there is more
/// above/below, that edge fades out, a slim gradient scrollbar shows the
/// position, and a "More below" pill bobs at the bottom until the end is
/// reached (tap = scroll to the end). Looks like a plain page when
/// everything fits.
class FadingScrollView extends StatefulWidget {
  const FadingScrollView({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<FadingScrollView> createState() => _FadingScrollViewState();
}

class _FadingScrollViewState extends State<FadingScrollView> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  bool _canScroll = false;
  bool _atTop = true;
  bool _atBottom = true;
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardOpen = _readKeyboard();
  }

  // Read from the window, NOT MediaQuery: a Scaffold (which every screen
  // here has) zeroes viewInsets.bottom for its body after resizing for
  // the keyboard, so MediaQuery down here always says "no keyboard".
  bool _readKeyboard() => View.of(context).viewInsets.bottom > 0;

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final open = _readKeyboard();
    if (open != _keyboardOpen) setState(() => _keyboardOpen = open);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  // Fires on every layout change (content grows, keyboard opens) and on
  // every scroll, so the fades and the hint always reflect reality.
  bool _onMetrics(ScrollMetrics m) {
    // Only the page scroller -- not a TextField's own inner scrollable.
    if (m.axis != Axis.vertical) return false;
    final canScroll = m.maxScrollExtent > 1;
    // A couple of px of slack: fractional device pixels and the end of a
    // fling can stop just short of the exact extent.
    final atTop = m.pixels <= m.minScrollExtent + 2;
    final atBottom = m.pixels >= m.maxScrollExtent - 2;
    if (canScroll != _canScroll || atTop != _atTop || atBottom != _atBottom) {
      // Metrics notifications arrive during layout; defer the rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _canScroll = canScroll;
            _atTop = atTop;
            _atBottom = atBottom;
          });
        }
      });
    }
    return false;
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fadeTop = _canScroll && !_atTop;
    final fadeBottom = _canScroll && !_atBottom;
    // With the keyboard up the viewport is squeezed and the user is busy
    // typing -- the pill would just sit on the field. Keep the edge fade
    // (quiet), drop the pill.
    final showHint = fadeBottom && !_keyboardOpen;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  fadeTop ? Colors.transparent : Colors.white,
                  Colors.white,
                  Colors.white,
                  fadeBottom ? Colors.transparent : Colors.white,
                ],
                // Clamped so a tiny viewport (keyboard open on a small
                // phone) can't produce unordered stops.
                stops: [
                  0,
                  (28 / rect.height).clamp(0.0, 0.3),
                  (1 - 56 / rect.height).clamp(0.7, 1.0),
                  1,
                ],
              ).createShader(rect),
              child: RawScrollbar(
                controller: _scroll,
                thumbVisibility: _canScroll,
                thickness: 4,
                radius: const Radius.circular(4),
                crossAxisMargin: 6,
                mainAxisMargin: 12,
                thumbColor: AppTheme.magenta.withValues(alpha: 0.7),
                child: SingleChildScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: widget.padding,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: IgnorePointer(
              ignoring: !showHint,
              child: AnimatedOpacity(
                opacity: showHint ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: _MoreBelowHint(onTap: _scrollToEnd),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Frosted "More below" pill with a bobbing chevron.
class _MoreBelowHint extends StatefulWidget {
  const _MoreBelowHint({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_MoreBelowHint> createState() => _MoreBelowHintState();
}

class _MoreBelowHintState extends State<_MoreBelowHint> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
        decoration: BoxDecoration(
          color: AppTheme.surface3.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.stroke),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'More below',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            AnimatedBuilder(
              animation: _bob,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, 3 * Curves.easeInOut.transform(_bob.value)),
                child: child,
              ),
              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Color(0xFFFF8AC2)),
            ),
          ],
        ),
      ),
    );
  }
}

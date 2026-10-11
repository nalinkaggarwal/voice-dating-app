import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/branding.dart';

/// Centred glowing icon badge + title + optional body + optional action.
/// The one layout for "nothing here yet", "something went wrong" and
/// "coming later", so those states look like the same app.
///
/// Scrolls on its own when given a bounded height that's too short for
/// it (small phones, keyboard open) -- never a "BOTTOM OVERFLOWED" strip.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowBadge(icon: icon, iconColor: iconColor),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                body!,
                style: theme.textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Inside an outer scroll view (unbounded height) just centre;
        // otherwise scroll if the space is too short.
        if (!constraints.hasBoundedHeight) return Center(child: content);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight, minWidth: constraints.maxWidth),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

/// The icon in a softly glowing, gradient-ringed disc.
class _GlowBadge extends StatelessWidget {
  const _GlowBadge({required this.icon, this.iconColor});

  final IconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: brandGradient(),
        boxShadow: [
          BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: -6),
        ],
      ),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.surface1),
        child: Icon(icon, size: 44, color: iconColor ?? AppTheme.coralLight),
      ),
    );
  }
}

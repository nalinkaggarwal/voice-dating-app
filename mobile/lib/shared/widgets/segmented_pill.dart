import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/branding.dart';

/// A two-or-more-way toggle drawn as one pill: a single Bloom-gradient
/// capsule SLIDES under the labels to the selected option (rather than
/// each option lighting up like a separate button), and the label colours
/// crossfade as it moves. Tap an option, or swipe the pill left/right.
/// Replaces Material's SegmentedButton on the auth screen, whose boxy
/// outline reads dated next to the rest of the UI.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  }) : assert(values.length == labels.length);

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  static const _slide = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final count = values.length;
    final index = values.indexOf(selected).clamp(0, count - 1);
    // Alignment.x runs -1 (first option) .. 1 (last option).
    final x = count == 1 ? 0.0 : -1 + 2 * index / (count - 1);

    void step(int delta) {
      final next = (index + delta).clamp(0, count - 1);
      if (next != index) onChanged(values[next]);
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 150) return;
        step(v > 0 ? 1 : -1);
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppTheme.stroke),
        ),
        child: Stack(
          children: [
            // The one capsule, gliding between slots.
            AnimatedAlign(
              duration: _slide,
              curve: _curve,
              alignment: Alignment(x, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: brandGradient(begin: Alignment.centerLeft, end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: [
                      BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: -6),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      child: GestureDetector(
                        onTap: () => onChanged(values[i]),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: _slide,
                            curve: _curve,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: i == index ? Colors.white : AppTheme.textMuted,
                            ),
                            child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

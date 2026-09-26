import 'package:flutter/material.dart';

/// Single source of truth for theming -- WP1 keeps this minimal
/// (Material 3 defaults with a seed color); the real design system lands
/// once product/design work is further along.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE85D75)),
      );
}

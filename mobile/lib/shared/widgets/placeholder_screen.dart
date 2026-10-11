import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'empty_state.dart';
import 'ui_kit.dart';

/// Shared placeholder for any feature not yet built out -- avoids six
/// near-identical "coming soon" widgets across the feature folders.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.featureName});

  final String featureName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(featureName)),
      body: AuroraBackground(
        intensity: 0.7,
        child: SafeArea(
          child: EmptyState(
            icon: Icons.auto_awesome_rounded,
            title: '$featureName is on its way',
            body: 'This part of Lolly lands in a later work package.',
          ),
        ),
      ),
    );
  }
}

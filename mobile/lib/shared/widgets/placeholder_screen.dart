import 'package:flutter/material.dart';

import 'empty_state.dart';

/// Shared placeholder for any feature not yet built out -- avoids six
/// near-identical "coming soon" widgets across the feature folders.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.featureName});

  final String featureName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(featureName)),
      body: EmptyState(
        icon: Icons.auto_awesome_rounded,
        title: '$featureName is on its way',
        body: 'This part of Lolly lands in a later work package.',
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Shared placeholder for any feature not yet built out -- avoids six
/// near-identical "coming soon" widgets across the feature folders.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.featureName});

  final String featureName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(featureName)),
      body: Center(child: Text('$featureName is coming in a later work package.')),
    );
  }
}

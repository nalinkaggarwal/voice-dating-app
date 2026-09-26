import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/application/auth_state.dart';

/// WP1 shell: signup succeeds and lands here. Real onboarding (basic
/// info -> preferences -> intent -> voice recording -> AI review ->
/// photo, matching UserStatus's progression) is built out in a later
/// work package.
class OnboardingPlaceholderScreen extends StatelessWidget {
  const OnboardingPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Lolly.ai'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "You're in! Onboarding (basic info, preferences, voice recording) "
            'lands in the next work package.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

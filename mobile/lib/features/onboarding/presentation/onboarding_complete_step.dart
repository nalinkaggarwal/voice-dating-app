import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/application/auth_state.dart';

class OnboardingCompleteStep extends StatelessWidget {
  const OnboardingCompleteStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("You're all set!"),
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
            'Your profile is ready. Discovery (matching on voice + preferences) '
            'lands in the next work package.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

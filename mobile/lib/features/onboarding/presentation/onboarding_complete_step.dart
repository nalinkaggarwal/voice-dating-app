import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/application/auth_state.dart';
import '../../discovery/presentation/discovery_home_screen.dart';

class OnboardingCompleteStep extends StatelessWidget {
  const OnboardingCompleteStep({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('You\'re all set!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Your profile is ready. Time to meet your first match.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => DiscoveryHomeScreen(currentUserId: currentUserId)),
                  );
                },
                child: const Text('Start discovering'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../reveal/presentation/reveal_screen.dart';

/// Mutual-match confirmation, shown right after a decide() call flips a
/// Connection to MUTUAL_INTEREST. Still no name or photo here -- same
/// "hear before you see" rule that governs the discovery card itself --
/// but WP4 wires the CTA forward into Mutual Reveal (name/photo) and then
/// Live Snap (a live video check) rather than just dismissing.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key, required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite, size: 72, color: Colors.pinkAccent),
              const SizedBox(height: 16),
              Text('You matched!', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                'You\'re both interested. See who it is next.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RevealScreen(connectionId: connectionId, currentUserId: currentUserId),
                  ),
                ),
                child: const Text('See your match'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Minimal mutual-match confirmation, shown right after a decide() call
/// flips a Connection to MUTUAL_INTEREST. Deliberately thin per the
/// brief -- the full mutual-reveal (seeing who it was) / Live Snap / chat
/// experience is WP4, not this one. No name or photo here either, same
/// "hear before you see" rule that governs the discovery card itself --
/// the backend doesn't send candidate identity to the client at all yet,
/// so there is nothing this screen could show even if it wanted to.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

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
                'You\'re both interested. Their full reveal comes later.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Discovery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

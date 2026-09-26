import 'package:flutter/material.dart';

/// Minimal mutual-match confirmation, shown right after a decide() call
/// flips a Connection to MUTUAL_INTEREST. Deliberately thin per the
/// brief -- the full mutual-reveal / Live Snap / chat experience is WP4,
/// not this one; this screen's only job is to tell the user it happened
/// and send them back to Discovery.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key, this.matchedDisplayName});

  final String? matchedDisplayName;

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
              Text(
                matchedDisplayName != null
                    ? 'You and $matchedDisplayName are both interested.'
                    : 'You\'re both interested in each other.',
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

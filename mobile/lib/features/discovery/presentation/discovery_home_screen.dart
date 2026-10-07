import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/voice_clip_player.dart';
import '../../auth/application/auth_state.dart';
import '../../matches/presentation/match_screen.dart';
import '../../messaging/presentation/conversations_list_screen.dart';
import '../application/discovery_state.dart';
import '../domain/discovery_entry.dart';

/// Entry point into WP3 discovery -- shows today's ONE curated candidate
/// (or more than one, for a tier with dailyCandidateLimit > 1; see
/// DiscoveryConfig on the backend). Deliberately not a swipe feed: no
/// stack of cards, no browsing ahead -- just the next undecided entry,
/// same shape as the backend's queue.
class DiscoveryHomeScreen extends StatelessWidget {
  const DiscoveryHomeScreen({super.key, required this.currentUserId});

  /// Needed to tell "my message" from "their message" in a thread --
  /// threaded down from main.dart's single already-fetched User rather
  /// than each messaging screen re-fetching it independently.
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DiscoveryState()..loadToday(),
      child: _DiscoveryBody(currentUserId: currentUserId),
    );
  }
}

class _DiscoveryBody extends StatelessWidget {
  const _DiscoveryBody({required this.currentUserId});

  final String currentUserId;

  Future<void> _handleDecision(
    BuildContext context,
    DiscoveryState state,
    DiscoveryDecision decision,
  ) async {
    final result = await state.decide(decision);
    if (result.matched && result.connectionId != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MatchScreen(connectionId: result.connectionId!, currentUserId: currentUserId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DiscoveryState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Messages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ConversationsListScreen(currentUserId: currentUserId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoveryState state) {
    if (state.isLoading && state.currentEntry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.currentEntry == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(state.errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: state.loadToday, child: const Text('Try again')),
          ],
        ),
      );
    }

    final entry = state.currentEntry;
    if (entry == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 48),
            SizedBox(height: 16),
            Text(
              'You\'re all caught up for today. Check back tomorrow for your next match.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _CandidateCard(
      entry: entry,
      isDeciding: state.isLoading,
      errorMessage: state.errorMessage,
      onPass: () => _handleDecision(context, state, DiscoveryDecision.pass),
      onInterested: () => _handleDecision(context, state, DiscoveryDecision.interested),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.entry,
    required this.isDeciding,
    required this.errorMessage,
    required this.onPass,
    required this.onInterested,
  });

  final DiscoveryEntry entry;
  final bool isDeciding;
  final String? errorMessage;
  final VoidCallback onPass;
  final VoidCallback onInterested;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // No photo, no name -- deliberately. "Hear before you see" is the
        // whole premise; a candidate's identity is never shown before a
        // decision (see DiscoveryEntry's own docstring). This silhouette
        // is a placeholder for "someone new", not a preview of anyone.
        const CircleAvatar(radius: 72, child: Icon(Icons.person, size: 64)),
        const SizedBox(height: 24),
        if (entry.voiceClipUrl != null)
          // Keyed on the entry -- without this, advancing to the next
          // candidate would reuse the previous VoiceClipPlayer's State
          // (same widget position in the tree), potentially leaving a
          // stale "playing" indicator or a still-running player from the
          // PREVIOUS candidate's clip.
          VoiceClipPlayer(key: ValueKey(entry.id), source: UrlSource(entry.voiceClipUrl!))
        else
          const Text('No voice intro available yet.', style: TextStyle(fontStyle: FontStyle.italic)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(entry.reasonText, textAlign: TextAlign.center),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton.icon(
              onPressed: isDeciding ? null : onPass,
              icon: const Icon(Icons.close),
              label: const Text('Pass'),
            ),
            FilledButton.icon(
              onPressed: isDeciding ? null : onInterested,
              icon: const Icon(Icons.favorite),
              label: const Text('Interested'),
            ),
          ],
        ),
      ],
    );
  }
}

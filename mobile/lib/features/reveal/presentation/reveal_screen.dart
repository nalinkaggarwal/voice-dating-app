import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../live_snap/presentation/live_snap_call_screen.dart';
import '../../trust_safety/domain/report_reason.dart';
import '../../trust_safety/presentation/trust_safety_actions.dart';
import '../application/reveal_state.dart';
import '../domain/reveal_profile.dart';

/// Mutual Reveal -- the matched user's name/photo, shown for the first
/// time now that there's a real mutual match. Sits between the "You
/// matched!" screen and the Live Snap call: seeing a photo first lets
/// someone back out before committing to a live call, matching the
/// product's own pipeline (... -> Mutual Reveal -> Live Snap -> ...).
class RevealScreen extends StatelessWidget {
  const RevealScreen({super.key, required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RevealState()..load(connectionId),
      child: _RevealBody(connectionId: connectionId, currentUserId: currentUserId),
    );
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  Future<void> _decline(BuildContext context, RevealState state) async {
    final declined = await state.decline(connectionId);
    if (declined && context.mounted) {
      // Back to Discovery directly -- no reason to pass back through the
      // "You matched!" screen for a match just declined.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _startLiveSnap(BuildContext context, String otherUserId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveSnapCallScreen(
          connectionId: connectionId,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
        ),
      ),
    );
  }

  Future<void> _handleBlock(BuildContext context, RevealProfile profile) async {
    final blocked = await confirmAndBlockUser(context, userId: profile.userId);
    if (blocked && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RevealState>();
    final profile = state.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your match'),
        actions: profile == null
            ? null
            : [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'report') {
                      showReportDialog(context, reportedUserId: profile.userId, reportContext: ReportContext.profile);
                    } else if (value == 'block') {
                      _handleBlock(context, profile);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'report', child: Text('Report')),
                    PopupMenuItem(value: 'block', child: Text('Block')),
                  ],
                ),
              ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RevealState state) {
    if (state.isLoading && state.profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(state.errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => state.load(connectionId),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final profile = state.profile;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 72,
          backgroundImage: profile?.photoUrl != null ? NetworkImage(profile!.photoUrl!) : null,
          child: profile?.photoUrl == null ? const Icon(Icons.person, size: 64) : null,
        ),
        const SizedBox(height: 16),
        Text(
          profile?.displayName ?? 'Your match',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Next: a quick live video check with each other before you unlock chat.',
          textAlign: TextAlign.center,
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton(
              onPressed: state.isLoading ? null : () => _decline(context, state),
              child: const Text('Not interested'),
            ),
            FilledButton(
              onPressed: state.isLoading || profile == null ? null : () => _startLiveSnap(context, profile.userId),
              child: const Text('Start Live Snap'),
            ),
          ],
        ),
      ],
    );
  }
}

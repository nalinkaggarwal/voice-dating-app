import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/conversations_state.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import 'message_thread_screen.dart';

/// One conversation per AUTHENTICATED_MATCH/ACTIVE Connection this user is
/// part of. No live updates here (REST-only, refresh on pull/return) --
/// the open thread screen is where live delivery matters; this list is
/// just "what do I have," refreshed when you look at it.
class ConversationsListScreen extends StatelessWidget {
  const ConversationsListScreen({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConversationsState()..load(),
      child: _ConversationsBody(currentUserId: currentUserId),
    );
  }
}

class _ConversationsBody extends StatelessWidget {
  const _ConversationsBody({required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConversationsState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: state.load,
        child: _buildBody(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ConversationsState state) {
    if (state.isLoading && state.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.conversations.isEmpty) {
      return _scrollable(
        EmptyState(
          icon: Icons.wifi_off_rounded,
          title: "Couldn't load your messages",
          body: state.errorMessage,
          action: OutlinedButton(onPressed: state.load, child: const Text('Try again')),
        ),
      );
    }

    if (state.conversations.isEmpty) {
      return _scrollable(
        const EmptyState(
          icon: Icons.forum_outlined,
          title: 'No conversations yet',
          body: 'A chat opens once you and a match confirm each other on Live Snap.',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: state.conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _ConversationTile(
        conversation: state.conversations[index],
        currentUserId: currentUserId,
      ),
    );
  }

  // RefreshIndicator needs a scrollable child even for the empty states.
  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight), child: child),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.currentUserId});

  final Conversation conversation;
  final String currentUserId;

  String _previewText() {
    final last = conversation.lastMessage;
    if (last == null) return 'Say hello!';
    return last.type == MessageType.voice ? 'Voice message' : (last.textContent ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isVoice = conversation.lastMessage?.type == MessageType.voice;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ListTile(
        leading: _Avatar(photoUrl: conversation.photoUrl),
        title: Text(conversation.displayName ?? 'Your match', style: theme.textTheme.titleMedium),
        subtitle: Row(
          children: [
            if (isVoice) ...[
              Icon(Icons.graphic_eq_rounded, size: 16, color: scheme.tertiary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                _previewText(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MessageThreadScreen(
              connectionId: conversation.connectionId,
              currentUserId: currentUserId,
              otherUserId: conversation.otherUserId,
              otherDisplayName: conversation.displayName,
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return CircleAvatar(radius: 26, backgroundImage: NetworkImage(photoUrl!));
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(gradient: brandGradient(), shape: BoxShape.circle),
      child: const Icon(Icons.person_rounded, color: Colors.white),
    );
  }
}

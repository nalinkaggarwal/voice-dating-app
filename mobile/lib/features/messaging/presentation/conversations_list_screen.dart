import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(state.errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: state.load, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (state.conversations.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: Text('No conversations yet -- they start once you and a match confirm Live Snap.'),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: state.conversations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _ConversationTile(
        conversation: state.conversations[index],
        currentUserId: currentUserId,
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
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: conversation.photoUrl != null ? NetworkImage(conversation.photoUrl!) : null,
        child: conversation.photoUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(conversation.displayName ?? 'Your match'),
      subtitle: Text(_previewText(), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }
}

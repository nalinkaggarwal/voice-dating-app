import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/error/app_exception.dart';
import 'package:lolly/features/messaging/application/conversations_state.dart';
import 'package:lolly/features/messaging/data/messaging_repository.dart';
import 'package:lolly/features/messaging/domain/conversation.dart';

class _FakeRepository extends MessagingRepository {
  _FakeRepository({this.conversations = const [], this.error});

  final List<Conversation> conversations;
  final Object? error;

  @override
  Future<List<Conversation>> listConversations() async {
    if (error != null) throw error!;
    return conversations;
  }
}

void main() {
  group('ConversationsState.load', () {
    test('populates conversations on success', () async {
      const conversation = Conversation(connectionId: 'conn-1', displayName: 'Jordan', photoUrl: null, lastMessage: null);
      final state = ConversationsState(repository: _FakeRepository(conversations: const [conversation]));

      await state.load();

      expect(state.isLoading, isFalse);
      expect(state.conversations, [conversation]);
      expect(state.errorMessage, isNull);
    });

    test('surfaces the error message on failure', () async {
      final state = ConversationsState(repository: _FakeRepository(error: const AppException('Network error')));

      await state.load();

      expect(state.errorMessage, 'Network error');
      expect(state.conversations, isEmpty);
    });
  });
}

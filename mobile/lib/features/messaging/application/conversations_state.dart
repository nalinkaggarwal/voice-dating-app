import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../data/messaging_repository.dart';
import '../domain/conversation.dart';

class ConversationsState extends ChangeNotifier {
  ConversationsState({MessagingRepository? repository}) : _repository = repository ?? MessagingRepository();

  final MessagingRepository _repository;

  bool isLoading = true;
  String? errorMessage;
  List<Conversation> conversations = [];

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      conversations = await _repository.listConversations();
    } on AppException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

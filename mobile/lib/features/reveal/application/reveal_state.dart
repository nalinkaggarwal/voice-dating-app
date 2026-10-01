import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../data/reveal_repository.dart';
import '../domain/reveal_profile.dart';

class RevealState extends ChangeNotifier {
  RevealState({RevealRepository? repository}) : _repository = repository ?? RevealRepository();

  final RevealRepository _repository;

  bool isLoading = true;
  String? errorMessage;
  RevealProfile? profile;

  Future<void> load(String connectionId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      profile = await _repository.getReveal(connectionId);
    } on AppException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Returns whether the decline actually went through -- the
  /// presentation layer only navigates away on success, leaving
  /// errorMessage visible (with a retry) otherwise.
  Future<bool> decline(String connectionId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _repository.decline(connectionId);
      return true;
    } on AppException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

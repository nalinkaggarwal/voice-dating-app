import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../data/discovery_repository.dart';
import '../domain/discovery_entry.dart';

class DiscoveryState extends ChangeNotifier {
  DiscoveryState({DiscoveryRepository? repository})
      : _repository = repository ?? DiscoveryRepository();

  final DiscoveryRepository _repository;

  bool isLoading = true;
  String? errorMessage;
  List<DiscoveryEntry> _queue = [];

  /// Always the next undecided entry to show -- null once the queue is
  /// empty (nothing left to decide today).
  DiscoveryEntry? get currentEntry => _queue.isEmpty ? null : _queue.first;

  Future<void> loadToday() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      _queue = await _repository.getToday();
    } on AppException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Decides on the current entry and removes it from the local queue.
  /// Returns whether this decision resulted in a mutual match -- the
  /// presentation layer uses this to decide whether to show the "You
  /// matched!" screen. Returns false (and leaves the queue untouched) on
  /// a network/API failure -- errorMessage carries the reason.
  Future<bool> decide(DiscoveryDecision decision) async {
    final entry = currentEntry;
    if (entry == null) return false;

    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _repository.decide(entry.id, decision);
      _queue = _queue.where((e) => e.id != entry.id).toList();
      return result.matched;
    } on AppException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

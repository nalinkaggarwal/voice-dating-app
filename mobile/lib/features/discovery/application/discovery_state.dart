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
  /// Returns the full result (matched + connectionId) -- the presentation
  /// layer uses `matched` to decide whether to show the "You matched!"
  /// screen, and `connectionId` to address it for Reveal/Live Snap past
  /// that point. Returns matched:false/connectionId:null on a network/API
  /// failure, leaving the queue untouched -- errorMessage carries the
  /// reason.
  Future<DiscoveryDecisionResult> decide(DiscoveryDecision decision) async {
    final entry = currentEntry;
    if (entry == null) return const DiscoveryDecisionResult(matched: false);

    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _repository.decide(entry.id, decision);
      _queue = _queue.where((e) => e.id != entry.id).toList();
      return result;
    } on AppException catch (e) {
      errorMessage = e.message;
      return const DiscoveryDecisionResult(matched: false);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

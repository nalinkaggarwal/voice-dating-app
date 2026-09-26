import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../../../shared/models/user.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_step.dart';
import '../domain/voice_answer.dart';

class OnboardingState extends ChangeNotifier {
  OnboardingState({OnboardingRepository? repository})
      : _repository = repository ?? OnboardingRepository();

  final OnboardingRepository _repository;

  OnboardingStep currentStep = OnboardingStep.basicInfo;
  bool isLoading = false;
  String? errorMessage;

  /// Resumes at the right step for a returning user instead of always
  /// restarting at basicInfo. One real gap: if the backend status is
  /// VOICE_RECORDED (recording uploaded, but the app was killed before
  /// the AI review was finalized), there's no "fetch my most recent
  /// voice answer" endpoint to resume the review screen with -- falls
  /// back to re-recording rather than resuming a review with no known
  /// voiceAnswerId. Documented limitation, not a silent bug.
  void resumeFrom(UserStatus status) {
    currentStep = switch (status) {
      UserStatus.accountCreated => OnboardingStep.basicInfo,
      UserStatus.basicInfoDone => OnboardingStep.preferences,
      UserStatus.preferencesDone => OnboardingStep.intent,
      UserStatus.intentDone => OnboardingStep.voiceRecording,
      UserStatus.voiceRecorded => OnboardingStep.voiceRecording,
      UserStatus.aiReviewDone => OnboardingStep.photo,
      UserStatus.photoUploaded => OnboardingStep.complete,
      UserStatus.active => OnboardingStep.complete,
    };
    notifyListeners();
  }

  VoiceAnswer? voiceAnswer;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<bool> _run(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AppException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitBasicInfo({required String displayName, String? geohash}) {
    return _run(() async {
      await _repository.submitBasicInfo(displayName: displayName, geohash: geohash);
      currentStep = OnboardingStep.preferences;
    });
  }

  Future<bool> submitPreferences({
    required List<String> genderInterest,
    int? ageMin,
    int? ageMax,
    int? maxDistanceKm,
  }) {
    return _run(() async {
      await _repository.submitPreferences(
        genderInterest: genderInterest,
        ageMin: ageMin,
        ageMax: ageMax,
        maxDistanceKm: maxDistanceKm,
      );
      currentStep = OnboardingStep.intent;
    });
  }

  Future<bool> submitIntent(String relationshipIntent) {
    return _run(() async {
      await _repository.submitIntent(relationshipIntent);
      currentStep = OnboardingStep.voiceRecording;
    });
  }

  Future<bool> uploadVoiceRecording(Uint8List bytes, {String contentType = 'audio/mp4'}) {
    return _run(() async {
      final target = await _repository.requestVoiceUploadUrl(contentType);
      await _repository.uploadToSignedUrl(target.uploadUrl, bytes, contentType);
      voiceAnswer = await _repository.completeVoiceUpload(target.key);
      currentStep = OnboardingStep.aiReview;
      _startPollingVoiceAnswer();
    });
  }

  /// Transcription + extraction run asynchronously on the backend (BullMQ
  /// workers) -- polls every 3s until the draft is ready (or it fails)
  /// rather than the client blocking on a single long request. Stops
  /// itself once there's nothing left to wait for.
  void _startPollingVoiceAnswer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final id = voiceAnswer?.id;
      if (id == null) return;
      try {
        final updated = await _repository.getVoiceAnswer(id);
        voiceAnswer = updated;
        notifyListeners();
        if (updated.status == VoiceAnswerStatus.draftReady ||
            updated.status == VoiceAnswerStatus.failed) {
          _pollTimer?.cancel();
        }
      } catch (_) {
        // Transient network blip -- next tick retries; don't surface a
        // scary error for what's likely a momentary connectivity gap.
      }
    });
  }

  Future<bool> editClaim(String claimId, String text) {
    return _run(() async {
      await _repository.editClaim(claimId, text);
      await _refreshVoiceAnswer();
    });
  }

  Future<bool> approveClaim(String claimId) {
    return _run(() async {
      await _repository.approveClaim(claimId);
      await _refreshVoiceAnswer();
    });
  }

  Future<bool> discardClaim(String claimId) {
    return _run(() async {
      await _repository.discardClaim(claimId);
      await _refreshVoiceAnswer();
    });
  }

  Future<void> _refreshVoiceAnswer() async {
    final id = voiceAnswer?.id;
    if (id == null) return;
    voiceAnswer = await _repository.getVoiceAnswer(id);
  }

  Future<bool> finalizeReview() {
    return _run(() async {
      final id = voiceAnswer?.id;
      if (id == null) throw const AppException('No voice recording to finalize');
      await _repository.finalizeVoiceReview(id);
      currentStep = OnboardingStep.photo;
    });
  }

  Future<bool> uploadPhoto(Uint8List bytes, {String contentType = 'image/jpeg'}) {
    return _run(() async {
      final target = await _repository.requestPhotoUploadUrl(contentType);
      await _repository.uploadToSignedUrl(target.uploadUrl, bytes, contentType);
      await _repository.completePhotoUpload(target.key);
      currentStep = OnboardingStep.complete;
    });
  }
}

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/error/app_exception.dart';
import '../../../shared/api/api_client.dart';
import '../domain/voice_answer.dart';

class UploadTarget {
  const UploadTarget(this.uploadUrl, this.key);
  final String uploadUrl;
  final String key;
}

class OnboardingRepository {
  OnboardingRepository({ApiClient? apiClient, http.Client? rawHttpClient})
      : _api = apiClient ?? ApiClient(),
        _rawHttp = rawHttpClient ?? http.Client();

  final ApiClient _api;
  // Direct-to-S3 PUTs bypass ApiClient entirely -- a signed URL carries
  // its own auth in the query string, and the body is raw bytes, not
  // JSON, so none of ApiClient's usual behavior (Bearer header, 401
  // refresh-and-retry, JSON encode/decode) applies.
  final http.Client _rawHttp;

  Future<void> submitBasicInfo({required String displayName, String? geohash}) {
    return _api.post(
      '/profile/basic-info',
      authenticated: true,
      body: {'displayName': displayName, if (geohash != null) 'geohash': geohash},
    );
  }

  Future<void> submitPreferences({
    required List<String> genderInterest,
    int? ageMin,
    int? ageMax,
    int? maxDistanceKm,
  }) {
    return _api.post(
      '/profile/preferences',
      authenticated: true,
      body: {
        'genderInterest': genderInterest,
        if (ageMin != null) 'ageMin': ageMin,
        if (ageMax != null) 'ageMax': ageMax,
        if (maxDistanceKm != null) 'maxDistanceKm': maxDistanceKm,
      },
    );
  }

  Future<void> submitIntent(String relationshipIntent) {
    return _api.post(
      '/profile/intent',
      authenticated: true,
      body: {'relationshipIntent': relationshipIntent},
    );
  }

  Future<UploadTarget> requestVoiceUploadUrl(String contentType) async {
    final response = await _api.post(
      '/ai-profile/voice/upload-url',
      authenticated: true,
      body: {'contentType': contentType},
    );
    return UploadTarget(response['uploadUrl'] as String, response['key'] as String);
  }

  Future<VoiceAnswer> completeVoiceUpload(String key) async {
    final response = await _api.post(
      '/ai-profile/voice/complete',
      authenticated: true,
      body: {'key': key},
    );
    return VoiceAnswer.fromJson(response);
  }

  Future<VoiceAnswer> getVoiceAnswer(String voiceAnswerId) async {
    final response = await _api.get('/ai-profile/voice/$voiceAnswerId', authenticated: true);
    return VoiceAnswer.fromJson(response);
  }

  /// Lets a resumed session find its voice answer without already knowing
  /// its id -- see OnboardingState.resumeFrom for why that matters.
  Future<VoiceAnswer> getLatestVoiceAnswer() async {
    final response = await _api.get('/ai-profile/voice/latest', authenticated: true);
    return VoiceAnswer.fromJson(response);
  }

  Future<void> editClaim(String claimId, String text) {
    return _api.post('/ai-profile/claims/$claimId/edit', authenticated: true, body: {'text': text});
  }

  Future<void> approveClaim(String claimId) {
    return _api.post('/ai-profile/claims/$claimId/approve', authenticated: true);
  }

  Future<void> discardClaim(String claimId) {
    return _api.post('/ai-profile/claims/$claimId/discard', authenticated: true);
  }

  Future<void> finalizeVoiceReview(String voiceAnswerId) {
    return _api.post('/ai-profile/voice/$voiceAnswerId/finalize', authenticated: true);
  }

  Future<UploadTarget> requestPhotoUploadUrl(String contentType) async {
    final response = await _api.post(
      '/profile/photo/upload-url',
      authenticated: true,
      body: {'contentType': contentType},
    );
    return UploadTarget(response['uploadUrl'] as String, response['key'] as String);
  }

  Future<void> completePhotoUpload(String key) {
    return _api.post('/profile/photo/complete', authenticated: true, body: {'key': key});
  }

  /// Shared by both voice and photo uploads -- a raw PUT of the file
  /// bytes straight to the signed URL, no auth header (the signature IS
  /// the auth) and no JSON.
  Future<void> uploadToSignedUrl(String uploadUrl, Uint8List bytes, String contentType) async {
    final response = await _rawHttp.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('Upload failed', statusCode: response.statusCode);
    }
  }
}

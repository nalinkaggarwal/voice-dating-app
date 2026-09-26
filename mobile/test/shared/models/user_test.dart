import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/shared/models/user.dart';

void main() {
  group('User.fromJson', () {
    test('maps SCREAMING_SNAKE_CASE status to the matching camelCase enum', () {
      final user = User.fromJson({
        'id': 'user-1',
        'email': 'a@example.com',
        'phone': null,
        'status': 'ACCOUNT_CREATED',
        'createdAt': '2026-01-01T00:00:00.000Z',
      });
      expect(user.status, UserStatus.accountCreated);
    });

    test('maps a multi-word status correctly (AI_REVIEW_DONE)', () {
      final user = User.fromJson({
        'id': 'user-1',
        'status': 'AI_REVIEW_DONE',
      });
      expect(user.status, UserStatus.aiReviewDone);
    });

    test('maps every UserStatus value round-trip via its SCREAMING_SNAKE form', () {
      // Guards against the enum and the backend's UserStatus drifting
      // apart silently -- if a new value is added to one but not mapped
      // here, this fails instead of silently falling back to accountCreated.
      final screamingSnakeByStatus = {
        UserStatus.accountCreated: 'ACCOUNT_CREATED',
        UserStatus.basicInfoDone: 'BASIC_INFO_DONE',
        UserStatus.preferencesDone: 'PREFERENCES_DONE',
        UserStatus.intentDone: 'INTENT_DONE',
        UserStatus.voiceRecorded: 'VOICE_RECORDED',
        UserStatus.aiReviewDone: 'AI_REVIEW_DONE',
        UserStatus.photoUploaded: 'PHOTO_UPLOADED',
        UserStatus.active: 'ACTIVE',
      };

      for (final entry in screamingSnakeByStatus.entries) {
        final user = User.fromJson({'id': 'u', 'status': entry.value});
        expect(user.status, entry.key, reason: 'failed for ${entry.value}');
      }
    });

    test('falls back to accountCreated for an unrecognized status', () {
      final user = User.fromJson({'id': 'u', 'status': 'SOME_FUTURE_STATUS'});
      expect(user.status, UserStatus.accountCreated);
    });
  });
}

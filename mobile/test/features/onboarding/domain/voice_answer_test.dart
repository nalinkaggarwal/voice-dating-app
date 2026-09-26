import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/features/onboarding/domain/voice_answer.dart';

void main() {
  group('VoiceAnswer.fromJson', () {
    test('maps status and claims correctly', () {
      final voiceAnswer = VoiceAnswer.fromJson({
        'id': 'va-1',
        'status': 'DRAFT_READY',
        'claims': [
          {'id': 'c1', 'text': 'I love hiking.', 'approved': false, 'discarded': false},
          {'id': 'c2', 'text': 'I hate mornings.', 'approved': true, 'discarded': false},
        ],
      });

      expect(voiceAnswer.status, VoiceAnswerStatus.draftReady);
      expect(voiceAnswer.claims.length, 2);
      expect(voiceAnswer.claims[1].approved, true);
    });

    test('defaults to an empty claims list when the key is absent', () {
      final voiceAnswer = VoiceAnswer.fromJson({'id': 'va-1', 'status': 'UPLOADED'});
      expect(voiceAnswer.claims, isEmpty);
    });

    test('maps every backend status value', () {
      const expected = {
        'UPLOADED': VoiceAnswerStatus.uploaded,
        'TRANSCRIBING': VoiceAnswerStatus.transcribing,
        'TRANSCRIBED': VoiceAnswerStatus.transcribed,
        'EXTRACTING': VoiceAnswerStatus.extracting,
        'DRAFT_READY': VoiceAnswerStatus.draftReady,
        'USER_APPROVED': VoiceAnswerStatus.userApproved,
        'FAILED': VoiceAnswerStatus.failed,
      };
      for (final entry in expected.entries) {
        final voiceAnswer = VoiceAnswer.fromJson({'id': 'va-1', 'status': entry.key});
        expect(voiceAnswer.status, entry.value, reason: 'failed for ${entry.key}');
      }
    });

    test('carries failureReason through when present', () {
      final voiceAnswer = VoiceAnswer.fromJson({
        'id': 'va-1',
        'status': 'FAILED',
        'failureReason': 'vendor timeout',
      });
      expect(voiceAnswer.failureReason, 'vendor timeout');
    });
  });
}

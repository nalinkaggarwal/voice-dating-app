import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/features/trust_safety/domain/report_reason.dart';

void main() {
  group('ReportReason.wireValue', () {
    test('every value maps to its exact backend ReportReason enum string', () {
      expect(ReportReason.inappropriateContent.wireValue, 'INAPPROPRIATE_CONTENT');
      expect(ReportReason.harassment.wireValue, 'HARASSMENT');
      expect(ReportReason.fakeProfile.wireValue, 'FAKE_PROFILE');
      expect(ReportReason.safetyConcern.wireValue, 'SAFETY_CONCERN');
      expect(ReportReason.spam.wireValue, 'SPAM');
      expect(ReportReason.other.wireValue, 'OTHER');
    });
  });

  group('ReportContext.wireValue', () {
    test('every value maps to its exact backend ReportContext enum string', () {
      expect(ReportContext.profile.wireValue, 'PROFILE');
      expect(ReportContext.message.wireValue, 'MESSAGE');
      expect(ReportContext.liveSnap.wireValue, 'LIVE_SNAP');
      expect(ReportContext.connection.wireValue, 'CONNECTION');
    });
  });
}

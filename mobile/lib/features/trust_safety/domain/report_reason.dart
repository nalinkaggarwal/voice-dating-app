/// Mirrors backend ReportReason exactly -- see schema.prisma.
enum ReportReason {
  inappropriateContent,
  harassment,
  fakeProfile,
  safetyConcern,
  spam,
  other,
}

extension ReportReasonWire on ReportReason {
  String get wireValue => switch (this) {
        ReportReason.inappropriateContent => 'INAPPROPRIATE_CONTENT',
        ReportReason.harassment => 'HARASSMENT',
        ReportReason.fakeProfile => 'FAKE_PROFILE',
        ReportReason.safetyConcern => 'SAFETY_CONCERN',
        ReportReason.spam => 'SPAM',
        ReportReason.other => 'OTHER',
      };

  String get label => switch (this) {
        ReportReason.inappropriateContent => 'Inappropriate content',
        ReportReason.harassment => 'Harassment',
        ReportReason.fakeProfile => 'Fake profile',
        ReportReason.safetyConcern => 'Safety concern',
        ReportReason.spam => 'Spam',
        ReportReason.other => 'Other',
      };
}

/// Mirrors backend ReportContext exactly -- what surface a report was
/// filed from, per the spec's "report a profile, a message, or a Live
/// Snap session" requirement.
enum ReportContext {
  profile,
  message,
  liveSnap,
  connection,
}

extension ReportContextWire on ReportContext {
  String get wireValue => switch (this) {
        ReportContext.profile => 'PROFILE',
        ReportContext.message => 'MESSAGE',
        ReportContext.liveSnap => 'LIVE_SNAP',
        ReportContext.connection => 'CONNECTION',
      };
}

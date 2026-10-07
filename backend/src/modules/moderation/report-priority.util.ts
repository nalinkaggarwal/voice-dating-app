import type { ReportContext, ReportReason } from '@prisma/client';

// Pure so it's trivially unit-testable with no DB -- not stored on Report
// itself (see schema comment) so it can never drift out of sync with
// reason/context. A LIVE_SNAP-context report or a SAFETY_CONCERN reason
// outranks every other PENDING/IN_REVIEW report in the queue, per the
// spec's "priority levels" requirement.
export type ReportPriority = 'HIGH' | 'NORMAL';

export function reportPriority(report: { reason: ReportReason; context: ReportContext }): ReportPriority {
  if (report.context === 'LIVE_SNAP' || report.reason === 'SAFETY_CONCERN') {
    return 'HIGH';
  }
  return 'NORMAL';
}

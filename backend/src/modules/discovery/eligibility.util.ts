import type { ConnectionStatus, Gender, UserStatus } from '@prisma/client';
import { calculateAge } from '../identity/util/age.js';
import { geohashDistanceKm } from '../../shared/geo/geohash.util.js';

export interface EligibilityCandidate {
  userId: string;
  userStatus: UserStatus;
  dateOfBirth: Date;
  gender: Gender | null;
  genderInterest: string[];
  ageMin: number | null;
  ageMax: number | null;
  geohash: string | null;
  maxDistanceKm: number | null;
  relationshipIntent: string | null;
  /** Status of any EXISTING Connection row between the viewer and this
   * candidate, in either direction -- null if none exists yet. */
  existingConnectionStatus: ConnectionStatus | null;
}

export interface EligibilityResult {
  eligible: boolean;
  /** Every hard-filter reason this candidate failed, even past the
   * first -- useful for support/moderation questions ("why didn't X ever
   * see Y") without re-deriving the check by hand. Empty when eligible. */
  failureReasons: string[];
}

// Flutter's WP2 onboarding UI collects genderInterest as "MEN"/"WOMEN"/
// "NON_BINARY" (interested-IN, plural-ish), while a person's own gender
// (added this WP, Profile.gender) is the singular Gender enum ("MAN"/
// "WOMAN"/"NON_BINARY"). Normalizing here rather than changing WP2's
// already-shipped stored vocabulary or its enum type.
const INTEREST_TO_GENDER: Record<string, Gender> = {
  MEN: 'MAN', MAN: 'MAN',
  WOMEN: 'WOMAN', WOMAN: 'WOMAN',
  NON_BINARY: 'NON_BINARY',
};

function interestIncludesGender(genderInterest: string[], gender: Gender | null): boolean {
  if (!gender) return false;
  return genderInterest.some((raw) => INTEREST_TO_GENDER[raw.toUpperCase()] === gender);
}

function ageWithinWindow(age: number, min: number | null, max: number | null): boolean {
  if (min !== null && age < min) return false;
  if (max !== null && age > max) return false;
  return true;
}

/**
 * Pure hard-filter check for ONE (viewer, candidate) pair -- no DB access,
 * no side effects, so it's trivially unit-testable and independently
 * auditable from ranking. All checks run (not short-circuited) so
 * failureReasons reports every reason a pair was excluded, not just the
 * first one hit.
 *
 * relationshipIntent alignment is deliberately NOT a hard filter here --
 * see EligibilityService's docstring for why (flagged tradeoff, per the
 * brief's own instruction to use judgment and flag it). Confirmed as the
 * right call for now: with an early/sparse user base, a hard filter risks
 * collapsing eligible candidates to zero. It's scored as a soft ranking
 * signal instead (see ranking.util.ts). Revisit turning this into a hard
 * filter once the user base is large enough that doing so wouldn't zero
 * out candidates for most users.
 */
export function checkEligibility(
  viewer: EligibilityCandidate,
  candidate: EligibilityCandidate,
): EligibilityResult {
  const failureReasons: string[] = [];

  if (candidate.userStatus !== 'ACTIVE') {
    failureReasons.push('candidate is not fully onboarded (status != ACTIVE)');
  }

  if (candidate.existingConnectionStatus !== null) {
    failureReasons.push(
      `an existing connection already exists between these users (status=${candidate.existingConnectionStatus})`,
    );
  }

  const viewerAge = calculateAge(viewer.dateOfBirth);
  const candidateAge = calculateAge(candidate.dateOfBirth);

  if (!ageWithinWindow(candidateAge, viewer.ageMin, viewer.ageMax)) {
    failureReasons.push("candidate's age is outside the viewer's preferred age range");
  }
  if (!ageWithinWindow(viewerAge, candidate.ageMin, candidate.ageMax)) {
    failureReasons.push("viewer's age is outside the candidate's preferred age range");
  }

  if (!interestIncludesGender(viewer.genderInterest, candidate.gender)) {
    failureReasons.push("candidate's gender does not match the viewer's stated interest");
  }
  if (!interestIncludesGender(candidate.genderInterest, viewer.gender)) {
    failureReasons.push("viewer's gender does not match the candidate's stated interest");
  }

  const distanceKm = geohashDistanceKm(viewer.geohash, candidate.geohash);
  if (viewer.maxDistanceKm !== null) {
    if (distanceKm === null) {
      failureReasons.push('distance cannot be verified (missing geohash on one or both sides)');
    } else if (distanceKm > viewer.maxDistanceKm) {
      failureReasons.push(
        `candidate is ${distanceKm.toFixed(1)}km away, outside the viewer's ${viewer.maxDistanceKm}km max`,
      );
    }
  }

  return { eligible: failureReasons.length === 0, failureReasons };
}

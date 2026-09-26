import { checkEligibility, type EligibilityCandidate } from './eligibility.util.js';

function makeCandidate(overrides: Partial<EligibilityCandidate> = {}): EligibilityCandidate {
  return {
    userId: 'user-1',
    userStatus: 'ACTIVE',
    dateOfBirth: new Date('1995-01-01'), // ~31 as of 2026
    gender: 'WOMAN',
    genderInterest: ['MEN'],
    ageMin: 25,
    ageMax: 40,
    geohash: 'u4pruy', // somewhere in the Netherlands
    maxDistanceKm: 50,
    relationshipIntent: 'LONG_TERM',
    existingConnectionStatus: null,
    ...overrides,
  };
}

describe('checkEligibility', () => {
  it('is eligible when every hard filter passes (mutual, symmetric setup)', () => {
    const viewer = makeCandidate({
      userId: 'viewer',
      gender: 'MAN',
      genderInterest: ['WOMEN'],
      dateOfBirth: new Date('1993-06-01'),
    });
    const candidate = makeCandidate({
      userId: 'candidate',
      gender: 'WOMAN',
      genderInterest: ['MEN'],
      dateOfBirth: new Date('1995-01-01'),
      geohash: 'u4pruz', // very close to viewer's hash
    });

    const result = checkEligibility(viewer, candidate);
    expect(result.eligible).toBe(true);
    expect(result.failureReasons).toEqual([]);
  });

  it('rejects a candidate who is not ACTIVE', () => {
    const viewer = makeCandidate({ userId: 'viewer' });
    const candidate = makeCandidate({ userId: 'candidate', userStatus: 'AI_REVIEW_DONE' });
    const result = checkEligibility(viewer, candidate);
    expect(result.eligible).toBe(false);
    expect(result.failureReasons.join(' ')).toMatch(/not fully onboarded/);
  });

  describe('mutual age-window compatibility', () => {
    it('rejects when candidate is too young for the viewer\'s window', () => {
      const viewer = makeCandidate({ userId: 'viewer', ageMin: 30, ageMax: 40 });
      const candidate = makeCandidate({ userId: 'candidate', dateOfBirth: new Date('2005-01-01') }); // ~21
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/outside the viewer's preferred age range/);
    });

    it('rejects when the VIEWER is outside the CANDIDATE\'s window -- the reverse direction', () => {
      // Candidate only wants 20-25 year-olds; viewer (from makeCandidate) is ~31.
      const viewer = makeCandidate({ userId: 'viewer', dateOfBirth: new Date('1995-01-01') });
      const candidate = makeCandidate({ userId: 'candidate', ageMin: 20, ageMax: 25 });
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/outside the candidate's preferred age range/);
    });

    it('passes when both sides are unset (no age preference at all)', () => {
      const viewer = makeCandidate({
        userId: 'viewer',
        gender: 'MAN',
        genderInterest: ['WOMEN'],
        ageMin: null,
        ageMax: null,
      });
      const candidate = makeCandidate({ userId: 'candidate', ageMin: null, ageMax: null });
      expect(checkEligibility(viewer, candidate).eligible).toBe(true);
    });
  });

  describe('mutual gender-interest compatibility', () => {
    it('rejects one-directional interest (viewer wants candidate, candidate does not want viewer)', () => {
      const viewer = makeCandidate({ userId: 'viewer', gender: 'MAN', genderInterest: ['WOMEN'] });
      const candidate = makeCandidate({
        userId: 'candidate',
        gender: 'WOMAN',
        genderInterest: ['WOMEN'], // doesn't want men
      });
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/viewer's gender does not match/);
    });

    it('accepts the plural "MEN"/"WOMEN" vocabulary against the singular Gender enum', () => {
      const viewer = makeCandidate({ userId: 'viewer', gender: 'MAN', genderInterest: ['WOMEN'] });
      const candidate = makeCandidate({ userId: 'candidate', gender: 'WOMAN', genderInterest: ['MEN'] });
      expect(checkEligibility(viewer, candidate).eligible).toBe(true);
    });

    it('rejects when the candidate has no gender set at all (can\'t verify mutual compatibility)', () => {
      const viewer = makeCandidate({ userId: 'viewer', genderInterest: ['WOMEN'] });
      const candidate = makeCandidate({ userId: 'candidate', gender: null });
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
    });
  });

  describe('distance (geohash-based, never exact lat/long)', () => {
    it('rejects a candidate outside maxDistanceKm', () => {
      const viewer = makeCandidate({ userId: 'viewer', geohash: 'u4pruy', maxDistanceKm: 10 });
      const candidate = makeCandidate({ userId: 'candidate', geohash: '9q8yyk' }); // California -- very far from NL
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/outside the viewer's/);
    });

    it('accepts a nearby candidate within maxDistanceKm', () => {
      const viewer = makeCandidate({
        userId: 'viewer',
        gender: 'MAN',
        genderInterest: ['WOMEN'],
        geohash: 'u4pruy',
        maxDistanceKm: 50,
      });
      const candidate = makeCandidate({ userId: 'candidate', geohash: 'u4pruz' });
      expect(checkEligibility(viewer, candidate).eligible).toBe(true);
    });

    it('rejects when distance cannot be verified (missing geohash) but a max distance is set', () => {
      const viewer = makeCandidate({ userId: 'viewer', geohash: null, maxDistanceKm: 50 });
      const candidate = makeCandidate({ userId: 'candidate' });
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/cannot be verified/);
    });

    it('passes regardless of distance when the viewer has no maxDistanceKm set', () => {
      const viewer = makeCandidate({
        userId: 'viewer',
        gender: 'MAN',
        genderInterest: ['WOMEN'],
        geohash: 'u4pruy',
        maxDistanceKm: null,
      });
      const candidate = makeCandidate({ userId: 'candidate', geohash: '9q8yyk' });
      expect(checkEligibility(viewer, candidate).eligible).toBe(true);
    });
  });

  describe('no-resurface rules', () => {
    it('rejects a candidate with an existing SUGGESTED connection', () => {
      const viewer = makeCandidate({ userId: 'viewer' });
      const candidate = makeCandidate({ userId: 'candidate', existingConnectionStatus: 'SUGGESTED' });
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/existing connection/);
    });

    it('rejects a candidate with an existing MUTUAL_INTEREST connection', () => {
      const viewer = makeCandidate({ userId: 'viewer' });
      const candidate = makeCandidate({ userId: 'candidate', existingConnectionStatus: 'MUTUAL_INTEREST' });
      expect(checkEligibility(viewer, candidate).eligible).toBe(false);
    });

    it('rejects a candidate with an existing ACTIVE connection', () => {
      const viewer = makeCandidate({ userId: 'viewer' });
      const candidate = makeCandidate({ userId: 'candidate', existingConnectionStatus: 'ACTIVE' });
      expect(checkEligibility(viewer, candidate).eligible).toBe(false);
    });

    it('rejects a BLOCKED connection -- the same "no existing connection in any status" rule covers blocking', () => {
      const viewer = makeCandidate({ userId: 'viewer' });
      const candidate = makeCandidate({ userId: 'candidate', existingConnectionStatus: 'BLOCKED' });
      const result = checkEligibility(viewer, candidate);
      expect(result.eligible).toBe(false);
      expect(result.failureReasons.join(' ')).toMatch(/BLOCKED/);
    });

    it('rejects even a CLOSED connection -- never resurface a past pairing at all', () => {
      const viewer = makeCandidate({ userId: 'viewer' });
      const candidate = makeCandidate({ userId: 'candidate', existingConnectionStatus: 'CLOSED' });
      expect(checkEligibility(viewer, candidate).eligible).toBe(false);
    });
  });

  it('reports every failing reason at once, not just the first (for support/moderation auditing)', () => {
    const viewer = makeCandidate({ userId: 'viewer', ageMin: 30, ageMax: 40, maxDistanceKm: 5 });
    const candidate = makeCandidate({
      userId: 'candidate',
      userStatus: 'AI_REVIEW_DONE', // fails status
      dateOfBirth: new Date('2005-01-01'), // fails age
      geohash: '9q8yyk', // fails distance
    });
    const result = checkEligibility(viewer, candidate);
    expect(result.eligible).toBe(false);
    expect(result.failureReasons.length).toBeGreaterThanOrEqual(3);
  });
});

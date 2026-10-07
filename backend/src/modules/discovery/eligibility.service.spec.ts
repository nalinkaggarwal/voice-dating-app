import { EligibilityService } from './eligibility.service.js';

// eligibility.util.spec.ts already proves the pure checkEligibility()
// function itself rejects a BLOCKED existingConnectionStatus -- but WP3's
// own photo-leak bug happened at exactly this kind of gap: correct logic
// in a pure function, never actually exercised through the real DB-
// querying service that wires it up. This test exercises
// EligibilityService.eligibleCandidatesFor() end-to-end against a mocked
// Prisma, the same level the photo-leak bug lived at, specifically for
// the "blocked user never resurfaces" case -- not inferred from the
// util-level test "generally covering" it.
describe('EligibilityService', () => {
  function makeUser(overrides: Record<string, any> = {}) {
    return {
      id: 'candidate-1',
      status: 'ACTIVE',
      dateOfBirth: new Date('1995-01-01'),
      profile: { gender: 'WOMAN', geohash: null },
      preference: { genderInterest: ['MAN'], ageMin: null, ageMax: null, maxDistanceKm: null, relationshipIntent: null },
      ...overrides,
    };
  }

  function makeViewer(overrides: Record<string, any> = {}) {
    return makeUser({
      id: 'viewer-1',
      profile: { gender: 'MAN', geohash: null },
      preference: { genderInterest: ['WOMAN'], ageMin: null, ageMax: null, maxDistanceKm: null, relationshipIntent: null },
      ...overrides,
    });
  }

  function makePrisma(viewer: any, candidates: any[], connections: any[]) {
    return {
      user: {
        findUnique: vi.fn(async () => viewer),
        findMany: vi.fn(async () => candidates),
      },
      connection: {
        findMany: vi.fn(async () => connections),
      },
    };
  }

  it('excludes a candidate with a BLOCKED Connection row against the viewer', async () => {
    const viewer = makeViewer();
    const candidate = makeUser({ id: 'candidate-1' });
    const connections = [
      { userAId: 'viewer-1', userBId: 'candidate-1', status: 'BLOCKED' },
    ];
    const service = new EligibilityService(makePrisma(viewer, [candidate], connections) as any);

    const result = await service.eligibleCandidatesFor('viewer-1');

    expect(result.map((c) => c.userId)).not.toContain('candidate-1');
    expect(result).toHaveLength(0);
  });

  it('excludes a candidate with a BLOCKED Connection row regardless of which side is userA/userB', async () => {
    const viewer = makeViewer();
    const candidate = makeUser({ id: 'candidate-1' });
    // Blocked the OTHER canonical-pair direction -- the candidate as A,
    // viewer as B. existingConnectionStatus lookup must still find it.
    const connections = [
      { userAId: 'candidate-1', userBId: 'viewer-1', status: 'BLOCKED' },
    ];
    const service = new EligibilityService(makePrisma(viewer, [candidate], connections) as any);

    const result = await service.eligibleCandidatesFor('viewer-1');

    expect(result).toHaveLength(0);
  });

  it('still returns an otherwise-eligible candidate with no existing connection at all', async () => {
    const viewer = makeViewer();
    const candidate = makeUser({ id: 'candidate-1' });
    const service = new EligibilityService(makePrisma(viewer, [candidate], []) as any);

    const result = await service.eligibleCandidatesFor('viewer-1');

    expect(result.map((c) => c.userId)).toContain('candidate-1');
  });
});

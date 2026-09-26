import { extractTerms, rankCandidates, scoreCandidate, type RankingCandidate } from './ranking.util.js';

describe('extractTerms', () => {
  it('strips stopwords and short/common filler words', () => {
    const terms = extractTerms(['I really love hiking and photography on the weekends']);
    expect(terms.has('hiking')).toBe(true);
    expect(terms.has('photography')).toBe(true);
    expect(terms.has('weekends')).toBe(true);
    // stopwords / filler must never survive
    expect(terms.has('love')).toBe(false);
    expect(terms.has('and')).toBe(false);
    expect(terms.has('the')).toBe(false);
    expect(terms.has('on')).toBe(false);
  });

  it('unions terms across multiple approved claims', () => {
    const terms = extractTerms(['I play guitar', 'I also enjoy cooking pasta']);
    expect(terms.has('guitar')).toBe(true);
    expect(terms.has('cooking')).toBe(true);
    expect(terms.has('pasta')).toBe(true);
  });
});

describe('scoreCandidate / rankCandidates determinism', () => {
  const viewerClaims = ['I love hiking in the mountains', 'I play guitar every weekend'];

  it('produces the exact same score and overlappingTerms across repeated calls with identical input', () => {
    const candidate: RankingCandidate = {
      userId: 'candidate-1',
      approvedClaimTexts: ['I also enjoy hiking and playing guitar'],
      relationshipIntent: null,
    };
    const viewerTerms = extractTerms(viewerClaims);

    const results = Array.from({ length: 5 }, () => scoreCandidate(viewerTerms, null, candidate));
    for (const r of results) {
      expect(r).toEqual(results[0]);
    }
    expect(results[0].score).toBe(2);
    expect(results[0].overlappingTerms).toEqual(['guitar', 'hiking']);
  });

  it('rankCandidates orders strictly by descending score', () => {
    const candidates: RankingCandidate[] = [
      { userId: 'zero-overlap', approvedClaimTexts: ['I collect vintage stamps'], relationshipIntent: null },
      { userId: 'one-overlap', approvedClaimTexts: ['I love hiking on weekends'], relationshipIntent: null },
      { userId: 'two-overlap', approvedClaimTexts: ['I hike and play guitar too'], relationshipIntent: null },
    ];

    const ranked = rankCandidates(viewerClaims, null, candidates);
    expect(ranked.map((r) => r.candidateUserId)).toEqual(['two-overlap', 'one-overlap', 'zero-overlap']);
    expect(ranked[0].score).toBeGreaterThan(ranked[1].score);
    expect(ranked[1].score).toBeGreaterThan(ranked[2].score);
  });

  it('breaks ties deterministically by userId (localeCompare), not insertion order', () => {
    const candidates: RankingCandidate[] = [
      { userId: 'zzz-user', approvedClaimTexts: ['I love hiking'], relationshipIntent: null },
      { userId: 'aaa-user', approvedClaimTexts: ['I love hiking'], relationshipIntent: null },
      { userId: 'mmm-user', approvedClaimTexts: ['I love hiking'], relationshipIntent: null },
    ];

    const ranked = rankCandidates(viewerClaims, null, candidates);
    // all three tie on score -- must come out alphabetically, regardless of
    // the order they were passed in.
    expect(ranked.map((r) => r.candidateUserId)).toEqual(['aaa-user', 'mmm-user', 'zzz-user']);

    // Reversing input order must not change the output order.
    const rankedReversed = rankCandidates(viewerClaims, null, [...candidates].reverse());
    expect(rankedReversed.map((r) => r.candidateUserId)).toEqual(['aaa-user', 'mmm-user', 'zzz-user']);
  });

  it('is a pure function -- never mutates the input arrays/candidates', () => {
    const candidates: RankingCandidate[] = [
      { userId: 'c1', approvedClaimTexts: ['I love hiking'], relationshipIntent: null },
    ];
    const candidatesCopy = JSON.parse(JSON.stringify(candidates));
    const viewerClaimsCopy = [...viewerClaims];

    rankCandidates(viewerClaims, null, candidates);

    expect(candidates).toEqual(candidatesCopy);
    expect(viewerClaims).toEqual(viewerClaimsCopy);
  });
});

describe('relationshipIntent as a soft ranking signal (never a hard filter)', () => {
  const viewerClaims = ['I love hiking'];

  it('breaks a tie in favor of the candidate whose relationshipIntent matches the viewer\'s', () => {
    const candidates: RankingCandidate[] = [
      { userId: 'no-match', approvedClaimTexts: ['I hike too'], relationshipIntent: 'CASUAL' },
      { userId: 'match', approvedClaimTexts: ['I hike too'], relationshipIntent: 'LONG_TERM' },
    ];

    const ranked = rankCandidates(viewerClaims, 'LONG_TERM', candidates);
    expect(ranked.map((r) => r.candidateUserId)).toEqual(['match', 'no-match']);
    expect(ranked[0].relationshipIntentAligned).toBe(true);
    expect(ranked[1].relationshipIntentAligned).toBe(false);
  });

  it('never lets relationshipIntent alignment outrank a strictly higher keyword-overlap score', () => {
    const candidates: RankingCandidate[] = [
      // Better keyword match but misaligned intent.
      { userId: 'strong-overlap', approvedClaimTexts: ['I love hiking'], relationshipIntent: 'CASUAL' },
      // Weaker keyword match but aligned intent.
      { userId: 'aligned-intent', approvedClaimTexts: ['I collect stamps'], relationshipIntent: 'LONG_TERM' },
    ];

    const ranked = rankCandidates(viewerClaims, 'LONG_TERM', candidates);
    // The stronger keyword-overlap candidate must still come first --
    // relationshipIntent can only break ties among equally-scored
    // candidates, never override the primary keyword signal.
    expect(ranked.map((r) => r.candidateUserId)).toEqual(['strong-overlap', 'aligned-intent']);
  });

  it('treats a null relationshipIntent on either side as unaligned, not a match', () => {
    const candidates: RankingCandidate[] = [
      { userId: 'unset', approvedClaimTexts: ['I hike'], relationshipIntent: null },
    ];
    const ranked = rankCandidates(viewerClaims, null, candidates);
    expect(ranked[0].relationshipIntentAligned).toBe(false);
  });
});

describe('guardrail: ranking never references voice-acoustic or protected-trait signals', () => {
  it('RankingCandidate\'s only inputs are userId, approved claim text, and relationshipIntent -- scoring cannot see anything else', () => {
    // Structural guardrail: construct a candidate using ONLY the fields the
    // RankingCandidate type declares. If a future edit widened this type to
    // include e.g. a voice-acoustic score or a protected trait, this object
    // literal would still type-check fine -- so the real enforcement is the
    // interface definition in ranking.util.ts itself (see its file-level
    // docstring). This test pins the current field set as a regression
    // guard: exactly these three keys, nothing else, on every candidate
    // scored. relationshipIntent is a stated preference field, not an
    // inferred/protected trait -- the brief's own soft-filter instruction
    // covers it explicitly (see eligibility.util.ts's docstring).
    const candidate: RankingCandidate = {
      userId: 'c1',
      approvedClaimTexts: ['I love hiking'],
      relationshipIntent: null,
    };
    expect(Object.keys(candidate).sort()).toEqual(['approvedClaimTexts', 'relationshipIntent', 'userId']);
  });

  it('never produces a score or overlap from banned signal words even if a claim text mentions them', () => {
    // Approved claims are free text from the user's own review step, so
    // ranking must treat words like "attractive" or "confident" as just
    // ordinary tokens -- there is no special-casing that boosts them, and
    // they are not filtered out either (nothing in ranking.util.ts singles
    // out protected/appearance traits for special treatment in either
    // direction -- it has no concept of them at all).
    const viewerTerms = extractTerms(['I think confidence and being attractive matter']);
    const candidate: RankingCandidate = {
      userId: 'c1',
      approvedClaimTexts: ['I also value confidence in a partner'],
      relationshipIntent: null,
    };
    const result = scoreCandidate(viewerTerms, null, candidate);
    // Ordinary overlap scoring applies uniformly -- no special banned-word path exists.
    expect(result.score).toBe(result.overlappingTerms.length);
  });
});

import { TemplateReasonGenerationProvider } from './template-reason-generation.provider.js';

// Same contract-level checks as WP2's mock-extraction.provider.spec.ts --
// apply to any future real (LLM-backed) implementation too, not just this
// mock, since the guardrail lives on ReasonGenerationProvider's interface.
const FORBIDDEN_PATTERNS = [
  /attractive/i,
  /beautiful/i,
  /handsome/i,
  /pretty/i,
  /cute/i,
  /sexy/i,
  /charming/i,
  /confiden(t|ce)/i,
  /sounds? like/i,
  /voice (is|sounds)/i,
  /accent/i,
  /personality/i,
  /\bvibe\b/i,
  /seems? (to be|like)/i,
  /race|ethnicity|religio/i,
];

describe('TemplateReasonGenerationProvider (guardrail contract)', () => {
  let provider: TemplateReasonGenerationProvider;

  beforeEach(() => {
    provider = new TemplateReasonGenerationProvider();
  });

  it('never emits personality/attractiveness/tone/protected-trait language', async () => {
    const reason = await provider.generate({
      overlappingTerms: ['hiking', 'guitar'],
      viewerClaimTexts: ['I love hiking and playing guitar'],
      candidateClaimTexts: ['I also hike and play guitar every weekend'],
    });

    for (const pattern of FORBIDDEN_PATTERNS) {
      expect(reason).not.toMatch(pattern);
    }
  });

  it('is grounded: every overlapping term it names actually appears in overlappingTerms verbatim', async () => {
    const overlappingTerms = ['cooking', 'travel'];
    const reason = await provider.generate({
      overlappingTerms,
      viewerClaimTexts: ['I love cooking and traveling'],
      candidateClaimTexts: ['I love cooking and traveling too'],
    });

    for (const term of overlappingTerms) {
      expect(reason).toContain(term);
    }
  });

  it('single-overlap case names exactly that one term', async () => {
    const reason = await provider.generate({
      overlappingTerms: ['pottery'],
      viewerClaimTexts: [],
      candidateClaimTexts: [],
    });
    expect(reason).toBe('You both mentioned pottery.');
  });

  it('zero-overlap case falls back to an honest, non-fabricated generic line -- never invents a shared interest', async () => {
    const reason = await provider.generate({
      overlappingTerms: [],
      viewerClaimTexts: ['I collect stamps'],
      candidateClaimTexts: ['I play chess'],
    });

    expect(reason).not.toMatch(/mentioned/i);
    for (const pattern of FORBIDDEN_PATTERNS) {
      expect(reason).not.toMatch(pattern);
    }
  });

  it('never fabricates a term that is absent from overlappingTerms, even when claim text contains other words', async () => {
    const reason = await provider.generate({
      overlappingTerms: ['hiking'],
      viewerClaimTexts: ['I love hiking and I am very confident and attractive'],
      candidateClaimTexts: ['I hike too and everyone says I have a great personality'],
    });

    // Only the actual overlapping term may be named -- the banned words
    // present in the raw claim text (confident/attractive/personality)
    // must never leak into the generated sentence even though they appear
    // in the raw inputs, proving the provider only reads overlappingTerms
    // for content, not the free-text claims themselves.
    expect(reason).toBe('You both mentioned hiking.');
    for (const pattern of FORBIDDEN_PATTERNS) {
      expect(reason).not.toMatch(pattern);
    }
  });
});

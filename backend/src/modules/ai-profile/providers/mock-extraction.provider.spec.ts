import { MockExtractionProvider } from './mock-extraction.provider.js';

// These are sanity checks on the CONTRACT (extraction-provider.interface.ts's
// documented guardrails), not just this one mock implementation -- if a
// real vendor-backed provider is swapped in later, its output should be
// run through the same kind of checks before it ships.
const FORBIDDEN_PATTERNS = [
  /attractive/i,
  /beautiful/i,
  /handsome/i,
  /pretty/i,
  /cute/i,
  /sexy/i,
  /charming/i,
  /confiden(t|ce)/i, // personality inference, not a stated fact
  /sounds? like/i, // tone/voice-based inference
  /voice (is|sounds)/i,
  /accent/i,
  /personality/i,
  /\bvibe\b/i,
  /seems? (to be|like)/i, // hedged inference language
];

describe('MockExtractionProvider (guardrail contract)', () => {
  let provider: MockExtractionProvider;

  beforeEach(() => {
    provider = new MockExtractionProvider();
  });

  it('never emits personality/attractiveness/tone-inferred language', async () => {
    const transcript =
      'I love hiking on weekends and trying new coffee shops around the city. ' +
      "I'm looking for someone who enjoys deep conversations as much as spontaneous road trips.";

    const claims = await provider.extract(transcript);

    expect(claims.length).toBeGreaterThan(0);
    for (const claim of claims) {
      for (const pattern of FORBIDDEN_PATTERNS) {
        expect(claim.text).not.toMatch(pattern);
      }
    }
  });

  it('every claim is an exact substring of the transcript -- proves it only summarizes what was said', async () => {
    const transcript =
      'I grew up in Chicago. I play guitar badly but enthusiastically. I want kids someday.';
    const claims = await provider.extract(transcript);

    expect(claims.length).toBeGreaterThan(0);
    for (const claim of claims) {
      expect(transcript).toContain(claim.text);
    }
  });

  it('sourceSpan accurately points back into the transcript', async () => {
    const transcript = 'I love pizza. I hate mushrooms.';
    const claims = await provider.extract(transcript);

    for (const claim of claims) {
      const [start, end] = claim.sourceSpan!.split('-').map(Number);
      expect(transcript.slice(start, end).trim()).toBe(claim.text);
    }
  });

  it('produces no claims from an empty or punctuation-only transcript (nothing to invent from)', async () => {
    expect(await provider.extract('')).toEqual([]);
    expect(await provider.extract('...')).toEqual([]);
  });

  it('handles a transcript with content an LLM might be tempted to editorialize about, without doing so', async () => {
    // A real vendor's prompt needs to resist inferring from HOW something
    // is said (tone/pace/accent) -- this transcript deliberately reads
    // like something a poorly-guarded LLM might editorialize on.
    const transcript =
      'I talk really fast when I get excited about music. My laugh is loud, my friends say. ' +
      'I grew up speaking two languages at home.';
    const claims = await provider.extract(transcript);

    for (const claim of claims) {
      for (const pattern of FORBIDDEN_PATTERNS) {
        expect(claim.text).not.toMatch(pattern);
      }
      // Still must be a verbatim excerpt, not a rephrasing/inference.
      expect(transcript).toContain(claim.text);
    }
  });
});

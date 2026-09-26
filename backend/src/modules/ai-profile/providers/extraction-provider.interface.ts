export interface DraftClaim {
  text: string;
  sourceSpan?: string;
}

/**
 * HARD GUARDRAILS — non-negotiable product rules, not a style preference.
 * Every implementation of this interface (mock or real) MUST satisfy all
 * four, and any real-vendor prompt/contract built on top of this
 * interface must bake these in as hard constraints, not soft guidance:
 *
 *  1. May ONLY summarize what the user explicitly said in the
 *     transcript -- never invent or add content the transcript doesn't
 *     support.
 *  2. Must NEVER infer or output anything about personality,
 *     attractiveness, ethnicity, health, or "vibe" -- including from
 *     tone, accent, or speaking pace. A claim like "sounds confident" or
 *     "has a nice voice" is a guardrail violation even if it sounds
 *     complimentary.
 *  3. Every claim produced here is a DRAFT. Nothing from this interface
 *     is ever shown to another user or used for matching until the
 *     user has explicitly reviewed and approved it (ProfileClaim.approved).
 *     This interface has no "auto-publish" path and must never grow one.
 *  4. Must never use protected traits (race, religion, national origin,
 *     etc.) as a hidden ranking/scoring signal -- this interface only
 *     ever returns claims for the user's own review, never a score.
 *
 * Real vendor is still TBD from the client (kept generic on purpose --
 * same reasoning as TranscriptionProvider).
 */
export interface ProfileExtractionProvider {
  extract(transcript: string): Promise<DraftClaim[]>;
}

export const EXTRACTION_PROVIDER = 'EXTRACTION_PROVIDER';

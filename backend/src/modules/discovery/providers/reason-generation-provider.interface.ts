export interface ReasonGenerationInput {
  /** Significant terms shared between both users' approved claims (from
   * ranking.util.ts) -- the ONLY thing this may build a sentence from
   * along with the raw claim text below. Never a raw numeric score. */
  overlappingTerms: string[];
  viewerClaimTexts: string[];
  candidateClaimTexts: string[];
}

/**
 * Same category of hard guardrail as WP2's ProfileExtractionProvider --
 * any implementation (mock or real) MUST hold these:
 *  1. Must be grounded in actual overlappingTerms/claim text -- never a
 *     vague/generic line ("You might get along!") and never a numeric
 *     score shown to the user.
 *  2. Must NEVER reference voice-acoustic properties, inferred
 *     personality, attractiveness, or protected traits -- those never
 *     appear in this interface's inputs, so a compliant implementation
 *     can only violate this by inventing content not present in the
 *     inputs at all.
 *  3. The only legitimate exception to "never generic" is a genuine
 *     zero-overlap pairing (no shared terms exist to ground a sentence
 *     in) -- an honest, mild fallback there is not the same as
 *     fabricating a false specific claim.
 *
 * Real vendor (an LLM call) is a later swap -- same reasoning as WP2's
 * provider interfaces, kept generic on purpose.
 */
export interface ReasonGenerationProvider {
  generate(input: ReasonGenerationInput): Promise<string>;
}

export const REASON_GENERATION_PROVIDER = 'REASON_GENERATION_PROVIDER';

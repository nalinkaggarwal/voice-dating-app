/**
 * HARD RULE (same category as WP2's extraction guardrails -- this is a
 * repeat of the client's hardest non-negotiable requirement, not a
 * lesser rule): ranking may ONLY use explicitly approved ProfileClaim
 * text and explicitly stated Preference fields. NEVER voice-acoustic
 * properties, inferred personality, attractiveness, or protected traits
 * (race, religion, etc.) -- there is no field for any of those in the
 * inputs this function accepts, by construction, not just by convention.
 *
 * Deliberately a simple, explainable keyword/topic overlap -- NOT an ML
 * model or embedding similarity. WP3 is not building a recommendation
 * engine; a score you can point at ("these 3 words overlapped") is the
 * point, both for this WP's reason-generation step and for future
 * support/moderation questions ("why did X see Y instead of Z" --
 * a ranking question, distinct from EligibilityService's "why didn't X
 * ever see Y" filter question).
 */

const STOPWORDS = new Set([
  'i', 'a', 'an', 'the', 'and', 'or', 'but', 'my', 'is', 'am', 'are', 'was',
  'were', 'to', 'of', 'in', 'on', 'for', 'with', 'that', 'this', 'it', 'be',
  'im', "i'm", 'love', 'like', 'enjoy', 'really', 'very', 'so', 'also',
  'me', 'you', 'your', 'we', 'us', 'our', 'at', 'as', 'by', 'from', 'do',
  'does', 'did', 'have', 'has', 'had', 'will', 'would', 'can', 'could',
  'someone', 'who', 'what', 'when', 'where', 'always', 'friends', 'say',
]);

function significantTerms(text: string): Set<string> {
  const words = text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w));
  return new Set(words);
}

export interface RankingCandidate {
  userId: string;
  approvedClaimTexts: string[];
  /** Mirrors EligibilityCandidate.relationshipIntent -- deliberately NOT a
   * hard eligibility filter (see eligibility.util.ts's docstring): with an
   * early/sparse user base, excluding on this would risk zeroing out
   * candidates for most users. Used here only as a soft tiebreaker. */
  relationshipIntent: string | null;
}

export interface RankingResult {
  candidateUserId: string;
  score: number;
  /** The actual shared significant terms -- feeds ReasonGenerationProvider
   * so the generated sentence is grounded in real overlap, never generic. */
  overlappingTerms: string[];
  /** True when both sides stated the same relationshipIntent. Breaks ties
   * among equally-keyword-scored candidates -- never overrides the keyword
   * overlap score itself, so it stays a soft nudge, not a filter. */
  relationshipIntentAligned: boolean;
}

/** Union of significant terms across every approved claim a user has. */
export function extractTerms(approvedClaimTexts: string[]): Set<string> {
  const all = new Set<string>();
  for (const text of approvedClaimTexts) {
    for (const term of significantTerms(text)) all.add(term);
  }
  return all;
}

/**
 * Scores ONE candidate against the viewer's own terms. Score is simply
 * the size of the term intersection -- deterministic, explainable, and
 * trivially reproducible for a given pair of claim sets (same input,
 * same output, no randomness) -- required for the "ranking determinism"
 * test the brief calls for. relationshipIntent alignment is computed
 * alongside the score but never added into it (see rankCandidates).
 */
export function scoreCandidate(
  viewerTerms: Set<string>,
  viewerRelationshipIntent: string | null,
  candidate: RankingCandidate,
): RankingResult {
  const candidateTerms = extractTerms(candidate.approvedClaimTexts);
  const overlappingTerms = [...viewerTerms].filter((t) => candidateTerms.has(t)).sort();
  const relationshipIntentAligned =
    viewerRelationshipIntent !== null &&
    candidate.relationshipIntent !== null &&
    viewerRelationshipIntent === candidate.relationshipIntent;
  return {
    candidateUserId: candidate.userId,
    score: overlappingTerms.length,
    overlappingTerms,
    relationshipIntentAligned,
  };
}

/**
 * Ranks every eligible candidate, highest keyword-overlap score first.
 * Ties on score break first toward relationshipIntent alignment (the soft
 * signal the brief asked for in place of a hard filter), then on userId
 * (stable, deterministic) rather than insertion order, which could
 * otherwise vary between runs depending on DB query ordering.
 *
 * relationshipIntent can only ever reorder candidates who are ALREADY
 * tied on keyword overlap -- it can never outrank a candidate with a
 * stronger keyword match, which is what keeps this a soft nudge rather
 * than a de facto filter.
 */
export function rankCandidates(
  viewerApprovedClaimTexts: string[],
  viewerRelationshipIntent: string | null,
  candidates: RankingCandidate[],
): RankingResult[] {
  const viewerTerms = extractTerms(viewerApprovedClaimTexts);
  return candidates
    .map((c) => scoreCandidate(viewerTerms, viewerRelationshipIntent, c))
    .sort(
      (a, b) =>
        b.score - a.score ||
        Number(b.relationshipIntentAligned) - Number(a.relationshipIntentAligned) ||
        a.candidateUserId.localeCompare(b.candidateUserId),
    );
}

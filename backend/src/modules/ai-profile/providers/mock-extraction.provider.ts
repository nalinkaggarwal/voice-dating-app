import { Injectable, Logger } from '@nestjs/common';
import type {
  DraftClaim,
  ProfileExtractionProvider,
} from './extraction-provider.interface.js';

// WP2 dev/test stub. Deliberately the SIMPLEST possible implementation
// that still satisfies the interface's guardrails by construction rather
// than by careful prompting: it splits the transcript into sentences and
// emits each one verbatim as a claim, with sourceSpan pointing at its
// exact character offset in the transcript.
//
// This trivially can't violate guardrails #1/#2 (only summarizes what was
// said, never infers personality/attractiveness/etc.) because it never
// adds or transforms anything -- it only extracts what's already there.
// A real LLM-backed implementation will need actual prompt engineering to
// hold those same guarantees; this mock's job is only to exercise the
// pipeline's state machine and shape, not to model real extraction quality.
@Injectable()
export class MockExtractionProvider implements ProfileExtractionProvider {
  private readonly logger = new Logger(MockExtractionProvider.name);

  async extract(transcript: string): Promise<DraftClaim[]> {
    this.logger.log('[MOCK EXTRACTION] deriving draft claims from transcript');

    const claims: DraftClaim[] = [];
    // Split on sentence-ending punctuation, keeping the offsets so
    // sourceSpan can point back into the original transcript exactly.
    const sentenceRegex = /[^.!?]+[.!?]+/g;
    let match: RegExpExecArray | null;
    while ((match = sentenceRegex.exec(transcript)) !== null) {
      const sentence = match[0].trim();
      if (sentence.length < 3) continue;
      const start = match.index;
      const end = start + match[0].length;
      claims.push({ text: sentence, sourceSpan: `${start}-${end}` });
    }

    return claims;
  }
}

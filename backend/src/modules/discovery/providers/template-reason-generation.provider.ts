import { Injectable } from '@nestjs/common';
import type {
  ReasonGenerationInput,
  ReasonGenerationProvider,
} from './reason-generation-provider.interface.js';

// WP3 mock: no LLM call, just a template built directly from
// overlappingTerms (already computed by ranking.util.ts as an
// intersection of both users' approved-claim terms, so every term here
// is guaranteed to actually appear, post-tokenization, in BOTH people's
// approved claims -- this can't fabricate a shared interest that isn't
// really there).
@Injectable()
export class TemplateReasonGenerationProvider implements ReasonGenerationProvider {
  async generate(input: ReasonGenerationInput): Promise<string> {
    const { overlappingTerms } = input;

    if (overlappingTerms.length === 0) {
      // Genuine zero-overlap pairing -- an honest, mild fallback, not a
      // fabricated specific claim (see the interface's guardrail #3).
      return "You're both new here — say hi and see where the conversation goes.";
    }

    if (overlappingTerms.length === 1) {
      return `You both mentioned ${overlappingTerms[0]}.`;
    }

    const [first, second] = overlappingTerms;
    return `You both mentioned ${first} and ${second}.`;
  }
}

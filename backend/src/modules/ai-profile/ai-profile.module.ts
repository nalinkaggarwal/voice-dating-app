import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { AiProfileController } from './ai-profile.controller.js';
import { AiProfileService } from './ai-profile.service.js';
import { StorageModule } from '../../shared/storage/storage.module.js';
import { IdentityModule } from '../identity/identity.module.js';
import { EXTRACTION_QUEUE, TRANSCRIPTION_QUEUE } from './queue.constants.js';
import { TranscriptionProcessor } from './processors/transcription.processor.js';
import { ExtractionProcessor } from './processors/extraction.processor.js';
import { TRANSCRIPTION_PROVIDER } from './providers/transcription-provider.interface.js';
import { EXTRACTION_PROVIDER } from './providers/extraction-provider.interface.js';
import { MockTranscriptionProvider } from './providers/mock-transcription.provider.js';
import { MockExtractionProvider } from './providers/mock-extraction.provider.js';

@Module({
  imports: [
    StorageModule,
    IdentityModule, // needs AccessTokenGuard
    BullModule.registerQueue({ name: TRANSCRIPTION_QUEUE }, { name: EXTRACTION_QUEUE }),
  ],
  controllers: [AiProfileController],
  providers: [
    AiProfileService,
    TranscriptionProcessor,
    ExtractionProcessor,
    // Swap these two for real-vendor implementations later -- nothing
    // else in this module needs to change (see the interfaces' own
    // docstrings for the guardrails any real implementation must hold).
    { provide: TRANSCRIPTION_PROVIDER, useClass: MockTranscriptionProvider },
    { provide: EXTRACTION_PROVIDER, useClass: MockExtractionProvider },
  ],
  exports: [AiProfileService],
})
export class AiProfileModule {}

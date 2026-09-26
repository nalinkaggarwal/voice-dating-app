import { Module } from '@nestjs/common';
import { DiscoveryController } from './discovery.controller.js';
import { DiscoveryService } from './discovery.service.js';
import { EligibilityService } from './eligibility.service.js';
import { DiscoveryConfigService } from './discovery-config.service.js';
import { QueueGenerationService } from './queue-generation.service.js';
import { DiscoveryScheduler } from './discovery.scheduler.js';
import { REASON_GENERATION_PROVIDER } from './providers/reason-generation-provider.interface.js';
import { TemplateReasonGenerationProvider } from './providers/template-reason-generation.provider.js';
import { ConnectionsModule } from '../connections/connections.module.js';
import { IdentityModule } from '../identity/identity.module.js';
import { StorageModule } from '../../shared/storage/storage.module.js';

@Module({
  imports: [ConnectionsModule, IdentityModule, StorageModule],
  controllers: [DiscoveryController],
  providers: [
    DiscoveryService,
    EligibilityService,
    DiscoveryConfigService,
    QueueGenerationService,
    DiscoveryScheduler,
    // Swap for a real LLM-backed implementation later -- same pattern as
    // WP2's TRANSCRIPTION_PROVIDER/EXTRACTION_PROVIDER.
    { provide: REASON_GENERATION_PROVIDER, useClass: TemplateReasonGenerationProvider },
  ],
  exports: [DiscoveryService, QueueGenerationService],
})
export class DiscoveryModule {}

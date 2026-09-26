import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { QueueGenerationService } from './queue-generation.service.js';

// @nestjs/schedule over a BullMQ repeatable job -- this is a single daily
// batch over the whole user table, not per-item work that benefits from
// a distributed queue/worker split; a cron job is the simpler tool for
// the job. generateForAllActiveUsers() is itself idempotent per user per
// day, so a missed/retried trigger (e.g. a redeploy right at 03:00) can
// never double-generate.
@Injectable()
export class DiscoveryScheduler {
  private readonly logger = new Logger(DiscoveryScheduler.name);

  constructor(private readonly queueGeneration: QueueGenerationService) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async handleDailyGeneration(): Promise<void> {
    this.logger.log('Starting daily discovery queue generation');
    try {
      const result = await this.queueGeneration.generateForAllActiveUsers();
      this.logger.log(
        `Daily discovery queue generation complete: ${JSON.stringify(result)}`,
      );
    } catch (error) {
      this.logger.error('Daily discovery queue generation failed', error);
    }
  }
}

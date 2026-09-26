import { Injectable } from '@nestjs/common';
import type { UserTier } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';

const DEFAULT_LIMIT = 1;

/**
 * Free vs. premium daily candidate limits, read fresh from the DB every
 * call (no in-memory caching) -- the whole point is that ops can change
 * a tier's limit by editing the DiscoveryConfig row directly and have it
 * take effect on the NEXT scheduled generation run, with no deploy.
 */
@Injectable()
export class DiscoveryConfigService {
  constructor(private readonly prisma: PrismaService) {}

  async dailyLimitFor(tier: UserTier): Promise<number> {
    const config = await this.prisma.discoveryConfig.findUnique({ where: { tier } });
    return config?.dailyCandidateLimit ?? DEFAULT_LIMIT;
  }
}

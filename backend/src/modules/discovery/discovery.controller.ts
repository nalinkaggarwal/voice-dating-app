import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { DiscoveryService } from './discovery.service.js';
import { DecideDto } from './dto/decide.dto.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

// The /v1/ prefix now comes from the global setGlobalPrefix('v1') in
// main.ts (applied to every module's routes, not just this one) --
// resolves the versioning inconsistency flagged when this controller was
// first written with a locally hardcoded 'v1/discovery' prefix.
@UseGuards(AccessTokenGuard)
@Controller('discovery')
export class DiscoveryController {
  constructor(private readonly discoveryService: DiscoveryService) {}

  @Get('queue/today')
  async today(@CurrentUserId() userId: string) {
    // Wrapped in an object (not a bare array) -- the Flutter ApiClient's
    // response decoding assumes every endpoint returns a JSON object, the
    // same as every other route in this API.
    return { entries: await this.discoveryService.today(userId) };
  }

  @Post('queue/:entryId/decide')
  decide(
    @CurrentUserId() userId: string,
    @Param('entryId') entryId: string,
    @Body() dto: DecideDto,
  ) {
    return this.discoveryService.decide(userId, entryId, dto.decision);
  }
}

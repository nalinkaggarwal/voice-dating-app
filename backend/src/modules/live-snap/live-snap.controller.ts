import { Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { LiveSnapService } from './live-snap.service.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

// Public STUN only -- no TURN server stood up for this pass. Calls can
// fail to connect behind a restrictive/symmetric NAT; documented
// limitation, not an oversight. Returned to the client so it's never
// hardcoded on the mobile side either.
const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
];

@UseGuards(AccessTokenGuard)
@Controller('live-snap')
export class LiveSnapController {
  constructor(private readonly liveSnapService: LiveSnapService) {}

  @Post(':connectionId/start')
  async start(@CurrentUserId() userId: string, @Param('connectionId') connectionId: string) {
    const session = await this.liveSnapService.startSession(userId, connectionId);
    return { session, iceServers: ICE_SERVERS };
  }

  @Get(':connectionId/session')
  getSession(@CurrentUserId() userId: string, @Param('connectionId') connectionId: string) {
    return this.liveSnapService.getSession(userId, connectionId);
  }
}

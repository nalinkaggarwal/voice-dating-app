import { Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ConnectionsService } from './connections.service.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

@UseGuards(AccessTokenGuard)
@Controller('connections')
export class ConnectionsController {
  constructor(private readonly connectionsService: ConnectionsService) {}

  @Get(':id/reveal')
  getReveal(@CurrentUserId() userId: string, @Param('id') id: string) {
    return this.connectionsService.getReveal(userId, id);
  }

  @Post(':id/decline')
  decline(@CurrentUserId() userId: string, @Param('id') id: string) {
    return this.connectionsService.decline(userId, id);
  }

  @Post(':id/snap/confirm')
  confirmSnap(@CurrentUserId() userId: string, @Param('id') id: string) {
    return this.connectionsService.markSnapDone(userId, id);
  }
}

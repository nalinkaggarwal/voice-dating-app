import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { MessagingService } from './messaging.service.js';
import { SendMessageDto } from './dto/send-message.dto.js';
import { RequestVoiceMessageUploadUrlDto } from './dto/request-voice-message-upload-url.dto.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

@UseGuards(AccessTokenGuard)
@Controller('messaging')
export class MessagingController {
  constructor(private readonly messagingService: MessagingService) {}

  @Get('conversations')
  async listConversations(@CurrentUserId() userId: string) {
    // Wrapped in an object (not a bare array), same reason
    // discovery.controller.ts's today() is -- the Flutter ApiClient's
    // response decoding assumes every endpoint returns a JSON object.
    return { conversations: await this.messagingService.listConversations(userId) };
  }

  @Post('voice/upload-url')
  requestVoiceUploadUrl(@Body() dto: RequestVoiceMessageUploadUrlDto) {
    return this.messagingService.requestVoiceUploadUrl(dto.contentType);
  }

  @Get(':connectionId/messages')
  getHistory(
    @CurrentUserId() userId: string,
    @Param('connectionId') connectionId: string,
    @Query('before') before?: string,
    @Query('since') since?: string,
    @Query('limit') limit?: string,
  ) {
    return this.messagingService.getHistory(userId, connectionId, {
      before,
      since,
      limit: limit ? Number(limit) : undefined,
    });
  }

  @Post(':connectionId/messages')
  sendMessage(
    @CurrentUserId() userId: string,
    @Param('connectionId') connectionId: string,
    @Body() dto: SendMessageDto,
  ) {
    return this.messagingService.sendMessage(userId, connectionId, dto);
  }

  @Post(':connectionId/delivered')
  markDelivered(@CurrentUserId() userId: string, @Param('connectionId') connectionId: string) {
    return this.messagingService.markDelivered(userId, connectionId);
  }

  @Post(':connectionId/read')
  markRead(@CurrentUserId() userId: string, @Param('connectionId') connectionId: string) {
    return this.messagingService.markRead(userId, connectionId);
  }
}

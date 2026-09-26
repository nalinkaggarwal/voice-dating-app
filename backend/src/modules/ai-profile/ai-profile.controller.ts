import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { AiProfileService } from './ai-profile.service.js';
import { RequestVoiceUploadUrlDto } from './dto/request-upload-url.dto.js';
import { CompleteVoiceUploadDto } from './dto/complete-upload.dto.js';
import { EditClaimDto } from './dto/edit-claim.dto.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

@UseGuards(AccessTokenGuard)
@Controller('ai-profile')
export class AiProfileController {
  constructor(private readonly aiProfileService: AiProfileService) {}

  @Post('voice/upload-url')
  requestVoiceUploadUrl(@Body() dto: RequestVoiceUploadUrlDto) {
    return this.aiProfileService.requestVoiceUploadUrl(dto.contentType);
  }

  @Post('voice/complete')
  completeVoiceUpload(@CurrentUserId() userId: string, @Body() dto: CompleteVoiceUploadDto) {
    return this.aiProfileService.completeVoiceUpload(userId, dto.key);
  }

  @Get('voice/:voiceAnswerId')
  getVoiceAnswer(@CurrentUserId() userId: string, @Param('voiceAnswerId') voiceAnswerId: string) {
    return this.aiProfileService.getVoiceAnswer(userId, voiceAnswerId);
  }

  @Post('voice/:voiceAnswerId/finalize')
  finalize(@CurrentUserId() userId: string, @Param('voiceAnswerId') voiceAnswerId: string) {
    return this.aiProfileService.finalizeReview(userId, voiceAnswerId);
  }

  @Post('claims/:claimId/edit')
  editClaim(
    @CurrentUserId() userId: string,
    @Param('claimId') claimId: string,
    @Body() dto: EditClaimDto,
  ) {
    return this.aiProfileService.editClaim(userId, claimId, dto.text);
  }

  @Post('claims/:claimId/approve')
  approveClaim(@CurrentUserId() userId: string, @Param('claimId') claimId: string) {
    return this.aiProfileService.approveClaim(userId, claimId);
  }

  @Post('claims/:claimId/discard')
  discardClaim(@CurrentUserId() userId: string, @Param('claimId') claimId: string) {
    return this.aiProfileService.discardClaim(userId, claimId);
  }
}

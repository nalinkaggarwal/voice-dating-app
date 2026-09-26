import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { ProfileService } from './profile.service.js';
import { BasicInfoDto } from './dto/basic-info.dto.js';
import { PreferencesDto } from './dto/preferences.dto.js';
import { IntentDto } from './dto/intent.dto.js';
import { RequestPhotoUploadUrlDto } from './dto/request-photo-upload-url.dto.js';
import { CompletePhotoUploadDto } from './dto/complete-photo-upload.dto.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

@UseGuards(AccessTokenGuard)
@Controller('profile')
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Post('basic-info')
  submitBasicInfo(@CurrentUserId() userId: string, @Body() dto: BasicInfoDto) {
    return this.profileService.submitBasicInfo(userId, dto);
  }

  @Post('preferences')
  submitPreferences(@CurrentUserId() userId: string, @Body() dto: PreferencesDto) {
    return this.profileService.submitPreferences(userId, dto);
  }

  @Post('intent')
  submitIntent(@CurrentUserId() userId: string, @Body() dto: IntentDto) {
    return this.profileService.submitIntent(userId, dto.relationshipIntent);
  }

  @Post('photo/upload-url')
  requestPhotoUploadUrl(@Body() dto: RequestPhotoUploadUrlDto) {
    return this.profileService.requestPhotoUploadUrl(dto.contentType);
  }

  @Post('photo/complete')
  completePhotoUpload(@CurrentUserId() userId: string, @Body() dto: CompletePhotoUploadDto) {
    return this.profileService.completePhotoUpload(userId, dto.key);
  }
}

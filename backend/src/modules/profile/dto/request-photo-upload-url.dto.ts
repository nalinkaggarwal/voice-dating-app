import { IsIn, IsString } from 'class-validator';

const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;

export class RequestPhotoUploadUrlDto {
  @IsString()
  @IsIn(ALLOWED_IMAGE_TYPES)
  contentType!: (typeof ALLOWED_IMAGE_TYPES)[number];
}

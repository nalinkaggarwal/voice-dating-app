import { IsEnum, IsString, MinLength } from 'class-validator';
import { DevicePlatform } from '@prisma/client';

// Enforced by the global ValidationPipe (src/validation.ts).
export class RegisterDeviceDto {
  // FCM registration tokens are long opaque strings; the floor only
  // catches an obviously empty/placeholder value, not a forged one.
  @IsString()
  @MinLength(20)
  token!: string;

  @IsEnum(DevicePlatform)
  platform!: DevicePlatform;
}

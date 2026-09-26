import { IsEnum, IsString, MinLength } from 'class-validator';
import { OtpChannel } from '@prisma/client';

export class StartLoginDto {
  @IsEnum(OtpChannel)
  channel!: OtpChannel;

  @IsString()
  @MinLength(3)
  identifier!: string;
}

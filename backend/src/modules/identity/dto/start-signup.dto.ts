import { IsDateString, IsEnum, IsString, MinLength } from 'class-validator';
import { OtpChannel } from '@prisma/client';

export class StartSignupDto {
  @IsEnum(OtpChannel)
  channel!: OtpChannel;

  // Raw email or phone (E.164 expected for PHONE) -- validated for shape
  // in IdentityService since the rule differs per channel.
  @IsString()
  @MinLength(3)
  identifier!: string;

  @IsDateString()
  dateOfBirth!: string;
}

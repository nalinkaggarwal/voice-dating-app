import { IsString, IsUUID, Length } from 'class-validator';

export class VerifyOtpDto {
  @IsUUID()
  challengeId!: string;

  @IsString()
  @Length(4, 8)
  code!: string;
}

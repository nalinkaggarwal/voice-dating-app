import { IsString, MinLength } from 'class-validator';

export class CompleteVoiceUploadDto {
  @IsString()
  @MinLength(3)
  key!: string;
}

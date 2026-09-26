import { IsString, MinLength } from 'class-validator';

export class CompletePhotoUploadDto {
  @IsString()
  @MinLength(3)
  key!: string;
}

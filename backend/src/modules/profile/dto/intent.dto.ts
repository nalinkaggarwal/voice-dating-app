import { IsString, MinLength } from 'class-validator';

export class IntentDto {
  @IsString()
  @MinLength(1)
  relationshipIntent!: string;
}

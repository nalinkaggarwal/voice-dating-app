import { IsString, MinLength } from 'class-validator';

export class EditClaimDto {
  @IsString()
  @MinLength(1)
  text!: string;
}

import { ArrayNotEmpty, IsArray, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class PreferencesDto {
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  genderInterest!: string[];

  @IsOptional()
  @IsInt()
  @Min(18)
  ageMin?: number;

  @IsOptional()
  @IsInt()
  @Max(120)
  ageMax?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  maxDistanceKm?: number;
}

import { IsOptional, IsString, MinLength } from 'class-validator';

export class BasicInfoDto {
  @IsString()
  @MinLength(1)
  displayName!: string;

  // Coarse geohash only -- never exact lat/long, matches Profile.geohash's
  // own comment in the schema.
  @IsOptional()
  @IsString()
  geohash?: string;
}

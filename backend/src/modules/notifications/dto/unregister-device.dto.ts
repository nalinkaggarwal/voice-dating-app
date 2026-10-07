import { IsString, MinLength } from 'class-validator';

// Enforced by the global ValidationPipe (src/validation.ts).
export class UnregisterDeviceDto {
  @IsString()
  @MinLength(20)
  token!: string;
}

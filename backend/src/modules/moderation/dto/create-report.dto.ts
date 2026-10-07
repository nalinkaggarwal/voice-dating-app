import { IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { ReportContext, ReportReason } from '@prisma/client';

// Enforced by the global ValidationPipe (src/validation.ts) since the
// post-WP6 validation pass. ModerationService still checks required
// fields itself too, so a non-HTTP caller gets the same errors.
export class CreateReportDto {
  @IsString()
  @MinLength(1)
  reportedUserId!: string;

  @IsEnum(ReportReason)
  reason!: ReportReason;

  @IsEnum(ReportContext)
  context!: ReportContext;

  @IsOptional()
  @IsString()
  contextId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  details?: string;
}

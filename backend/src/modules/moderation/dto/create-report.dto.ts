import { IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { ReportContext, ReportReason } from '@prisma/client';

// NOTE: no ValidationPipe is registered anywhere in this app (see
// messaging's send-message.dto.ts for the same caveat) -- ModerationService
// checks required fields itself rather than relying on these decorators.
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

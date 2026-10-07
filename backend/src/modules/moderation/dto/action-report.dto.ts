import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ReportStatus } from '@prisma/client';

// Enforced by the global ValidationPipe (src/validation.ts) -- see
// create-report.dto.ts's own note.
export class ActionReportDto {
  @IsEnum(ReportStatus)
  status!: ReportStatus;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  decision?: string;
}

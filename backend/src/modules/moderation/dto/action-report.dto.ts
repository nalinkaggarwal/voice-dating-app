import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ReportStatus } from '@prisma/client';

// NOTE: no ValidationPipe is registered anywhere in this app -- see
// create-report.dto.ts's own note.
export class ActionReportDto {
  @IsEnum(ReportStatus)
  status!: ReportStatus;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  decision?: string;
}

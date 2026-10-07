import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import type { ReportContext, ReportStatus } from '@prisma/client';
import { ModerationService } from './moderation.service.js';
import { CreateReportDto } from './dto/create-report.dto.js';
import { ActionReportDto } from './dto/action-report.dto.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { AdminGuard } from '../identity/guards/admin.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';
import type { ReportPriority } from './report-priority.util.js';

@Controller('moderation')
export class ModerationController {
  constructor(private readonly moderationService: ModerationService) {}

  // Any authenticated user can report -- no admin gate here, unlike
  // everything else in this controller.
  @UseGuards(AccessTokenGuard)
  @Post('reports')
  report(@CurrentUserId() userId: string, @Body() dto: CreateReportDto) {
    return this.moderationService.report(userId, dto);
  }

  // Reports are sensitive -- every route below is admin-only.
  // AccessTokenGuard must run first so AdminGuard has request.userId to
  // look up.
  @UseGuards(AccessTokenGuard, AdminGuard)
  @Get('reports')
  listReports(
    @Query('status') status?: ReportStatus,
    @Query('context') context?: ReportContext,
    @Query('priority') priority?: ReportPriority,
  ) {
    return this.moderationService.listReports({ status, context, priority });
  }

  @UseGuards(AccessTokenGuard, AdminGuard)
  @Get('reports/:id')
  getReport(@Param('id') id: string) {
    return this.moderationService.getReport(id);
  }

  @UseGuards(AccessTokenGuard, AdminGuard)
  @Post('reports/:id/action')
  actionReport(@CurrentUserId() reviewerId: string, @Param('id') id: string, @Body() dto: ActionReportDto) {
    return this.moderationService.actionReport(id, reviewerId, dto);
  }
}

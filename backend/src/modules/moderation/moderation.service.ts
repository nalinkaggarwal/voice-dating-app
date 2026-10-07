import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import type { Report, ReportContext, ReportReason, ReportStatus } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { reportPriority, type ReportPriority } from './report-priority.util.js';

export interface ReportWithPriority extends Report {
  priority: ReportPriority;
}

export interface ListReportsFilters {
  status?: ReportStatus;
  context?: ReportContext;
  priority?: ReportPriority;
}

@Injectable()
export class ModerationService {
  constructor(private readonly prisma: PrismaService) {}

  // report() and block() are deliberately independent (see the schema's
  // own comment) -- this never creates a Block row, and never requires
  // one to exist first. Self-reports are rejected the same way
  // ConnectionsService.block() rejects self-blocks.
  async report(
    reporterId: string,
    dto: { reportedUserId: string; reason: ReportReason; context: ReportContext; contextId?: string; details?: string },
  ): Promise<Report> {
    if (dto.reportedUserId === reporterId) {
      throw new BadRequestException('Cannot report yourself');
    }
    return this.prisma.report.create({
      data: {
        reporterId,
        reportedUserId: dto.reportedUserId,
        reason: dto.reason,
        context: dto.context,
        contextId: dto.contextId,
        details: dto.details,
      },
    });
  }

  // Priority-ordered queue: HIGH (LIVE_SNAP context or SAFETY_CONCERN
  // reason, see report-priority.util.ts) before NORMAL, oldest-first
  // within each tier (FIFO) -- a report shouldn't sit indefinitely just
  // because newer ones keep landing in the same tier. Priority isn't a
  // DB column, so a `priority` filter is applied after computing it in
  // memory; status/context filter at the query level since those ARE
  // real columns.
  async listReports(filters: ListReportsFilters = {}): Promise<ReportWithPriority[]> {
    const reports = await this.prisma.report.findMany({
      where: {
        ...(filters.status ? { status: filters.status } : {}),
        ...(filters.context ? { context: filters.context } : {}),
      },
    });
    const withPriority = reports
      .map((report) => ({ ...report, priority: reportPriority(report) }))
      .filter((report) => !filters.priority || report.priority === filters.priority);

    return withPriority.sort((a, b) => {
      if (a.priority !== b.priority) return a.priority === 'HIGH' ? -1 : 1;
      return a.createdAt.getTime() - b.createdAt.getTime();
    });
  }

  async getReport(id: string): Promise<ReportWithPriority> {
    const report = await this.prisma.report.findUnique({ where: { id } });
    if (!report) throw new NotFoundException('Report not found');
    return { ...report, priority: reportPriority(report) };
  }

  // Covers assign/action (IN_REVIEW or ACTIONED, + an optional decision
  // note) and dismiss (status DISMISSED) -- both are just "set status,
  // stamp who/when reviewed it," so one method serves both rather than
  // two near-identical ones.
  async actionReport(id: string, reviewerId: string, dto: { status: ReportStatus; decision?: string }): Promise<Report> {
    const existing = await this.prisma.report.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Report not found');
    return this.prisma.report.update({
      where: { id },
      data: { status: dto.status, decision: dto.decision, reviewedAt: new Date(), reviewedBy: reviewerId },
    });
  }
}

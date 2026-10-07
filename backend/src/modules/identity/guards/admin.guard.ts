import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../../shared/prisma/prisma.service.js';
import type { AuthenticatedRequest } from './access-token.guard.js';

// Must run AFTER AccessTokenGuard (needs request.userId already set) --
// @UseGuards(AccessTokenGuard, AdminGuard), in that order. Unlike
// AccessTokenGuard, this one DOES hit the DB: isAdmin is a plain User
// column (see schema's own comment on why -- a manually-set MVP flag,
// not a role/RBAC system), deliberately not encoded into the short-lived
// access token itself, so revoking admin access takes effect on this
// user's very next request rather than only their next login.
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const user = await this.prisma.user.findUnique({ where: { id: request.userId } });
    if (!user?.isAdmin) {
      throw new ForbiddenException('Admin access required');
    }
    return true;
  }
}

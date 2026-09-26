import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { TokenService } from '../token.service.js';

export interface AuthenticatedRequest extends Request {
  userId: string;
}

// Verifies the Authorization: Bearer <accessToken> header on every guarded
// route and attaches the resolved userId to the request. Deliberately
// stateless (no DB lookup) -- that's the whole point of a short-lived
// access token; revocation only ever applies to refresh tokens.
@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(private readonly tokens: TokenService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing bearer token');
    }
    const token = header.slice('Bearer '.length);
    try {
      const payload = this.tokens.verifyAccessToken(token);
      request.userId = payload.sub;
      return true;
    } catch {
      throw new UnauthorizedException('Invalid or expired access token');
    }
  }
}

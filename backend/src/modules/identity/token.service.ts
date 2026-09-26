import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomUUID } from 'node:crypto';
import { PrismaService } from '../../shared/prisma/prisma.service.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number; // access token TTL, in seconds, for the client
}

export interface RotateResult {
  ok: boolean;
  reason?: 'NOT_FOUND' | 'EXPIRED' | 'REVOKED_REUSE_DETECTED';
  tokens?: TokenPair;
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

// Issues/verifies short-lived JWT access tokens and manages the DB-backed
// rotating refresh token chain. IdentityService calls this after a
// successful OTP verification; it never touches OTP or User-creation
// concerns itself.
@Injectable()
export class TokenService {
  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  private accessTokenTtlSeconds(): number {
    // JwtModule is configured with JWT_ACCESS_EXPIRES_IN (e.g. "15m") for
    // signing; this parses the same value to report expiresIn to the
    // client in seconds, without hardcoding it a second time.
    const raw = this.config.get<string>('JWT_ACCESS_EXPIRES_IN', '15m');
    const match = /^(\d+)([smhd])$/.exec(raw);
    if (!match) return 900;
    const n = Number(match[1]);
    const unit = match[2];
    const multiplier = { s: 1, m: 60, h: 3600, d: 86400 }[unit] ?? 60;
    return n * multiplier;
  }

  private refreshTtlMs(): number {
    const raw = this.config.get<string>('JWT_REFRESH_EXPIRES_IN', '30d');
    const match = /^(\d+)([smhd])$/.exec(raw);
    if (!match) return 30 * 86400 * 1000;
    const n = Number(match[1]);
    const unit = match[2];
    const multiplier = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[unit] ?? 86_400_000;
    return n * multiplier;
  }

  private async issueRefreshToken(
    userId: string,
    familyId: string,
    meta: { userAgent?: string; ip?: string } = {},
  ): Promise<string> {
    const raw = randomUUID() + randomUUID(); // 72 chars of entropy, no dashes stripped
    const tokenHash = sha256(raw);
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash,
        familyId,
        expiresAt: new Date(Date.now() + this.refreshTtlMs()),
        userAgent: meta.userAgent,
        ip: meta.ip,
      },
    });
    return raw;
  }

  private signAccessToken(userId: string): string {
    return this.jwt.sign(
      { sub: userId },
      {
        secret: this.config.get<string>('JWT_ACCESS_SECRET'),
        // A number of seconds (not the raw "15m" string) so this always
        // satisfies @nestjs/jwt's expiresIn type regardless of how it's
        // branded upstream, and reuses the same parsing this module
        // already needs for reporting expiresIn back to the client.
        expiresIn: this.accessTokenTtlSeconds(),
      },
    );
  }

  // Called once per successful signup/login OTP verification -- starts a
  // brand new rotation family for this session/device.
  async issueTokenPair(
    userId: string,
    meta: { userAgent?: string; ip?: string } = {},
  ): Promise<TokenPair> {
    const familyId = randomUUID();
    const refreshToken = await this.issueRefreshToken(userId, familyId, meta);
    return {
      accessToken: this.signAccessToken(userId),
      refreshToken,
      expiresIn: this.accessTokenTtlSeconds(),
    };
  }

  // Rotates a refresh token: the presented token is looked up by hash,
  // must be unrevoked and unexpired, then is atomically revoked and
  // replaced by a brand-new token in the SAME family. If the presented
  // token was already revoked (meaning someone is replaying an old,
  // already-rotated-out token -- a strong theft signal, since the
  // legitimate client always uses the newest one), the entire family is
  // revoked and the caller must re-authenticate via OTP.
  async rotateRefreshToken(
    rawToken: string,
    meta: { userAgent?: string; ip?: string } = {},
  ): Promise<RotateResult> {
    const tokenHash = sha256(rawToken);
    const existing = await this.prisma.refreshToken.findUnique({ where: { tokenHash } });

    if (!existing) return { ok: false, reason: 'NOT_FOUND' };

    if (existing.revokedAt) {
      // Reuse of a already-rotated/rotated-out token -- revoke the whole
      // family so a stolen token chain is fully cut off, not just this link.
      await this.prisma.refreshToken.updateMany({
        where: { familyId: existing.familyId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      return { ok: false, reason: 'REVOKED_REUSE_DETECTED' };
    }

    if (existing.expiresAt < new Date()) {
      return { ok: false, reason: 'EXPIRED' };
    }

    const newRawToken = randomUUID() + randomUUID();
    const newTokenHash = sha256(newRawToken);

    // Atomic: revoke the old token and insert its replacement together,
    // so a crash between the two steps can never leave both tokens live
    // (double-spend) or both dead (user locked out for no reason).
    await this.prisma.$transaction([
      this.prisma.refreshToken.update({
        where: { id: existing.id },
        data: { revokedAt: new Date(), replacedBy: newTokenHash },
      }),
      this.prisma.refreshToken.create({
        data: {
          userId: existing.userId,
          tokenHash: newTokenHash,
          familyId: existing.familyId,
          expiresAt: new Date(Date.now() + this.refreshTtlMs()),
          userAgent: meta.userAgent,
          ip: meta.ip,
        },
      }),
    ]);

    return {
      ok: true,
      tokens: {
        accessToken: this.signAccessToken(existing.userId),
        refreshToken: newRawToken,
        expiresIn: this.accessTokenTtlSeconds(),
      },
    };
  }

  // Logout: revoke just the presented token (this device/session only).
  // Idempotent -- revoking an already-revoked or unknown token is a no-op
  // success, not an error, so a retried logout call never fails.
  async revokeRefreshToken(rawToken: string): Promise<void> {
    const tokenHash = sha256(rawToken);
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  verifyAccessToken(token: string): { sub: string } {
    return this.jwt.verify(token, {
      secret: this.config.get<string>('JWT_ACCESS_SECRET'),
    });
  }
}

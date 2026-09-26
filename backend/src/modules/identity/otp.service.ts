import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, randomInt } from 'node:crypto';
import type { OtpChallenge, OtpChannel, OtpPurpose } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import {
  OTP_DELIVERY_PROVIDER,
  type OtpDeliveryProvider,
} from './providers/otp-provider.interface.js';

export interface OtpVerifyResult {
  ok: boolean;
  reason?: 'NOT_FOUND' | 'EXPIRED' | 'ALREADY_CONSUMED' | 'TOO_MANY_ATTEMPTS' | 'WRONG_CODE';
  challenge?: OtpChallenge;
}

// All OTP generation/hashing/verification lives here, isolated from
// IdentityService's account-creation/login orchestration -- this class
// has no idea what a User is, only what a challenge is.
@Injectable()
export class OtpService {
  private readonly codeLength: number;
  private readonly ttlSeconds: number;
  private readonly maxAttempts: number;
  private readonly pepper: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    @Inject(OTP_DELIVERY_PROVIDER) private readonly deliveryProvider: OtpDeliveryProvider,
  ) {
    this.codeLength = Number(this.config.get('OTP_CODE_LENGTH', '6'));
    this.ttlSeconds = Number(this.config.get('OTP_TTL_SECONDS', '300'));
    this.maxAttempts = Number(this.config.get('OTP_MAX_ATTEMPTS', '5'));
    this.pepper = this.config.get<string>('OTP_PEPPER', 'dev-pepper');
  }

  private generateCode(): string {
    // randomInt is CSPRNG-backed (unlike Math.random) -- an OTP is a
    // short-lived credential, so it needs to be unguessable, not just
    // "look random".
    const max = 10 ** this.codeLength;
    return randomInt(0, max).toString().padStart(this.codeLength, '0');
  }

  private hashCode(code: string, challengeId: string): string {
    // challengeId is mixed in as a per-row salt so two challenges that
    // happen to generate the same raw code never produce the same hash.
    return createHash('sha256').update(`${code}:${challengeId}:${this.pepper}`).digest('hex');
  }

  async createChallenge(
    identifier: string,
    channel: OtpChannel,
    purpose: OtpPurpose,
    userId: string | null,
    pendingDateOfBirth?: Date,
    // Creates a real challenge row (so the API response shape is
    // identical either way -- see IdentityService.startLogin) but never
    // actually delivers the code. Used for login attempts against an
    // identifier that isn't registered: the client still gets back a
    // challengeId it can "verify" against, but no one will ever receive
    // a code that could satisfy it, so it can never succeed. This is the
    // ONLY thing that makes not leaking user existence in the response
    // also safe in practice, not just cosmetically vague.
    silent = false,
  ): Promise<{ challengeId: string }> {
    const code = this.generateCode();
    const expiresAt = new Date(Date.now() + this.ttlSeconds * 1000);

    // Two-step create: need the row's own id to salt the hash, so create
    // with a placeholder hash, then patch it. Both writes are on a brand
    // new row no one else can see yet, so no race window matters here.
    const created = await this.prisma.otpChallenge.create({
      data: {
        identifier,
        channel,
        purpose,
        userId: userId ?? undefined,
        codeHash: 'pending',
        expiresAt,
        pendingDateOfBirth,
      },
    });
    const codeHash = this.hashCode(code, created.id);
    await this.prisma.otpChallenge.update({
      where: { id: created.id },
      data: { codeHash },
    });

    if (!silent) {
      await this.deliveryProvider.send(identifier, channel, code);
    }

    return { challengeId: created.id };
  }

  async verifyChallenge(challengeId: string, code: string): Promise<OtpVerifyResult> {
    const challenge = await this.prisma.otpChallenge.findUnique({
      where: { id: challengeId },
    });
    if (!challenge) return { ok: false, reason: 'NOT_FOUND' };
    if (challenge.consumedAt) return { ok: false, reason: 'ALREADY_CONSUMED' };
    if (challenge.expiresAt < new Date()) return { ok: false, reason: 'EXPIRED' };
    if (challenge.attempts >= this.maxAttempts) {
      return { ok: false, reason: 'TOO_MANY_ATTEMPTS' };
    }

    const candidateHash = this.hashCode(code, challenge.id);
    if (candidateHash !== challenge.codeHash) {
      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      return { ok: false, reason: 'WRONG_CODE' };
    }

    const consumed = await this.prisma.otpChallenge.update({
      where: { id: challenge.id },
      data: { consumedAt: new Date() },
    });
    return { ok: true, challenge: consumed };
  }
}

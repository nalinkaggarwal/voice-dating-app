import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { OtpChannel, OtpPurpose } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { OtpService } from './otp.service.js';
import { TokenService, type TokenPair } from './token.service.js';
import { isOldEnough } from './util/age.js';
import type { StartSignupDto } from './dto/start-signup.dto.js';
import type { StartLoginDto } from './dto/start-login.dto.js';
import type { VerifyOtpDto } from './dto/verify-otp.dto.js';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// Loose E.164 check: + then 8-15 digits. Real validation (carrier lookup,
// country-specific formatting) belongs in a phone-number library when a
// real SMS provider gets wired in -- not needed to validate WP1's flow.
const PHONE_RE = /^\+[1-9]\d{7,14}$/;

export interface RequestMeta {
  userAgent?: string;
  ip?: string;
}

@Injectable()
export class IdentityService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly otp: OtpService,
    private readonly tokens: TokenService,
  ) {}

  private assertValidIdentifier(identifier: string, channel: OtpChannel) {
    const pattern = channel === OtpChannel.EMAIL ? EMAIL_RE : PHONE_RE;
    if (!pattern.test(identifier)) {
      throw new BadRequestException(
        channel === OtpChannel.EMAIL
          ? 'identifier is not a valid email address'
          : 'identifier is not a valid E.164 phone number (e.g. +14155552671)',
      );
    }
  }

  private identifierWhere(identifier: string, channel: OtpChannel) {
    return channel === OtpChannel.EMAIL ? { email: identifier } : { phone: identifier };
  }

  // ── Signup ──────────────────────────────────────────────────────────

  async startSignup(dto: StartSignupDto): Promise<{ challengeId: string }> {
    this.assertValidIdentifier(dto.identifier, dto.channel);

    const dateOfBirth = new Date(dto.dateOfBirth);
    if (Number.isNaN(dateOfBirth.getTime())) {
      throw new BadRequestException('dateOfBirth is not a valid date');
    }
    if (!isOldEnough(dateOfBirth)) {
      throw new ForbiddenException('You must be 18 or older to use Lolly.ai');
    }

    const existing = await this.prisma.user.findFirst({
      where: this.identifierWhere(dto.identifier, dto.channel),
    });
    if (existing) {
      throw new ConflictException('An account with this identifier already exists');
    }

    return this.otp.createChallenge(
      dto.identifier,
      dto.channel,
      OtpPurpose.SIGNUP,
      null,
      dateOfBirth,
    );
  }

  async verifySignup(
    dto: VerifyOtpDto,
    meta: RequestMeta = {},
  ): Promise<{ userId: string; tokens: TokenPair }> {
    const result = await this.otp.verifyChallenge(dto.challengeId, dto.code);

    if (!result.ok) {
      // Idempotent-retry handling: a client that never received the
      // response from an earlier successful verify will retry with the
      // same challengeId. That challenge is now ALREADY_CONSUMED, but if
      // it already has a linked user (set at the end of the happy path
      // below), this is that retry, not a genuine replay attempt --
      // issue a fresh token pair for the existing account instead of
      // erroring the client into a stuck state.
      if (result.reason === 'ALREADY_CONSUMED') {
        const challenge = await this.prisma.otpChallenge.findUnique({
          where: { id: dto.challengeId },
        });
        if (challenge?.userId) {
          const tokens = await this.tokens.issueTokenPair(challenge.userId, meta);
          return { userId: challenge.userId, tokens };
        }
      }
      throw new UnauthorizedException(`OTP verification failed: ${result.reason}`);
    }

    const challenge = result.challenge!;
    if (challenge.purpose !== OtpPurpose.SIGNUP) {
      throw new BadRequestException('This challenge is not a signup challenge');
    }

    const user = await this.prisma.user.create({
      data: {
        ...this.identifierWhere(challenge.identifier, challenge.channel),
        dateOfBirth: challenge.pendingDateOfBirth!,
      },
    });

    // Link the challenge to the user it created -- this is what makes the
    // ALREADY_CONSUMED retry path above possible.
    await this.prisma.otpChallenge.update({
      where: { id: challenge.id },
      data: { userId: user.id },
    });

    const tokens = await this.tokens.issueTokenPair(user.id, meta);
    return { userId: user.id, tokens };
  }

  // ── Login ───────────────────────────────────────────────────────────

  async startLogin(dto: StartLoginDto): Promise<{ challengeId: string }> {
    this.assertValidIdentifier(dto.identifier, dto.channel);

    const user = await this.prisma.user.findFirst({
      where: this.identifierWhere(dto.identifier, dto.channel),
    });

    // Deliberately identical response shape whether or not the identifier
    // is registered -- a real challengeId comes back either way. For an
    // unregistered identifier the challenge is created "silent" (no code
    // ever delivered, see OtpService.createChallenge), so it can never be
    // verified successfully, but its existence alone doesn't tell an
    // attacker anything.
    const { challengeId } = await this.otp.createChallenge(
      dto.identifier,
      dto.channel,
      OtpPurpose.LOGIN,
      user?.id ?? null,
      undefined,
      !user,
    );
    return { challengeId };
  }

  async verifyLogin(
    dto: VerifyOtpDto,
    meta: RequestMeta = {},
  ): Promise<{ userId: string; tokens: TokenPair }> {
    const result = await this.otp.verifyChallenge(dto.challengeId, dto.code);
    if (!result.ok) {
      throw new UnauthorizedException(`OTP verification failed: ${result.reason}`);
    }
    const challenge = result.challenge!;
    if (challenge.purpose !== OtpPurpose.LOGIN || !challenge.userId) {
      throw new BadRequestException('This challenge is not a login challenge');
    }

    const tokens = await this.tokens.issueTokenPair(challenge.userId, meta);
    return { userId: challenge.userId, tokens };
  }

  // ── Session management ──────────────────────────────────────────────

  async refresh(rawRefreshToken: string, meta: RequestMeta = {}): Promise<TokenPair> {
    const result = await this.tokens.rotateRefreshToken(rawRefreshToken, meta);
    if (!result.ok) {
      throw new UnauthorizedException(`Refresh failed: ${result.reason}`);
    }
    return result.tokens!;
  }

  async logout(rawRefreshToken: string): Promise<void> {
    await this.tokens.revokeRefreshToken(rawRefreshToken);
  }

  async getUserOrThrow(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }
}

import { Test } from '@nestjs/testing';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { OtpChannel, OtpPurpose } from '@prisma/client';
import { IdentityService } from './identity.service.js';
import { OtpService } from './otp.service.js';
import { TokenService } from './token.service.js';
import { PrismaService } from '../../shared/prisma/prisma.service.js';

describe('IdentityService', () => {
  let service: IdentityService;
  let prisma: any;
  let otp: { createChallenge: any; verifyChallenge: any };
  let tokens: { issueTokenPair: any; rotateRefreshToken: any; revokeRefreshToken: any };

  const ADULT_DOB = '1990-01-01';

  beforeEach(async () => {
    prisma = {
      user: {
        findFirst: vi.fn(async () => null),
        create: vi.fn(async ({ data }: any) => ({ id: 'user-1', ...data })),
        findUnique: vi.fn(async () => null),
      },
      otpChallenge: {
        findUnique: vi.fn(async () => null),
        update: vi.fn(async () => ({})),
      },
    };
    otp = {
      createChallenge: vi.fn(async () => ({ challengeId: 'challenge-1' })),
      verifyChallenge: vi.fn(),
    };
    tokens = {
      issueTokenPair: vi.fn(async () => ({
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresIn: 900,
      })),
      rotateRefreshToken: vi.fn(),
      revokeRefreshToken: vi.fn(async () => {}),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        IdentityService,
        { provide: PrismaService, useValue: prisma },
        { provide: OtpService, useValue: otp },
        { provide: TokenService, useValue: tokens },
      ],
    }).compile();

    service = moduleRef.get(IdentityService);
  });

  describe('startSignup', () => {
    it('rejects under-18 signups (age gate)', async () => {
      await expect(
        service.startSignup({
          channel: OtpChannel.EMAIL,
          identifier: 'teen@example.com',
          dateOfBirth: '2015-01-01',
        }),
      ).rejects.toThrow(ForbiddenException);
      expect(otp.createChallenge).not.toHaveBeenCalled();
    });

    it('rejects a malformed email identifier', async () => {
      await expect(
        service.startSignup({
          channel: OtpChannel.EMAIL,
          identifier: 'not-an-email',
          dateOfBirth: ADULT_DOB,
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a malformed phone identifier', async () => {
      await expect(
        service.startSignup({
          channel: OtpChannel.PHONE,
          identifier: '5551234',
          dateOfBirth: ADULT_DOB,
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects signup for an identifier that already has an account', async () => {
      prisma.user.findFirst.mockResolvedValueOnce({ id: 'existing-user' });
      await expect(
        service.startSignup({
          channel: OtpChannel.EMAIL,
          identifier: 'taken@example.com',
          dateOfBirth: ADULT_DOB,
        }),
      ).rejects.toThrow(ConflictException);
    });

    it('creates a SIGNUP challenge for a valid adult signup', async () => {
      const result = await service.startSignup({
        channel: OtpChannel.EMAIL,
        identifier: 'new@example.com',
        dateOfBirth: ADULT_DOB,
      });
      expect(result.challengeId).toBe('challenge-1');
      expect(otp.createChallenge).toHaveBeenCalledWith(
        'new@example.com',
        OtpChannel.EMAIL,
        OtpPurpose.SIGNUP,
        null,
        expect.any(Date),
      );
    });
  });

  describe('verifySignup', () => {
    it('creates the user and issues tokens on a valid code', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({
        ok: true,
        challenge: {
          id: 'challenge-1',
          purpose: OtpPurpose.SIGNUP,
          identifier: 'new@example.com',
          channel: OtpChannel.EMAIL,
          pendingDateOfBirth: new Date(ADULT_DOB),
        },
      });

      const result = await service.verifySignup({ challengeId: 'challenge-1', code: '123456' });

      expect(prisma.user.create).toHaveBeenCalledOnce();
      expect(prisma.otpChallenge.update).toHaveBeenCalledWith({
        where: { id: 'challenge-1' },
        data: { userId: 'user-1' },
      });
      expect(tokens.issueTokenPair).toHaveBeenCalledWith('user-1', expect.any(Object));
      expect(result.userId).toBe('user-1');
    });

    it('re-issues tokens (not an error) on a retried verify of an already-completed signup', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({ ok: false, reason: 'ALREADY_CONSUMED' });
      prisma.otpChallenge.findUnique.mockResolvedValueOnce({
        id: 'challenge-1',
        userId: 'user-1',
      });

      const result = await service.verifySignup({ challengeId: 'challenge-1', code: '123456' });

      expect(result.userId).toBe('user-1');
      expect(tokens.issueTokenPair).toHaveBeenCalledWith('user-1', expect.any(Object));
      // Must NOT attempt to create a second user for the retry.
      expect(prisma.user.create).not.toHaveBeenCalled();
    });

    it('rejects a genuine replay (consumed, no linked user yet)', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({ ok: false, reason: 'ALREADY_CONSUMED' });
      prisma.otpChallenge.findUnique.mockResolvedValueOnce({ id: 'challenge-1', userId: null });

      await expect(
        service.verifySignup({ challengeId: 'challenge-1', code: '123456' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('rejects a wrong code', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({ ok: false, reason: 'WRONG_CODE' });
      await expect(
        service.verifySignup({ challengeId: 'challenge-1', code: '000000' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('rejects a LOGIN-purpose challenge presented to the signup endpoint', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({
        ok: true,
        challenge: { id: 'challenge-1', purpose: OtpPurpose.LOGIN },
      });
      await expect(
        service.verifySignup({ challengeId: 'challenge-1', code: '123456' }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('startLogin', () => {
    it('returns a real, usable challengeId for a registered identifier', async () => {
      prisma.user.findFirst.mockResolvedValueOnce({ id: 'user-1' });
      const result = await service.startLogin({
        channel: OtpChannel.EMAIL,
        identifier: 'user@example.com',
      });
      expect(result.challengeId).toBe('challenge-1');
      expect(otp.createChallenge).toHaveBeenCalledWith(
        'user@example.com',
        OtpChannel.EMAIL,
        OtpPurpose.LOGIN,
        'user-1',
        undefined,
        false, // not silent -- a real code gets sent
      );
    });

    it('returns the SAME response shape for an unregistered identifier (no enumeration)', async () => {
      prisma.user.findFirst.mockResolvedValueOnce(null);
      const result = await service.startLogin({
        channel: OtpChannel.EMAIL,
        identifier: 'ghost@example.com',
      });
      expect(result.challengeId).toBe('challenge-1'); // same shape as the registered case
      expect(otp.createChallenge).toHaveBeenCalledWith(
        'ghost@example.com',
        OtpChannel.EMAIL,
        OtpPurpose.LOGIN,
        null,
        undefined,
        true, // silent -- no code is ever actually deliverable
      );
    });
  });

  describe('verifyLogin', () => {
    it('issues tokens for a valid login code', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({
        ok: true,
        challenge: { id: 'challenge-1', purpose: OtpPurpose.LOGIN, userId: 'user-1' },
      });
      const result = await service.verifyLogin({ challengeId: 'challenge-1', code: '123456' });
      expect(result.userId).toBe('user-1');
      expect(tokens.issueTokenPair).toHaveBeenCalledWith('user-1', expect.any(Object));
    });

    it('rejects a SIGNUP-purpose challenge presented to the login endpoint', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({
        ok: true,
        challenge: { id: 'challenge-1', purpose: OtpPurpose.SIGNUP, userId: null },
      });
      await expect(
        service.verifyLogin({ challengeId: 'challenge-1', code: '123456' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a silently-created (never-deliverable) challenge -- it can never have a right code', async () => {
      otp.verifyChallenge.mockResolvedValueOnce({ ok: false, reason: 'WRONG_CODE' });
      await expect(
        service.verifyLogin({ challengeId: 'challenge-1', code: 'anything' }),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  describe('refresh / logout', () => {
    it('returns fresh tokens on a valid rotation', async () => {
      tokens.rotateRefreshToken.mockResolvedValueOnce({
        ok: true,
        tokens: { accessToken: 'a2', refreshToken: 'r2', expiresIn: 900 },
      });
      const result = await service.refresh('old-refresh-token');
      expect(result.accessToken).toBe('a2');
    });

    it('throws on a failed rotation (expired/reused/unknown)', async () => {
      tokens.rotateRefreshToken.mockResolvedValueOnce({
        ok: false,
        reason: 'REVOKED_REUSE_DETECTED',
      });
      await expect(service.refresh('stolen-token')).rejects.toThrow(UnauthorizedException);
    });

    it('logout delegates to TokenService.revokeRefreshToken', async () => {
      await service.logout('some-token');
      expect(tokens.revokeRefreshToken).toHaveBeenCalledWith('some-token');
    });
  });
});

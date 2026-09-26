import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { OtpChannel, OtpPurpose } from '@prisma/client';
import { OtpService } from './otp.service.js';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { OTP_DELIVERY_PROVIDER } from './providers/otp-provider.interface.js';

function makePrismaMock() {
  const rows = new Map<string, any>();
  let counter = 0;
  return {
    otpChallenge: {
      create: vi.fn(async ({ data }: any) => {
        const id = `challenge-${++counter}`;
        const row = { id, attempts: 0, consumedAt: null, ...data };
        rows.set(id, row);
        return row;
      }),
      update: vi.fn(async ({ where, data }: any) => {
        const row = rows.get(where.id);
        const updated = {
          ...row,
          ...data,
          attempts:
            data.attempts?.increment !== undefined
              ? row.attempts + data.attempts.increment
              : (data.attempts ?? row.attempts),
        };
        rows.set(where.id, updated);
        return updated;
      }),
      findUnique: vi.fn(async ({ where }: any) => rows.get(where.id) ?? null),
    },
    __rows: rows,
  };
}

describe('OtpService', () => {
  let service: OtpService;
  let prisma: ReturnType<typeof makePrismaMock>;
  let deliveryProvider: { send: ReturnType<typeof vi.fn> };

  beforeEach(async () => {
    prisma = makePrismaMock();
    deliveryProvider = { send: vi.fn(async () => {}) };

    const moduleRef = await Test.createTestingModule({
      providers: [
        OtpService,
        { provide: PrismaService, useValue: prisma },
        { provide: OTP_DELIVERY_PROVIDER, useValue: deliveryProvider },
        {
          provide: ConfigService,
          useValue: {
            get: (key: string, fallback?: string) =>
              ({
                OTP_CODE_LENGTH: '6',
                OTP_TTL_SECONDS: '300',
                OTP_MAX_ATTEMPTS: '3',
                OTP_PEPPER: 'test-pepper',
              })[key] ?? fallback,
          },
        },
      ],
    }).compile();

    service = moduleRef.get(OtpService);
  });

  it('creates a challenge and delivers the code', async () => {
    const { challengeId } = await service.createChallenge(
      'user@example.com',
      OtpChannel.EMAIL,
      OtpPurpose.SIGNUP,
      null,
    );
    expect(challengeId).toBeTruthy();
    expect(deliveryProvider.send).toHaveBeenCalledOnce();
    expect(deliveryProvider.send).toHaveBeenCalledWith(
      'user@example.com',
      OtpChannel.EMAIL,
      expect.stringMatching(/^\d{6}$/),
    );
  });

  it('does not deliver anything when silent=true', async () => {
    await service.createChallenge(
      'nobody@example.com',
      OtpChannel.EMAIL,
      OtpPurpose.LOGIN,
      null,
      undefined,
      true,
    );
    expect(deliveryProvider.send).not.toHaveBeenCalled();
  });

  it('verifies the correct code successfully, exactly once', async () => {
    let sentCode = '';
    deliveryProvider.send.mockImplementation(async (_id, _ch, code) => {
      sentCode = code;
    });
    const { challengeId } = await service.createChallenge(
      'user@example.com',
      OtpChannel.EMAIL,
      OtpPurpose.SIGNUP,
      null,
    );

    const first = await service.verifyChallenge(challengeId, sentCode);
    expect(first.ok).toBe(true);
    expect(first.challenge?.consumedAt).toBeTruthy();

    const second = await service.verifyChallenge(challengeId, sentCode);
    expect(second.ok).toBe(false);
    expect(second.reason).toBe('ALREADY_CONSUMED');
  });

  it('rejects a wrong code without consuming the challenge', async () => {
    const { challengeId } = await service.createChallenge(
      'user@example.com',
      OtpChannel.EMAIL,
      OtpPurpose.SIGNUP,
      null,
    );
    const result = await service.verifyChallenge(challengeId, '000000');
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('WRONG_CODE');
  });

  it('locks out after OTP_MAX_ATTEMPTS wrong attempts', async () => {
    const { challengeId } = await service.createChallenge(
      'user@example.com',
      OtpChannel.EMAIL,
      OtpPurpose.SIGNUP,
      null,
    );
    await service.verifyChallenge(challengeId, '000000');
    await service.verifyChallenge(challengeId, '000000');
    await service.verifyChallenge(challengeId, '000000');
    const fourth = await service.verifyChallenge(challengeId, '000000');
    expect(fourth.reason).toBe('TOO_MANY_ATTEMPTS');
  });

  it('rejects an expired challenge', async () => {
    let sentCode = '';
    deliveryProvider.send.mockImplementation(async (_id, _ch, code) => {
      sentCode = code;
    });
    const { challengeId } = await service.createChallenge(
      'user@example.com',
      OtpChannel.EMAIL,
      OtpPurpose.SIGNUP,
      null,
    );
    // Force it into the past, same way an elapsed real TTL would.
    const row = prisma.__rows.get(challengeId);
    row.expiresAt = new Date(Date.now() - 1000);

    const result = await service.verifyChallenge(challengeId, sentCode);
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('EXPIRED');
  });

  it('rejects an unknown challenge id', async () => {
    const result = await service.verifyChallenge('does-not-exist', '123456');
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('NOT_FOUND');
  });
});

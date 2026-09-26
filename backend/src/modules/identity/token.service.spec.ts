import { Test } from '@nestjs/testing';
import { JwtModule } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { TokenService } from './token.service.js';
import { PrismaService } from '../../shared/prisma/prisma.service.js';

function makePrismaMock() {
  const tokens = new Map<string, any>();
  let counter = 0;
  return {
    refreshToken: {
      create: vi.fn(async ({ data }: any) => {
        const id = `rt-${++counter}`;
        const row = { id, revokedAt: null, replacedBy: null, ...data };
        tokens.set(data.tokenHash, row);
        return row;
      }),
      findUnique: vi.fn(async ({ where }: any) => tokens.get(where.tokenHash) ?? null),
      update: vi.fn(async ({ where, data }: any) => {
        const row = [...tokens.values()].find((t) => t.id === where.id);
        Object.assign(row, data);
        return row;
      }),
      updateMany: vi.fn(async ({ where, data }: any) => {
        let count = 0;
        for (const row of tokens.values()) {
          const familyMatches = where.familyId ? row.familyId === where.familyId : true;
          const hashMatches = where.tokenHash ? row.tokenHash === where.tokenHash : true;
          const notRevoked = where.revokedAt === null ? row.revokedAt === null : true;
          if (familyMatches && hashMatches && notRevoked) {
            Object.assign(row, data);
            count++;
          }
        }
        return { count };
      }),
    },
    $transaction: vi.fn(async (ops: Promise<any>[]) => Promise.all(ops)),
    __tokens: tokens,
  };
}

describe('TokenService', () => {
  let service: TokenService;
  let prisma: ReturnType<typeof makePrismaMock>;

  const config = {
    get: (key: string, fallback?: string) =>
      ({
        JWT_ACCESS_SECRET: 'test-access-secret',
        JWT_ACCESS_EXPIRES_IN: '15m',
        JWT_REFRESH_EXPIRES_IN: '30d',
      })[key] ?? fallback,
  };

  beforeEach(async () => {
    prisma = makePrismaMock();
    const moduleRef = await Test.createTestingModule({
      imports: [JwtModule.register({})],
      providers: [
        TokenService,
        { provide: PrismaService, useValue: prisma },
        { provide: ConfigService, useValue: config },
      ],
    }).compile();
    service = moduleRef.get(TokenService);
  });

  it('issues a verifiable access token and a refresh token', async () => {
    const pair = await service.issueTokenPair('user-1');
    expect(pair.accessToken).toBeTruthy();
    expect(pair.refreshToken).toBeTruthy();
    expect(pair.expiresIn).toBe(15 * 60);

    const payload = service.verifyAccessToken(pair.accessToken);
    expect(payload.sub).toBe('user-1');
  });

  it('rotates a valid refresh token and revokes the old one', async () => {
    const pair = await service.issueTokenPair('user-1');
    const result = await service.rotateRefreshToken(pair.refreshToken);

    expect(result.ok).toBe(true);
    expect(result.tokens!.refreshToken).not.toBe(pair.refreshToken);

    // Old token must now be unusable.
    const secondAttempt = await service.rotateRefreshToken(pair.refreshToken);
    expect(secondAttempt.ok).toBe(false);
    expect(secondAttempt.reason).toBe('REVOKED_REUSE_DETECTED');
  });

  it('revokes the WHOLE family on reuse of an already-rotated token', async () => {
    const pair = await service.issueTokenPair('user-1');
    const rotated = await service.rotateRefreshToken(pair.refreshToken);
    expect(rotated.ok).toBe(true);

    // Replay the original (now-revoked) token -- theft signal.
    await service.rotateRefreshToken(pair.refreshToken);

    // The token issued by the (legitimate) rotation must ALSO now be dead,
    // since reuse revokes the entire family, not just the replayed link.
    const afterFamilyRevoke = await service.rotateRefreshToken(rotated.tokens!.refreshToken);
    expect(afterFamilyRevoke.ok).toBe(false);
    expect(afterFamilyRevoke.reason).toBe('REVOKED_REUSE_DETECTED');
  });

  it('rejects an unknown refresh token', async () => {
    const result = await service.rotateRefreshToken('not-a-real-token');
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('NOT_FOUND');
  });

  it('rejects an expired refresh token', async () => {
    const pair = await service.issueTokenPair('user-1');
    const row = [...prisma.__tokens.values()][0];
    row.expiresAt = new Date(Date.now() - 1000);

    const result = await service.rotateRefreshToken(pair.refreshToken);
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('EXPIRED');
  });

  it('logout revokes the token; a second logout call is a harmless no-op', async () => {
    const pair = await service.issueTokenPair('user-1');
    await service.revokeRefreshToken(pair.refreshToken);
    await expect(service.revokeRefreshToken(pair.refreshToken)).resolves.not.toThrow();

    const afterLogout = await service.rotateRefreshToken(pair.refreshToken);
    expect(afterLogout.ok).toBe(false);
    expect(afterLogout.reason).toBe('REVOKED_REUSE_DETECTED');
  });
});

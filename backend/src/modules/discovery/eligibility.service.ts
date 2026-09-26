import { Injectable } from '@nestjs/common';
import type { ConnectionStatus, Gender, Profile, Preference, User } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { checkEligibility, type EligibilityCandidate } from './eligibility.util.js';

type UserWithProfilePreference = User & { profile: Profile | null; preference: Preference | null };

function toEligibilityCandidate(
  user: UserWithProfilePreference,
  existingConnectionStatus: ConnectionStatus | null = null,
): EligibilityCandidate {
  return {
    userId: user.id,
    userStatus: user.status,
    dateOfBirth: user.dateOfBirth,
    gender: (user.profile?.gender as Gender | null) ?? null,
    genderInterest: user.preference?.genderInterest ?? [],
    ageMin: user.preference?.ageMin ?? null,
    ageMax: user.preference?.ageMax ?? null,
    geohash: user.profile?.geohash ?? null,
    maxDistanceKm: user.preference?.maxDistanceKm ?? null,
    relationshipIntent: user.preference?.relationshipIntent ?? null,
    existingConnectionStatus,
  };
}

/**
 * DB-querying wrapper around eligibility.util.ts's pure filter -- the
 * filter LOGIC lives there (and is unit-tested there with no DB at all);
 * this class is only responsible for fetching the data it needs and
 * shaping it into EligibilityCandidate.
 *
 * WP3 scope note: fetches every ACTIVE user (minus the viewer and anyone
 * already connected) and filters in memory. Fine for an early user base;
 * as it grows, the DB query itself should narrow the candidate pool
 * (e.g. a geo index instead of a full scan + in-memory haversine) --
 * that's a scaling concern, not a correctness one, and out of scope here.
 */
@Injectable()
export class EligibilityService {
  constructor(private readonly prisma: PrismaService) {}

  /** Every eligible candidate for viewerId, per the hard filters in
   * eligibility.util.ts. Returns [] (not an error) if the viewer has no
   * User row -- callers decide whether that's worth logging. */
  async eligibleCandidatesFor(viewerId: string): Promise<EligibilityCandidate[]> {
    const viewerUser = await this.prisma.user.findUnique({
      where: { id: viewerId },
      include: { profile: true, preference: true },
    });
    if (!viewerUser) return [];
    const viewer = toEligibilityCandidate(viewerUser);

    const [activeUsers, existingConnections] = await Promise.all([
      this.prisma.user.findMany({
        where: { status: 'ACTIVE', id: { not: viewerId } },
        include: { profile: true, preference: true },
      }),
      this.prisma.connection.findMany({
        where: { OR: [{ userAId: viewerId }, { userBId: viewerId }] },
      }),
    ]);

    const statusByOtherUserId = new Map<string, ConnectionStatus>();
    for (const conn of existingConnections) {
      const otherId = conn.userAId === viewerId ? conn.userBId : conn.userAId;
      statusByOtherUserId.set(otherId, conn.status);
    }

    const pool = activeUsers.map((user) =>
      toEligibilityCandidate(user, statusByOtherUserId.get(user.id) ?? null),
    );

    return pool.filter((candidate) => checkEligibility(viewer, candidate).eligible);
  }
}

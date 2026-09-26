import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { StorageService } from '../../shared/storage/storage.service.js';
import { advanceUserStatus } from '../../shared/onboarding/advance-status.util.js';

const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

@Injectable()
export class ProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  async submitBasicInfo(userId: string, data: { displayName: string; geohash?: string }) {
    const profile = await this.prisma.profile.upsert({
      where: { userId },
      create: { userId, displayName: data.displayName, geohash: data.geohash },
      update: { displayName: data.displayName, geohash: data.geohash },
    });
    await advanceUserStatus(this.prisma, userId, ['ACCOUNT_CREATED'], 'BASIC_INFO_DONE');
    return profile;
  }

  async submitPreferences(
    userId: string,
    data: { genderInterest: string[]; ageMin?: number; ageMax?: number; maxDistanceKm?: number },
  ) {
    const preference = await this.prisma.preference.upsert({
      where: { userId },
      create: { userId, ...data },
      update: { ...data },
    });
    await advanceUserStatus(this.prisma, userId, ['BASIC_INFO_DONE'], 'PREFERENCES_DONE');
    return preference;
  }

  async submitIntent(userId: string, relationshipIntent: string) {
    const preference = await this.prisma.preference.upsert({
      where: { userId },
      // relationshipIntent is asked as its own onboarding step, but the
      // brief's schema puts it on the same Preference row as
      // genderInterest/age/distance -- a user could in principle hit
      // this before submitPreferences (client shouldn't allow that, but
      // the API needs a valid create() either way), so genderInterest
      // defaults to empty rather than making it required here too.
      create: { userId, genderInterest: [], relationshipIntent },
      update: { relationshipIntent },
    });
    await advanceUserStatus(this.prisma, userId, ['PREFERENCES_DONE'], 'INTENT_DONE');
    return preference;
  }

  async requestPhotoUploadUrl(contentType: string): Promise<{ uploadUrl: string; key: string }> {
    const extension = EXTENSION_BY_CONTENT_TYPE[contentType] ?? 'bin';
    const key = this.storage.generateKey('photo', extension);
    const uploadUrl = await this.storage.getUploadUrl(key, contentType);
    return { uploadUrl, key };
  }

  // Photo is the last onboarding step in the brief's own flow diagram
  // ("photo upload -> ACTIVE", no distinct action in between), so
  // completing it chains straight through PHOTO_UPLOADED to ACTIVE --
  // both advances still go through the same guarded, idempotent helper.
  // Photo does NOT become visible to other users here -- that's gated by
  // the Connections state machine later, per the brief; this only wires
  // up storage + linkage.
  async completePhotoUpload(userId: string, key: string) {
    const profile = await this.prisma.profile.update({
      where: { userId },
      data: { photoUrl: key },
    });
    await advanceUserStatus(this.prisma, userId, ['AI_REVIEW_DONE'], 'PHOTO_UPLOADED');
    await advanceUserStatus(this.prisma, userId, ['PHOTO_UPLOADED'], 'ACTIVE');
    return profile;
  }
}

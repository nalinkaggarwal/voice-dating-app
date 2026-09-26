import { ProfileService } from './profile.service.js';

describe('ProfileService', () => {
  let service: ProfileService;
  let prisma: any;
  let storage: { generateKey: ReturnType<typeof vi.fn>; getUploadUrl: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    prisma = {
      profile: {
        upsert: vi.fn(async ({ create }: any) => ({ id: 'profile-1', ...create })),
        update: vi.fn(async ({ data }: any) => ({ id: 'profile-1', ...data })),
      },
      preference: {
        upsert: vi.fn(async ({ create }: any) => ({ id: 'pref-1', ...create })),
      },
      user: { updateMany: vi.fn(async () => ({ count: 1 })) },
    };
    storage = {
      generateKey: vi.fn(() => 'photo/abc.jpg'),
      getUploadUrl: vi.fn(async () => 'https://s3.example.com/signed-put-photo'),
    };
    service = new ProfileService(prisma, storage as any);
  });

  describe('submitBasicInfo', () => {
    it('upserts the Profile and advances ACCOUNT_CREATED -> BASIC_INFO_DONE', async () => {
      await service.submitBasicInfo('user-1', { displayName: 'Alex', geohash: 'u4pruy' });

      expect(prisma.profile.upsert).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        create: { userId: 'user-1', displayName: 'Alex', geohash: 'u4pruy' },
        update: { displayName: 'Alex', geohash: 'u4pruy' },
      });
      expect(prisma.user.updateMany).toHaveBeenCalledWith({
        where: { id: 'user-1', status: { in: ['ACCOUNT_CREATED'] } },
        data: { status: 'BASIC_INFO_DONE' },
      });
    });
  });

  describe('submitPreferences', () => {
    it('upserts Preference and advances BASIC_INFO_DONE -> PREFERENCES_DONE', async () => {
      await service.submitPreferences('user-1', { genderInterest: ['WOMEN'], ageMin: 25, ageMax: 35 });

      expect(prisma.preference.upsert).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        create: { userId: 'user-1', genderInterest: ['WOMEN'], ageMin: 25, ageMax: 35 },
        update: { genderInterest: ['WOMEN'], ageMin: 25, ageMax: 35 },
      });
      expect(prisma.user.updateMany).toHaveBeenCalledWith({
        where: { id: 'user-1', status: { in: ['BASIC_INFO_DONE'] } },
        data: { status: 'PREFERENCES_DONE' },
      });
    });
  });

  describe('submitIntent', () => {
    it('upserts relationshipIntent and advances PREFERENCES_DONE -> INTENT_DONE', async () => {
      await service.submitIntent('user-1', 'LONG_TERM');

      expect(prisma.preference.upsert).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        create: { userId: 'user-1', genderInterest: [], relationshipIntent: 'LONG_TERM' },
        update: { relationshipIntent: 'LONG_TERM' },
      });
      expect(prisma.user.updateMany).toHaveBeenCalledWith({
        where: { id: 'user-1', status: { in: ['PREFERENCES_DONE'] } },
        data: { status: 'INTENT_DONE' },
      });
    });
  });

  describe('photo upload', () => {
    it('requestPhotoUploadUrl generates a key and signed URL', async () => {
      const result = await service.requestPhotoUploadUrl('image/jpeg');
      expect(result).toEqual({
        uploadUrl: 'https://s3.example.com/signed-put-photo',
        key: 'photo/abc.jpg',
      });
    });

    it('completePhotoUpload sets photoUrl and chains AI_REVIEW_DONE -> PHOTO_UPLOADED -> ACTIVE', async () => {
      await service.completePhotoUpload('user-1', 'photo/abc.jpg');

      expect(prisma.profile.update).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        data: { photoUrl: 'photo/abc.jpg' },
      });
      expect(prisma.user.updateMany).toHaveBeenNthCalledWith(1, {
        where: { id: 'user-1', status: { in: ['AI_REVIEW_DONE'] } },
        data: { status: 'PHOTO_UPLOADED' },
      });
      expect(prisma.user.updateMany).toHaveBeenNthCalledWith(2, {
        where: { id: 'user-1', status: { in: ['PHOTO_UPLOADED'] } },
        data: { status: 'ACTIVE' },
      });
    });
  });
});

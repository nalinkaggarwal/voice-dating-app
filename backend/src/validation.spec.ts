import { ArgumentMetadata, BadRequestException } from '@nestjs/common';
import { MessageType, OtpChannel, ReportContext, ReportReason } from '@prisma/client';
import { createValidationPipe } from './validation.js';
import { SendMessageDto } from './modules/messaging/dto/send-message.dto.js';
import { StartSignupDto } from './modules/identity/dto/start-signup.dto.js';
import { PreferencesDto } from './modules/profile/dto/preferences.dto.js';
import { BlockUserDto } from './modules/connections/dto/block-user.dto.js';
import { CreateReportDto } from './modules/moderation/dto/create-report.dto.js';
import { RequestVoiceUploadUrlDto } from './modules/ai-profile/dto/request-upload-url.dto.js';

// Exercises the exact pipe main.ts registers (not a fresh ValidationPipe
// with guessed options) against the real DTO classes, the way Nest would
// for an @Body() param. The per-module unit tests construct services
// directly and never go through the HTTP layer, so without this nothing
// proves the decorators every DTO carries actually reject anything.
const pipe = createValidationPipe();

function bodyOf(metatype: new () => unknown): ArgumentMetadata {
  return { type: 'body', metatype: metatype as never };
}

async function rejectionMessages(value: unknown, metatype: new () => unknown): Promise<string[]> {
  try {
    await pipe.transform(value, bodyOf(metatype));
  } catch (err) {
    expect(err).toBeInstanceOf(BadRequestException);
    const response = (err as BadRequestException).getResponse() as { message: string | string[] };
    return Array.isArray(response.message) ? response.message : [response.message];
  }
  throw new Error('expected the pipe to reject this body');
}

describe('createValidationPipe', () => {
  describe('SendMessageDto (WP5)', () => {
    it('accepts a TEXT message with textContent and returns a class instance', async () => {
      const out = (await pipe.transform(
        { type: MessageType.TEXT, textContent: 'hi' },
        bodyOf(SendMessageDto),
      )) as SendMessageDto;
      expect(out).toBeInstanceOf(SendMessageDto);
      expect(out.textContent).toBe('hi');
    });

    it('rejects a TEXT message with no textContent', async () => {
      const messages = await rejectionMessages({ type: MessageType.TEXT }, SendMessageDto);
      expect(messages.join(' ')).toMatch(/textContent/);
    });

    it('rejects a VOICE message longer than 60s', async () => {
      const messages = await rejectionMessages(
        { type: MessageType.VOICE, audioUrl: 'https://x/y.webm', audioDurationSec: 61 },
        SendMessageDto,
      );
      expect(messages.join(' ')).toMatch(/audioDurationSec/);
    });

    it('rejects an unknown type', async () => {
      const messages = await rejectionMessages({ type: 'VIDEO', textContent: 'x' }, SendMessageDto);
      expect(messages.join(' ')).toMatch(/type/);
    });
  });

  describe('StartSignupDto (WP1) -- what the mobile client actually sends', () => {
    it('accepts a date-only ISO string for dateOfBirth (auth_repository.dart sends YYYY-MM-DD)', async () => {
      const out = await pipe.transform(
        { channel: OtpChannel.EMAIL, identifier: 'a@b.co', dateOfBirth: '2000-01-31' },
        bodyOf(StartSignupDto),
      );
      expect(out).toBeInstanceOf(StartSignupDto);
    });

    it('rejects a malformed dateOfBirth', async () => {
      const messages = await rejectionMessages(
        { channel: OtpChannel.EMAIL, identifier: 'a@b.co', dateOfBirth: '31/01/2000' },
        StartSignupDto,
      );
      expect(messages.join(' ')).toMatch(/dateOfBirth/);
    });

    it('rejects an unknown channel', async () => {
      const messages = await rejectionMessages(
        { channel: 'CARRIER_PIGEON', identifier: 'a@b.co', dateOfBirth: '2000-01-31' },
        StartSignupDto,
      );
      expect(messages.join(' ')).toMatch(/channel/);
    });
  });

  describe('PreferencesDto (WP2)', () => {
    it('accepts the optional fields omitted (onboarding_repository.dart omits nulls)', async () => {
      const out = (await pipe.transform({ genderInterest: ['WOMEN'] }, bodyOf(PreferencesDto))) as PreferencesDto;
      expect(out.ageMin).toBeUndefined();
    });

    it('rejects ageMin below 18', async () => {
      const messages = await rejectionMessages({ genderInterest: ['WOMEN'], ageMin: 17 }, PreferencesDto);
      expect(messages.join(' ')).toMatch(/ageMin/);
    });

    it('rejects a numeric string for ageMin -- implicit conversion is off on purpose', async () => {
      const messages = await rejectionMessages({ genderInterest: ['WOMEN'], ageMin: '25' }, PreferencesDto);
      expect(messages.join(' ')).toMatch(/ageMin/);
    });

    it('rejects an empty genderInterest list', async () => {
      const messages = await rejectionMessages({ genderInterest: [] }, PreferencesDto);
      expect(messages.join(' ')).toMatch(/genderInterest/);
    });
  });

  describe('whitelist', () => {
    it('strips properties no DTO decorator declares instead of passing them to the service', async () => {
      const out = await pipe.transform(
        { blockedUserId: 'u2', isAdmin: true, anythingElse: 1 },
        bodyOf(BlockUserDto),
      );
      expect(out).toEqual(expect.objectContaining({ blockedUserId: 'u2' }));
      expect(out).not.toHaveProperty('isAdmin');
      expect(out).not.toHaveProperty('anythingElse');
    });

    it('does not 400 on an extra property (forbidNonWhitelisted stays off for client-version skew)', async () => {
      await expect(
        pipe.transform({ blockedUserId: 'u2', extra: 'x' }, bodyOf(BlockUserDto)),
      ).resolves.toBeDefined();
    });
  });

  describe('WP6 DTOs now enforced by the pipe, not only by hand in the service/controller', () => {
    it('rejects an empty blockedUserId', async () => {
      const messages = await rejectionMessages({ blockedUserId: '' }, BlockUserDto);
      expect(messages.join(' ')).toMatch(/blockedUserId/);
    });

    it('rejects a report with an unknown reason', async () => {
      const messages = await rejectionMessages(
        { reportedUserId: 'u2', reason: 'BAD_VIBES', context: ReportContext.PROFILE },
        CreateReportDto,
      );
      expect(messages.join(' ')).toMatch(/reason/);
    });

    it('accepts a full valid report', async () => {
      const out = await pipe.transform(
        {
          reportedUserId: 'u2',
          reason: ReportReason.HARASSMENT,
          context: ReportContext.MESSAGE,
          contextId: 'm1',
          details: 'said something awful',
        },
        bodyOf(CreateReportDto),
      );
      expect(out).toBeInstanceOf(CreateReportDto);
    });
  });

  describe('error shape', () => {
    it('reports one message per failed property (stopAtFirstError) so the client-side join stays readable', async () => {
      // contentType fails both @IsString and @IsIn when it is a number;
      // stopAtFirstError should surface exactly one of them.
      const messages = await rejectionMessages({ contentType: 42 }, RequestVoiceUploadUrlDto);
      expect(messages).toHaveLength(1);
    });
  });
});

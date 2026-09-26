import type { OtpChannel } from '@prisma/client';

// Real SMS/email providers (Twilio, SES, etc.) get wired in behind this
// interface later -- nothing in IdentityService/OtpService should ever
// import a concrete provider directly.
export interface OtpDeliveryProvider {
  send(identifier: string, channel: OtpChannel, code: string): Promise<void>;
}

export const OTP_DELIVERY_PROVIDER = 'OTP_DELIVERY_PROVIDER';

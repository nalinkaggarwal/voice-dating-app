import { Injectable, Logger } from '@nestjs/common';
import type { OtpChannel } from '@prisma/client';
import type { OtpDeliveryProvider } from './otp-provider.interface.js';

// WP1 dev stub: logs the code instead of sending a real SMS/email. Swap
// for a real Twilio/SES-backed provider (same interface) when WP4-era
// work needs actual delivery -- nothing else in the identity module
// changes when that happens.
@Injectable()
export class ConsoleOtpProvider implements OtpDeliveryProvider {
  private readonly logger = new Logger(ConsoleOtpProvider.name);

  async send(identifier: string, channel: OtpChannel, code: string): Promise<void> {
    this.logger.log(`[DEV OTP] ${channel} -> ${identifier}: ${code}`);
  }
}

import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { IdentityController } from './identity.controller.js';
import { IdentityService } from './identity.service.js';
import { OtpService } from './otp.service.js';
import { TokenService } from './token.service.js';
import { AccessTokenGuard } from './guards/access-token.guard.js';
import { ConsoleOtpProvider } from './providers/console-otp.provider.js';
import { OTP_DELIVERY_PROVIDER } from './providers/otp-provider.interface.js';

@Module({
  imports: [JwtModule.register({})], // secret/expiry passed per-call in TokenService
  controllers: [IdentityController],
  providers: [
    IdentityService,
    OtpService,
    TokenService,
    AccessTokenGuard,
    { provide: OTP_DELIVERY_PROVIDER, useClass: ConsoleOtpProvider },
  ],
  exports: [TokenService, AccessTokenGuard],
})
export class IdentityModule {}

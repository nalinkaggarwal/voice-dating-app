import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { IdentityService } from './identity.service.js';
import { StartSignupDto } from './dto/start-signup.dto.js';
import { StartLoginDto } from './dto/start-login.dto.js';
import { VerifyOtpDto } from './dto/verify-otp.dto.js';
import { RefreshTokenDto } from './dto/refresh-token.dto.js';
import { AccessTokenGuard } from './guards/access-token.guard.js';
import { CurrentUserId } from './decorators/current-user.decorator.js';

function metaFrom(req: Request) {
  return { userAgent: req.headers['user-agent'], ip: req.ip };
}

@Controller('auth')
export class IdentityController {
  constructor(private readonly identity: IdentityService) {}

  @Post('signup/start')
  startSignup(@Body() dto: StartSignupDto) {
    return this.identity.startSignup(dto);
  }

  @Post('signup/verify')
  async verifySignup(@Body() dto: VerifyOtpDto, @Req() req: Request) {
    return this.identity.verifySignup(dto, metaFrom(req));
  }

  @Post('login/start')
  async startLogin(@Body() dto: StartLoginDto) {
    // challengeId is always real and usable -- see IdentityService
    // .startLogin's comment on why this doesn't leak identifier existence.
    return this.identity.startLogin(dto);
  }

  @Post('login/verify')
  async verifyLogin(@Body() dto: VerifyOtpDto, @Req() req: Request) {
    return this.identity.verifyLogin(dto, metaFrom(req));
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshTokenDto, @Req() req: Request) {
    return this.identity.refresh(dto.refreshToken, metaFrom(req));
  }

  @Post('logout')
  async logout(@Body() dto: RefreshTokenDto) {
    await this.identity.logout(dto.refreshToken);
    return { message: 'Logged out' };
  }

  @UseGuards(AccessTokenGuard)
  @Get('me')
  async me(@CurrentUserId() userId: string) {
    const user = await this.identity.getUserOrThrow(userId);
    return {
      id: user.id,
      email: user.email,
      phone: user.phone,
      status: user.status,
      createdAt: user.createdAt,
    };
  }
}

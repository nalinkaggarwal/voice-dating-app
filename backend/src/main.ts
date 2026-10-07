import { NestFactory } from '@nestjs/core';
import { RequestMethod } from '@nestjs/common';
import { AppModule } from './app.module.js';
import { createValidationPipe } from './validation.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // Versioning the whole API now (WP3), rather than retrofitting it once
  // WP4's Live Snap/chat/calling endpoints add more clients calling
  // unversioned routes. AppController's root ('/') stays excluded -- it's
  // a bare health check, not a versioned API surface.
  app.setGlobalPrefix('v1', { exclude: [{ path: '/', method: RequestMethod.GET }] });
  // Every DTO's class-validator decorators were inert from WP1 through WP6
  // because nothing registered a pipe. See src/validation.ts for the
  // policy; src/validation.spec.ts pins the behaviour per DTO.
  app.useGlobalPipes(createValidationPipe());
  await app.listen(process.env.PORT ?? 3000);
}
await bootstrap();

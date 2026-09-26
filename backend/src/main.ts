import { NestFactory } from '@nestjs/core';
import { RequestMethod } from '@nestjs/common';
import { AppModule } from './app.module.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // Versioning the whole API now (WP3), rather than retrofitting it once
  // WP4's Live Snap/chat/calling endpoints add more clients calling
  // unversioned routes. AppController's root ('/') stays excluded -- it's
  // a bare health check, not a versioned API surface.
  app.setGlobalPrefix('v1', { exclude: [{ path: '/', method: RequestMethod.GET }] });
  await app.listen(process.env.PORT ?? 3000);
}
await bootstrap();

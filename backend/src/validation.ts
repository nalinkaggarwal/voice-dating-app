import { ValidationPipe } from '@nestjs/common';

// The one place the app's request-validation policy lives. main.ts
// registers this globally; test/app.e2e-spec.ts registers the same pipe
// so e2e behaviour matches production rather than silently skipping it.
//
// Why these options:
// - whitelist: unknown body properties are stripped rather than passed
//   through to services (every DTO declares all of its fields with a
//   class-validator decorator, so nothing legitimate is lost).
// - forbidNonWhitelisted is deliberately OFF: an older/newer mobile build
//   sending one extra field should not get a 400 for it.
// - transform: @Body() params arrive as real DTO class instances, so
//   @ValidateIf and friends see the typed object they were written for.
//   Implicit primitive conversion stays off -- JSON bodies already carry
//   the right primitive types, and turning it on would let "18" pass an
//   @IsInt() check.
// - stopAtFirstError: one message per failed property instead of one per
//   failed decorator, which keeps the `message` array the mobile client
//   joins into a single line (api_client.dart) readable.
export function createValidationPipe(): ValidationPipe {
  return new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: false,
    transform: true,
    stopAtFirstError: true,
  });
}

# Lolly.ai — WP1 (Foundations)

A dating app where users hear a voice clip before seeing a photo:

```
Reason -> Hear -> Decide -> Mutual Reveal -> Live Snap (liveness check) -> Chat/Call unlocked
```

This is **WP1 only**: auth foundations, the Connections schema, and module
skeletons. No matching, AI profile extraction, or Live Snap logic yet.

## Stack

- **Backend**: NestJS (TypeScript, ESM), PostgreSQL via Prisma, Redis,
  S3-compatible storage (client wired, no upload flows yet)
- **Mobile**: Flutter (iOS + Android, single codebase)
- **Auth**: OTP-only (email or phone), short-lived access tokens (15 min)
  + rotating, revocable refresh tokens (30 days)
- **Realtime**: WebSocket gateway skeleton (auth-gated, no chat logic yet)

## Repo layout

```
backend/    NestJS API
mobile/     Flutter app
.github/    CI (GitHub Actions)
docker-compose.yml   Postgres + Redis for local dev
```

## Backend — running locally

```bash
docker compose up -d          # Postgres + Redis
cd backend
cp .env.example .env          # fill in real secrets for anything beyond local dev
npm install
npx prisma generate
npx prisma migrate dev --name init
npm run start:dev
```

Tests: `npm test` (Vitest, all offline — Prisma/OTP-delivery are mocked,
no live DB needed). Lint: `npm run lint`. Type-check: `npx tsc --noEmit`.

### Auth flow (OTP-only, email or phone)

```
POST /auth/signup/start   { channel, identifier, dateOfBirth } -> { challengeId }
POST /auth/signup/verify  { challengeId, code }                -> { userId, tokens }
POST /auth/login/start    { channel, identifier }               -> { challengeId }
POST /auth/login/verify   { challengeId, code }                 -> { userId, tokens }
POST /auth/refresh        { refreshToken }                      -> tokens
POST /auth/logout         { refreshToken }                      -> { message }
GET  /auth/me             (Authorization: Bearer <accessToken>) -> user
```

`channel` is `"EMAIL"` or `"PHONE"`. In dev, OTP codes are logged to the
console (`ConsoleOtpProvider`) instead of actually being sent — swap for a
real Twilio/SES-backed provider behind the same `OtpDeliveryProvider`
interface when that's ready.

Refresh tokens rotate on every use and are stored hashed; presenting an
already-rotated token revokes its entire token family (theft signal).

### Module structure

Every module under `backend/src/modules/` follows the same shape
(`controller` / `service` / `module` / `dto/`). `identity/` is the only
one built out fully in WP1 — the rest (`profile`, `ai-profile`,
`discovery`, `connections`, `messaging`, `realtime`, `moderation`,
`billing`, `notifications`) are stubs so the module boundaries and DI
wiring already exist for later work packages.

`connections/` has its full Prisma schema (see below) but the actual
state-transition methods (`markInterested`, `decline`, `markSnapDone`,
`block`) are `NotImplementedException` stubs with the transition rules
documented in the service's docstring — real implementation is WP3.

### Database schema highlights

- `User` / `Consent` / `Profile` / `Connection` — exactly as specified for
  WP1.
- `OtpChallenge` / `RefreshToken` — added to actually implement OTP-only
  auth + rotating refresh tokens (not in the original schema sketch).

## Mobile — running locally

**Not verified on this machine** — no Flutter SDK was available in the
environment this was built in. The code follows standard Flutter/Dart
conventions and the backend-facing logic was reasoned through carefully,
but `flutter pub get` / `flutter analyze` / `flutter test` have not
actually been run against it. Treat CI's `mobile` job (or your own first
local run) as the first real verification.

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=APP_ENV=development
```

Tests: `flutter test`. Analyze: `flutter analyze`.

### Structure

```
lib/
  core/       app config (dart-define based), theming, a single AppException type
  shared/     API client (auto token-refresh on 401, single retry), secure
              token storage (flutter_secure_storage, never SharedPreferences),
              the User model
  features/
    auth/         built out fully — signup/login screens, OTP verify, AuthState
    onboarding/   placeholder shell (real onboarding is a later WP)
    discovery/, matches/, messaging/, voice_date/, trust_safety/, premium/
                  each a single placeholder screen for now
```

State management is `provider` (a single `ChangeNotifier`, `AuthState`) --
deliberately minimal for a thin auth+onboarding shell; a heavier solution
can come in once there's more cross-screen state to justify it.

## CI

`.github/workflows/ci.yml` runs on every push/PR: backend lint + type-check
+ test, and mobile analyze + test (Flutter SDK installed fresh in CI, so
this is also the mobile side's first real compile check).

## Decisions made this session (per the kickoff brief's own ask)

- **Refresh token lifetime**: 30 days, rotating.
- **Login method**: both email and phone as first-class, swappable per call.
- **Auth flow**: OTP-only, no passwords.

## Suggested next steps (WP2+)

- WP2: AI profile extraction (with the no personality/attractiveness-from-voice
  guardrail) — deserves its own focused kickoff prompt.
- WP3: Connections state machine transitions (schema's already here) +
  discovery/matching.
- WP4: Live Snap (WebRTC liveness check, atomic dual-confirmation) — also
  deserves its own focused kickoff prompt.

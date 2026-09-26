# Lolly.ai — WP1 + WP2

A dating app where users hear a voice clip before seeing a photo:

```
Reason -> Hear -> Decide -> Mutual Reveal -> Live Snap (liveness check) -> Chat/Call unlocked
```

**WP1**: auth foundations, Connections schema, module skeletons.
**WP2**: onboarding steps 2-5 (basic info -> preferences -> intent -> voice
recording -> AI review -> photo -> ACTIVE) and the voice-to-profile
pipeline. No Discovery/matching logic yet — WP3.

## Stack

- **Backend**: NestJS (TypeScript, ESM), PostgreSQL via Prisma, Redis +
  BullMQ (transcription/extraction pipeline), S3-compatible storage
  (signed direct-to-S3 uploads for voice + photo)
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

Tests: `npm test` (Vitest, all offline — Prisma/OTP-delivery/queues are
mocked, no live DB or Redis needed). Lint: `npm run lint`. Type-check:
`npx tsc --noEmit`. **75 tests, all passing** as of WP2.

### Auth flow (OTP-only, email or phone) — WP1

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
console (`ConsoleOtpProvider`) instead of actually being sent. Refresh
tokens rotate on every use and are stored hashed; presenting an
already-rotated token revokes its entire token family (theft signal).

### Onboarding + voice pipeline — WP2

```
POST /profile/basic-info               { displayName, geohash? }
POST /profile/preferences              { genderInterest[], ageMin?, ageMax?, maxDistanceKm? }
POST /profile/intent                   { relationshipIntent }
POST /profile/photo/upload-url         { contentType } -> { uploadUrl, key }
POST /profile/photo/complete           { key }          -> chains PHOTO_UPLOADED -> ACTIVE

POST /ai-profile/voice/upload-url      { contentType } -> { uploadUrl, key }
POST /ai-profile/voice/complete        { key }          -> creates VoiceAnswer, enqueues transcription
GET  /ai-profile/voice/:id             -> current status + claims
POST /ai-profile/claims/:id/edit       { text }
POST /ai-profile/claims/:id/approve
POST /ai-profile/claims/:id/discard
POST /ai-profile/voice/:id/finalize    -> USER_APPROVED, advances User.status to AI_REVIEW_DONE
```

Every `upload-url` endpoint returns a **signed PUT URL** — the client
uploads audio/photo bytes directly to S3, never through this API. Each
`User.status` transition (`ACCOUNT_CREATED` -> ... -> `ACTIVE`) goes
through `shared/onboarding/advance-status.util.ts`, a single guarded
`UPDATE ... WHERE status IN (...)` — atomic and idempotent, same
guarantee WP1's Connections rules require.

**Pipeline** (BullMQ on Redis, two queues): `voice/complete` creates a
`VoiceAnswer` (status `UPLOADED`) and enqueues a `transcription` job ->
`TranscriptionProcessor` calls `TranscriptionProvider` (mocked:
`ConsoleOtpProvider`'s sibling, `MockTranscriptionProvider`, returns fixed
dummy text) -> `TRANSCRIBED`, enqueues an `extraction` job ->
`ExtractionProcessor` calls `ProfileExtractionProvider` (mocked:
`MockExtractionProvider`) -> creates `ProfileClaim` rows (all unapproved)
-> `DRAFT_READY`. Either stage sets `FAILED` + `failureReason` on error.

**Hard guardrails** (documented on `ProfileExtractionProvider`'s
interface, not just the mock — any real vendor swapped in later must
hold these too): may only summarize what the user explicitly said; never
infer personality/attractiveness/ethnicity/health/"vibe" from tone,
accent, or pace; every claim is a draft until the user approves it —
nothing here has an auto-publish path; never use protected traits as a
hidden ranking signal. `MockExtractionProvider` satisfies these *by
construction* (it only ever emits verbatim sentences already in the
transcript) — a real LLM-backed provider will need actual prompt
engineering to hold the same guarantees, and its output should be run
through the same kind of guardrail tests as
`mock-extraction.provider.spec.ts`.

Real STT/LLM vendor is still open (kept the interfaces generic on
purpose); voice-recording retention policy also still open — WP2 doesn't
persist any real user audio (mocked pipeline), so there's nothing to
retain yet.

### Module structure

Every module under `backend/src/modules/` follows the same shape
(`controller` / `service` / `module` / `dto/`). `identity/`, `profile/`,
and `ai-profile/` are built out fully. `connections/` has its full Prisma
schema but the state-transition methods are `NotImplementedException`
stubs (WP3). The rest (`discovery`, `messaging`, `realtime`, `moderation`,
`billing`, `notifications`) are stubs.

### Database schema highlights

- WP1: `User` / `Consent` / `Profile` / `Connection`, plus `OtpChallenge`
  / `RefreshToken` (auth support, not in the original sketch).
- WP2: `VoiceAnswer` / `ProfileClaim` / `Preference`, plus a `FAILED`
  `VoiceAnswerStatus` (not in the original sketch — a stage that throws
  needs a real terminal state, not silently stuck mid-pipeline forever).

## Mobile — running locally

**Not verified on this machine** — no Flutter SDK was available in either
session this was built in. The code follows standard Flutter/Dart
conventions and the backend-facing logic was reasoned through carefully
(including manually tracing a few bugs found and fixed before they'd have
hit a real build), but `flutter pub get` / `flutter analyze` /
`flutter test` have not actually been run against it. Treat CI's `mobile`
job (or your own first local run) as the first real verification.

**Before your first run, you need to scaffold the platform folders** —
`android/` and `ios/` don't exist yet (that needs `flutter create`, which
needs the SDK):

```bash
cd mobile
flutter create . --project-name lolly --org com.lolly    # generates android/, ios/, etc. -- do this FIRST
flutter pub get
```

Then add the permission declarations the WP2 packages need (not added
automatically by `flutter create`):
- **Android** (`android/app/src/main/AndroidManifest.xml`): `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`
- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`

```bash
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
    auth/         signup/login/OTP-verify screens, AuthState
    onboarding/   WP2: full 6-step flow (basic info -> preferences ->
                  intent -> voice recording -> AI review -> photo),
                  resumes at the right step for a returning user (see
                  OnboardingState.resumeFrom) rather than always
                  restarting at step 1
    discovery/, matches/, messaging/, voice_date/, trust_safety/, premium/
                  each a single placeholder screen for now
```

Voice recording uses `record` (capture) + `audioplayers` (playback,
record/re-record/preview before upload) + `permission_handler` (mic
permission requested only when the user reaches that step, not at app
launch). Photo picking uses `image_picker`. State management is
`provider` (`ChangeNotifier`s: `AuthState`, `OnboardingState`).

One known, documented gap in `OnboardingState.resumeFrom`: if the app is
killed after a recording uploads but before the AI review is finalized
(`VOICE_RECORDED` status), there's no "fetch my most recent voice answer"
endpoint yet to resume the review screen with a known `voiceAnswerId` —
it falls back to the recording step (re-record) rather than resuming.

## CI

`.github/workflows/ci.yml` runs on every push/PR: backend lint +
type-check + test, and mobile analyze + test (Flutter SDK installed fresh
in CI — this predates the `flutter create` step above, so the mobile CI
job will need that added before it can pass; see the mobile section).

## Decisions made across sessions (per each kickoff brief's own ask)

- **WP1** — Refresh token lifetime: 30 days, rotating. Login method: both
  email and phone as first-class. Auth flow: OTP-only, no passwords.
- **WP2** — STT/LLM vendor: left fully open/generic (interfaces only).
  Recording retention: deferred entirely (nothing real is persisted yet).

## Suggested next steps (WP3+)

- WP3: Connections state machine transitions (schema's already here) +
  discovery/matching, consuming the approved `ProfileClaim`s from WP2.
- WP4: Live Snap (WebRTC liveness check, atomic dual-confirmation) —
  deserves its own focused kickoff prompt, highest-risk phase.

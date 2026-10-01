# Lolly.ai — WP1 + WP2 + WP3

A dating app where users hear a voice clip before seeing a photo:

```
Reason -> Hear -> Decide -> Mutual Reveal -> Live Snap (liveness check) -> Chat/Call unlocked
```

**WP1**: auth foundations, Connections schema, module skeletons.
**WP2**: onboarding steps 2-5 (basic info -> preferences -> intent -> voice
recording -> AI review -> photo -> ACTIVE) and the voice-to-profile
pipeline.
**WP3**: daily discovery/matching — one curated candidate a day (per-tier
configurable), eligibility filtering, explainable keyword-overlap ranking,
the decision endpoint wired into WP1's Connections state machine, and the
Flutter discovery/match screens. No Live Snap/chat yet — WP4.

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
`npx tsc --noEmit`. **129 tests, all passing** as of WP3.

### API versioning

Every route is served under a global `/v1` prefix (`main.ts`'s
`setGlobalPrefix`), added in WP3 while the surface area was still small
rather than retrofitting it once WP4 adds Live Snap/chat/calling routes.
The bare root health check (`GET /`) is the one exclusion. All routes
below are shown without the prefix for brevity — prepend `/v1` to every
one of them. The Flutter `ApiClient` prepends it in one place
(`_uri()`), so no call site hardcodes it.

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

### Daily discovery + matching — WP3

```
GET  /discovery/queue/today            -> { entries: [{ id, reasonText, voiceClipUrl }] }
POST /discovery/queue/:entryId/decide  { decision: "PASS" | "INTERESTED" } -> { entry, matched }
```

One curated candidate a day per user by default — **not** a swipe feed,
no browsing ahead. The per-day limit is DB-backed (`DiscoveryConfig`,
keyed by `User.tier`), read fresh on every generation run, so free vs.
premium limits can be changed independently at runtime with no deploy.

**Launch-blocking rule, verified explicitly (not just by inspection):**
`GET .../today` never returns a candidate's name, photo, or userId —
only `reasonText` and a signed `voiceClipUrl`. "Hear before you see" is
the app's entire premise (see the tagline above); `DiscoveryService.today()`
doesn't even query `Profile`, so there's no "fetched but not sent" step to
get wrong. `discovery.service.spec.ts` pins the exact response key set
and asserts `Profile` is never queried by this path. The Flutter
`DiscoveryEntry` model mirrors this — it has no `displayName`/`photoUrl`
field to accidentally render, and the candidate card shows a generic
silhouette instead.

**Pipeline** (`QueueGenerationService`, run daily at 3am UTC via
`@nestjs/schedule`): `EligibilityService` applies hard filters (ACTIVE
status, mutual age window, geohash-based distance — never exact
lat/long, mutual gender-interest compatibility, no existing `Connection`
in any status, blocked/reported exclusion) -> `ranking.util.ts` scores
survivors by explainable approved-`ProfileClaim` keyword/topic overlap
(deliberately not ML) -> `TemplateReasonGenerationProvider` builds a
grounded, non-generic reason sentence from the actual overlap -> one
`DiscoveryQueueEntry` per remaining daily slot.

`POST .../decide` reuses WP1's `ConnectionsService` state machine
(`createSuggestion` / `markInterested`, implemented for real in WP3) —
`INTERESTED` creates/updates a `Connection` and reports `matched: true`
only when THIS call is the one that flips it to `MUTUAL_INTEREST` (so a
retry never shows a duplicate "You matched!" screen). `PASS` has no
`Connection` side effects. Both are idempotent per entry via a single
guarded `updateMany` (`decision: null` in the WHERE clause), same pattern
as WP2's `advance-status.util.ts`.

**Two judgment calls made explicitly, not silently:**
- `relationshipIntent` alignment is a soft ranking tiebreaker, never a
  hard eligibility filter — with an early/sparse user base, a hard
  filter risked collapsing eligible candidates to zero for most users.
  It can only reorder candidates already tied on keyword overlap, never
  outrank a stronger keyword match. Revisit as a hard filter once the
  user base is large enough that this wouldn't happen.
- API versioning (`/v1`, see above) was applied API-wide rather than
  just to `discovery`, once flagged as an inconsistency.

### Module structure

Every module under `backend/src/modules/` follows the same shape
(`controller` / `service` / `module` / `dto/`). `identity/`, `profile/`,
`ai-profile/`, `connections/`, and `discovery/` are built out fully. The
rest (`messaging`, `realtime`, `moderation`, `billing`, `notifications`)
are stubs — `realtime`, `messaging`, and Live Snap land in WP4.

### Database schema highlights

- WP1: `User` / `Consent` / `Profile` / `Connection`, plus `OtpChallenge`
  / `RefreshToken` (auth support, not in the original sketch).
- WP2: `VoiceAnswer` / `ProfileClaim` / `Preference`, plus a `FAILED`
  `VoiceAnswerStatus` (not in the original sketch — a stage that throws
  needs a real terminal state, not silently stuck mid-pipeline forever).
- WP3: `DiscoveryConfig` / `DiscoveryQueueEntry`, plus `User.tier` and
  `Profile.gender` (a person's own gender — neither WP1 nor WP2 ever
  captured it; only `Preference.genderInterest`, who they're interested
  in, existed before). `DiscoveryQueueEntry`'s unique constraint is
  `(userId, queueDate, sequenceInDay)`, not the brief's suggested
  `(userId, queueDate)` — the extra `sequenceInDay` column is what makes
  a premium tier with `dailyCandidateLimit > 1` possible without a future
  schema change.

## Mobile — running locally

**Verified**: `android/` and `ios/` platform folders are scaffolded and
committed (generated via `flutter create . --project-name lolly --org
com.lolly`, trimmed to just these two per the stack decision above — drop
the linux/macos/web/windows folders `flutter create` adds by default if you
ever regenerate). Required permission declarations are already in place:
- **Android** (`android/app/src/main/AndroidManifest.xml`): `RECORD_AUDIO`
- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`

`flutter pub get` / `flutter analyze` / `flutter test` / `flutter build apk
--debug` have all actually been run and pass (10 tests, 0 analyzer errors,
APK builds). Two `dependency_overrides` in `pubspec.yaml` were needed to get
there — both documented inline there:
- `path_provider_foundation: 2.4.1` — newer versions pull in `objective_c`,
  which requires Dart's experimental native-assets build hooks; those hooks
  broke outright on a Windows profile path containing a space. Revisit once
  upstream fixes that, or just drop it on a machine without the issue.
- `record: ^7.1.1` (bumped from `^5.1.2`) — the old constraint resolved to
  `record_linux 0.7.2`, which doesn't implement the `record_platform_interface`
  version `record` itself pulls in (missing `startStream`, mismatched
  `hasPermission`) — breaks kernel compilation for every platform, not just
  Linux, since `record`'s own code branches on `Platform.isLinux` and the
  whole graph has to type-check. Bumping the whole `record` family together
  keeps its internal versions consistent; the `AudioRecorder`/`RecordConfig`
  API this app uses didn't change across the bump.

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=APP_ENV=development
```

Tests: `flutter test`. Analyze: `flutter analyze`. Build: `flutter build apk --debug`.

No Android emulator/device was available to actually launch the app on this
machine (Windows Hypervisor Platform firmware setting disabled in BIOS) — a
successful `flutter build apk` is as far as this got. Treat your own first
`flutter run` against a real device/emulator as the next verification step.

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
                  restarting at step 1. Ends by handing off to discovery/.
    discovery/    WP3: today's candidate card (photo, reason text, voice
                  clip playback), Pass/Interested, loading/empty/error
                  states. An ACTIVE user lands here directly on app
                  launch (see main.dart's _AppRoot).
    matches/      WP3: minimal "You matched!" screen, shown when a
                  decide() call reports a new mutual match. Deliberately
                  thin — full mutual-reveal/Live Snap UI is WP4.
    messaging/, voice_date/, trust_safety/, premium/
                  each a single placeholder screen for now
```

Voice recording uses `record` (capture) + `audioplayers` (playback) +
`permission_handler` (mic permission requested only when the user reaches
that step, not at app launch). Playback itself lives in one shared
widget, `shared/widgets/voice_clip_player.dart` — WP2's own-recording
preview (a local file) and WP3's discovery candidate card (a remote
signed URL) both use it, rather than duplicating play/pause/dispose
logic. Photo picking uses `image_picker`. State management is `provider`
(`ChangeNotifier`s: `AuthState`, `OnboardingState`, `DiscoveryState`).

One known, documented gap in `OnboardingState.resumeFrom`: if the app is
killed after a recording uploads but before the AI review is finalized
(`VOICE_RECORDED` status), there's no "fetch my most recent voice answer"
endpoint yet to resume the review screen with a known `voiceAnswerId` —
it falls back to the recording step (re-record) rather than resuming.

## CI

`.github/workflows/ci.yml` runs on every push/PR: backend lint +
type-check + test, and mobile analyze + test (Flutter SDK installed fresh in
CI, pinned to 3.47.5 — the version this was actually verified against
locally, see the mobile section). `android/`/`ios/` being committed means
CI's checkout already has everything `flutter pub get` needs; no `flutter
create` step required.

## Decisions made across sessions (per each kickoff brief's own ask)

- **WP1** — Refresh token lifetime: 30 days, rotating. Login method: both
  email and phone as first-class. Auth flow: OTP-only, no passwords.
- **WP2** — STT/LLM vendor: left fully open/generic (interfaces only).
  Recording retention: deferred entirely (nothing real is persisted yet).
- **WP3** — One-candidate-per-day: configurable per tier (DB-backed, not
  hardcoded), not a fixed hard constraint, so free vs. premium limits can
  differ and change without a deploy. `relationshipIntent`: soft ranking
  signal, not a hard filter (see "Two judgment calls" above). API
  versioning: applied `/v1` globally rather than leaving `discovery` as
  the only versioned route.

## Suggested next steps (WP4+)

- WP4: Live Snap (WebRTC liveness check, atomic dual-confirmation) once
  two users are `MUTUAL_INTEREST` — deserves its own focused kickoff
  prompt, highest-risk phase. Chat/calling unlock after that.

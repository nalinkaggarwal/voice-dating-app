# Lolly.ai — WP1 + WP2 + WP3 + WP4 + WP5

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
Flutter discovery/match screens.
**WP4**: Mutual Reveal (name/photo, once matched) and Live Snap — a live
mutual WebRTC video call with atomic dual-confirmation, landing the
Connection at AUTHENTICATED_MATCH. **Implemented and unit-tested, not yet
verified on a real device** — see "Verification status" below.
**WP5**: text + voice chat once a Connection is AUTHENTICATED_MATCH/ACTIVE
— conversation list, message history/pagination, and live delivery over
WP4's existing Socket.IO gateway. **No push notifications exist in this
project** — live delivery only works while both users have the app open
with a socket connected. **Implemented and unit-tested, not yet verified
on a real device** — see "Verification status" below before treating
this as a finished, shippable chat feature.

## Verification status

What's actually been confirmed, and what hasn't, as of WP5 — kept in one
place so it doesn't get lost in the per-section detail below:

| | Backend tests | Mobile unit tests | `flutter analyze`/build | Real device/emulator | Real two-device session |
|---|---|---|---|---|---|
| WP1-3 | ✅ pass | ✅ pass | ✅ clean / APK builds | ❌ not run | n/a |
| WP4 (Reveal + Live Snap) | ✅ pass | ✅ pass (`confirmMatch`/`declineMatch` only — see below) | ✅ clean / APK builds | ❌ not run | ❌ never exercised |
| WP5 (Chat) | ✅ pass | ✅ pass (`MessageThreadState` fully covered) | ✅ clean / APK builds | ❌ not run | ❌ never exercised |

Current totals (all of WP1-5 together): **188 backend tests, 35 mobile
tests, 0 analyzer errors** — see each module's own test file for the
per-feature breakdown; these numbers aren't re-split by work package
below.

No Android emulator or physical device was available while building any
of this (see "Mobile — running locally" below for why) — everything
above the device/session columns is static verification: the backend's
own logic tests (no live DB/Redis), Flutter's widget-free unit tests, a
successful `flutter analyze` and `flutter build apk --debug`. None of it
exercises `flutter_webrtc`'s native platform channel or a real
`socket_io_client` connection between two actual devices. Concretely,
that means:
- Live Snap's camera/mic permission flow, WebRTC offer/answer/ICE
  exchange, and the actual video call have **never run** — only
  `LiveSnapState.confirmMatch()`/`declineMatch()` are covered by a test
  that doesn't need the native platform channel.
- Chat's `MessageThreadState` (history, send, live delivery, reconnect
  catch-up, delivered/read) is fully unit-tested against a **fake**
  `ChatSocketClient` — real-world behavior against the actual backend
  Socket.IO gateway over a real network has never been observed.
- Treat your first `flutter run` against a real device/emulator, with
  two devices/accounts for Live Snap and chat specifically, as the next
  verification step this session could not take further.

## Stack

- **Backend**: NestJS (TypeScript, ESM), PostgreSQL via Prisma, Redis +
  BullMQ (transcription/extraction pipeline), S3-compatible storage
  (signed direct-to-S3 uploads for voice + photo)
- **Mobile**: Flutter (iOS + Android, single codebase)
- **Auth**: OTP-only (email or phone), short-lived access tokens (15 min)
  + rotating, revocable refresh tokens (30 days)
- **Realtime**: Socket.IO gateway, auth-gated (WP1) + Live Snap WebRTC
  signaling relay (WP4). No chat logic yet.

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
`npx tsc --noEmit`. **188 tests, all passing** as of WP5.

### API versioning

Every route is served under a global `/v1` prefix (`main.ts`'s
`setGlobalPrefix`), added in WP3 while the surface area was still small
rather than retrofitting it once WP4's Connections/Live Snap routes
landed. The bare root health check (`GET /`) is the one exclusion. All routes
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
GET  /ai-profile/voice/latest          -> caller's most recent VoiceAnswer (resume support, no id needed)
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
POST /discovery/queue/:entryId/decide  { decision: "PASS" | "INTERESTED" } -> { entry, matched, connectionId }
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
as WP2's `advance-status.util.ts`. `connectionId` (added in WP4) is only
ever populated on the call that actually processed an INTERESTED decision
— a retry returns `connectionId: null` rather than calling
`createSuggestion` again just to re-derive it, keeping the "no new side
effects on retry" guarantee above intact.

**Two judgment calls made explicitly, not silently:**
- `relationshipIntent` alignment is a soft ranking tiebreaker, never a
  hard eligibility filter — with an early/sparse user base, a hard
  filter risked collapsing eligible candidates to zero for most users.
  It can only reorder candidates already tied on keyword overlap, never
  outrank a stronger keyword match. Revisit as a hard filter once the
  user base is large enough that this wouldn't happen.
- API versioning (`/v1`, see above) was applied API-wide rather than
  just to `discovery`, once flagged as an inconsistency.

### Mutual Reveal + Live Snap — WP4

```
GET  /connections/:id/reveal          -> { displayName, photoUrl }  (the OTHER party's)
POST /connections/:id/decline         -> status CLOSED
POST /connections/:id/snap/confirm    -> { connection, matched }

POST /live-snap/:connectionId/start   -> { session, iceServers }
GET  /live-snap/:connectionId/session -> latest LiveSnapSession for this connection
```

**Mutual Reveal**: `ConnectionsService.getReveal()` — the matched user's
name + a signed photo URL (`StorageService.getDownloadUrl`, same pattern
`discovery.service.ts` uses for `voiceClipUrl`), gated on the connection
being MUTUAL_INTEREST or later. "Hear before you see" only governs the
pre-decision discovery payload (`TodayQueueEntryView`) — once there's a
real mutual match, revealing identity is the whole point of this step.

**Live Snap**: a live mutual WebRTC video call, not an independent
per-user liveness check — the two users see each other live before either
confirms. `LiveSnapSession` (new model) tracks one row per call attempt
(RINGING -> ACTIVE -> ENDED/MISSED) — plural by design, since a dropped
call can retry. Signaling (offer/answer/ICE) rides the existing
`RealtimeGateway` Socket.IO connection as a pure relay (`liveSnap:*`
events) — every event re-verifies the authenticated socket's userId is a
party to the connection, same as every REST route does. The gateway
assigns exactly one side to create the WebRTC offer (the second of the
pair to join the signaling room) to avoid both sides racing to offer at
once. **STUN-only** (public Google STUN servers, returned from the
`start` response) — no TURN server stood up for this pass, so a call can
fail to connect behind a restrictive/symmetric NAT. Standing up TURN is
deliberately deferred, not an oversight.

`ConnectionsService.markSnapDone()` (called via `.../snap/confirm`)
mirrors `markInterested`'s exact shape — set this user's `*SnapDone` flag,
re-check both inside one transaction, transition MUTUAL_INTEREST ->
SNAP_PENDING on the first confirmation, -> AUTHENTICATED_MATCH once both
are in. `matched: true` only on the call that actually flips it, same
"only the flipping call gets true" rule `decide()` uses — but unlike
`decide()`, there's no outer write-once entity protecting a retry here, so
the protection lives in `markSnapDone()` itself: a connection already at
AUTHENTICATED_MATCH/ACTIVE short-circuits to a harmless no-op instead of
re-running the flag logic.

**Explicitly out of scope for WP4** (don't assume these exist): a TURN
server, push notifications for an incoming call (no push infra exists in
this project at all yet — both users need the app open), in-call
reporting/moderation (`trust_safety` is still a stub), and the actual chat
UI/backend after AUTHENTICATED_MATCH (`messaging` stays a stub too).

### Chat — WP5

```
GET  /messaging/conversations              -> { conversations: [{ connectionId, displayName, photoUrl, lastMessage }] }
POST /messaging/voice/upload-url           { contentType } -> { uploadUrl, key }
GET  /messaging/:connectionId/messages     ?before=<ts> | ?since=<ts> | ?limit=<n> -> { messages, hasMore }
POST /messaging/:connectionId/messages     { type: "TEXT"|"VOICE", textContent? | audioUrl?+audioDurationSec? } -> Message
POST /messaging/:connectionId/delivered    -> { upTo }
POST /messaging/:connectionId/read         -> { upTo }
```

One `Message` row per text or voice message (new model — `type`,
`textContent`/`audioUrl`+`audioDurationSec`, `sentAt`/`deliveredAt`/
`readAt`), on an AUTHENTICATED_MATCH or ACTIVE `Connection`.
`MessagingService.getOwnedActiveConnection()` is the one access-control
gate every method goes through: caller must be a party to the connection
AND its status must be exactly one of those two. It's an **allowlist, not
a denylist** — SUGGESTED/MUTUAL_INTEREST/SNAP_PENDING/CLOSED/BLOCKED are
all rejected by not being in the allowed set. That matters specifically
for BLOCKED: `block()` (`ConnectionsService`) is still an unimplemented
stub, but the day it starts actually setting that status, messaging is cut
off here for free — nothing in this module needs to change.

**Sending a message is REST-only**, deliberately not symmetric with the
`message:send` socket event a first-draft spec for this work package
assumed. Every other business action in this app (Live Snap's
start/confirm/decline included) is REST too, with sockets reserved purely
for "tell whoever's already connected this just happened" — keeping that
consistent avoided a circular module dependency between `messaging/` and
`realtime/` that a symmetric socket-send path would have introduced
(`RealtimeGateway` would need `MessagingService` for inbound sends, while
`MessagingService` already needs `RealtimeGateway` for outbound
broadcasts). `RealtimeGateway.broadcastToChat()` is the one new piece on
the gateway: `MessagingService` calls it after persisting a
send/delivered/read, which fans out `message:new` / `message:delivered` /
`message:read` to the room. On connect (and reconnect), a socket
auto-joins a `chat:<connectionId>` room for every AUTHENTICATED_MATCH/
ACTIVE connection it's party to — ambient, not opt-in per conversation, so
a message lands even if that thread isn't the one on screen. Deliberately
a **separate room namespace from Live Snap's** (`liveSnap:<connectionId>`
vs `chat:<connectionId>`) — Live Snap's 2-person-room size check (see
WP4's `handleJoin`) would silently break the moment a socket is also
sitting in that same room just for chat delivery.

The first message sent on an AUTHENTICATED_MATCH connection flips its
status to ACTIVE (guarded `updateMany`, same idiom as `decline()`/
`advance-status.util.ts` — every later message is a harmless no-op here).
History pagination is cursor-based on `sentAt`: `before` pages backward
through older messages, `since` is the **reconnect catch-up path** — "ask
for everything newer than the last message I have," no pagination,
exercised on every socket (re)connect rather than trusting the socket
alone for correctness (same "ask for the truth, don't trust what you
think you already have" reasoning as `OnboardingState.resumeFrom`/
`GET /ai-profile/voice/latest`).

**Discovered while building this, not introduced by it:** there is no
`ValidationPipe` registered anywhere in this app (`main.ts`/
`app.module.ts`) — every DTO's `class-validator` decorators across WP1-4
have been inert the whole time; Nest never actually runs them.
`MessagingService.validateSendDto()` enforces WP5's own type-specific
required fields (TEXT needs `textContent`, VOICE needs `audioUrl` +
`audioDurationSec` capped at 60s) by hand rather than relying on the DTO
decorators, since those currently do nothing. Wiring up the pipe
app-wide would touch every existing endpoint's behavior at once —
deliberately left alone here as out of scope for this work package, but
worth fixing as its own pass.

**Explicitly out of scope for WP5**: the conversation list has no live
updates of its own (REST-only, refreshed on open/pull-to-refresh) — only
an open thread gets real-time delivery. No typing indicators, no message
editing/deletion, no group chat (one Connection, two participants, always).

### Module structure

Every module under `backend/src/modules/` follows the same shape
(`controller` / `service` / `module` / `dto/`). `identity/`, `profile/`,
`ai-profile/`, `connections/`, `discovery/`, `live-snap/`, and `messaging/`
are built out fully. `realtime/` has its WP1 auth skeleton plus WP4's Live
Snap signaling relay and WP5's chat broadcast. The rest (`moderation`,
`billing`, `notifications`) are still stubs.

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
- WP4: `LiveSnapSession` (`connectionId`, `status`, `startedAt`,
  `endedAt`) — one row per call attempt, not unique on `connectionId`,
  since a dropped call can retry; only the latest row for a connection
  matters for status checks. No change to `Connection` itself — WP1
  already had `userASnapDone`/`userBSnapDone` and `SNAP_PENDING`/
  `AUTHENTICATED_MATCH` on `ConnectionStatus`, built for exactly this.
- WP5: `Message` (`connectionId`, `senderId`, `type`, `textContent`/
  `audioUrl`+`audioDurationSec`, `sentAt`/`deliveredAt`/`readAt`), plus
  `MessageType` (`TEXT`/`VOICE`). Indexed on `(connectionId, sentAt)` --
  covers both "history for this connection" and "paginate using `sentAt`
  as the cursor" in one index. No `ConnectionStatus` change either --
  `ACTIVE` already existed on the enum (WP1) but nothing ever set it until
  WP5's first-message-sent transition.

## Mobile — running locally

**Verified**: `android/` and `ios/` platform folders are scaffolded and
committed (generated via `flutter create . --project-name lolly --org
com.lolly`, trimmed to just these two per the stack decision above — drop
the linux/macos/web/windows folders `flutter create` adds by default if you
ever regenerate). Required permission declarations are already in place:
- **Android** (`android/app/src/main/AndroidManifest.xml`): `RECORD_AUDIO`,
  `CAMERA` (WP4), `INTERNET`/`ACCESS_NETWORK_STATE`/`CHANGE_NETWORK_STATE`/
  `MODIFY_AUDIO_SETTINGS` + camera `uses-feature` entries (flutter_webrtc's
  own documented requirements, not optional extras)
- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription`,
  `NSCameraUsageDescription` (WP4), `NSPhotoLibraryUsageDescription`

`flutter pub get` / `flutter analyze` / `flutter test` / `flutter build apk
--debug` have all actually been run and pass (35 tests, 0 analyzer errors,
APK builds — including WP4's `flutter_webrtc`/`socket_io_client` native
code, reused as-is by WP5's chat socket, no new native dependencies
needed). Two `dependency_overrides` in `pubspec.yaml` were needed to get
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
`flutter run` against a real device/emulator as the next verification step
— WP4's Live Snap call AND WP5's chat (sent explicitly before that device
verification happened, per an explicit call made when WP5 was kicked off)
have never been exercised against a real two-device session; that's your
first real test of both, not something this session could verify further.
See "Verification status" near the top of this file for the consolidated
summary of exactly what has and hasn't been confirmed.

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
    matches/      WP3: "You matched!" screen, shown when a decide() call
                  reports a new mutual match. Its CTA now (WP4) pushes
                  into reveal/ rather than just dismissing.
    reveal/       WP4: Mutual Reveal -- the matched user's name/photo
                  (GET /connections/:id/reveal), with a "Start Live Snap"
                  / "Not interested" choice before committing to a call.
    live_snap/    WP4: the Live Snap video call itself -- camera/mic
                  permission flow (mirrors voice_recording_step.dart),
                  flutter_webrtc peer connection, socket_io_client
                  signaling (SignalingClient), and the confirm/decline
                  screen shown once the call ends. Confirming a match that
                  just hit AUTHENTICATED_MATCH (WP5) now pushes straight
                  into messaging/'s new thread screen instead of just
                  popping back to Discovery.
    messaging/    WP5: conversation list (GET /messaging/conversations) +
                  message thread (history/pagination, text + voice send,
                  live delivery via ChatSocketClient -- a second thin
                  socket_io_client wrapper alongside live_snap/'s
                  SignalingClient, same stored-access-token auth pattern).
                  Voice messages record via the same AudioRecorder pattern
                  as voice_recording_step.dart, auto-stopping at the 60s
                  cap. Reached from a new "Messages" icon in Discovery's
                  AppBar -- there was no bottom-nav shell to hang this off
                  of before WP5, so this is the first real navigation
                  entry point into it.
    voice_date/, trust_safety/, premium/
                  each a single placeholder screen for now
```

`currentUserId` is threaded from `main.dart`'s single already-fetched
`User` (the same one `OnboardingFlowScreen`'s `resumeFrom` comes from) all
the way down through `DiscoveryHomeScreen` -> `MatchScreen` ->
`RevealScreen` -> `LiveSnapCallScreen` -> `MessageThreadScreen`, and
separately through `OnboardingFlowScreen` -> `OnboardingCompleteStep` for
a user finishing onboarding for the first time. Every messaging screen
needs it (to tell "my message" from "theirs"); fetching it once at the
root and passing it down avoids every screen independently re-fetching
the same `GET /auth/me`.

Voice recording uses `record` (capture) + `audioplayers` (playback) +
`permission_handler` (mic permission requested only when the user reaches
that step, not at app launch). Playback itself lives in one shared
widget, `shared/widgets/voice_clip_player.dart` — WP2's own-recording
preview (a local file) and WP3's discovery candidate card (a remote
signed URL) both use it, rather than duplicating play/pause/dispose
logic. Photo picking uses `image_picker`. Voice message recording
(`message_thread_screen.dart`) reuses the exact same recorder pattern, in
the widget itself rather than on `MessageThreadState` -- recording is
UI-lifecycle-bound, not business state, same reasoning
`voice_recording_step.dart` already established. State management is
`provider` (`ChangeNotifier`s: `AuthState`, `OnboardingState`,
`DiscoveryState`, `RevealState`, `LiveSnapState`, `ConversationsState`,
`MessageThreadState`).

`LiveSnapState` (WP4) owns the whole call lifecycle: camera/mic
permission, the `flutter_webrtc` peer connection, and `SignalingClient` (a
thin `socket_io_client` wrapper connecting with the same stored access
token `ApiClient` uses). `confirmMatch()`/`declineMatch()` are the only
part of it covered by unit tests — everything else calls into
`flutter_webrtc`'s native platform channel, which has no implementation in
a plain `flutter test` run (no device/emulator); see the doc comment on
`live_snap_state_test.dart` for why that's a real test-environment limit,
not a gap left on purpose.

`MessageThreadState` (WP5) is fully unit-tested, unlike `LiveSnapState` --
`socket_io_client` (unlike `flutter_webrtc`) is pure Dart with no native
platform channel, so a fake `ChatSocketClient` can simulate
connect/reconnect/incoming-message/delivered/read events directly in a
plain `flutter test` run. Covers: history load, live message dedup (a
duplicate `message:new` for the same id is a no-op), reconnect catch-up
via `since`, delivered/read status broadcasts applying only to the
caller's OWN messages, send (text and voice), and backward pagination.

`OnboardingState.resumeFrom`'s one-time gap is closed: if the app is killed
after a recording uploads but before the AI review is finalized
(`VOICE_RECORDED` status), `GET /ai-profile/voice/latest` (added for exactly
this) fetches the caller's most recent `VoiceAnswer` with no `voiceAnswerId`
needed. `resumeFrom` still synchronously defaults to the recording step
first — the only safe guess without an extra round-trip — then upgrades to
the review screen once that fetch lands; any failure (no voice answer on
record, network error) just leaves the safe default in place.

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
- **WP4** — Live Snap is a live mutual video call, not an independent
  per-user liveness check (the two product readings `markSnapDone`'s own
  WP1-era TODO left open) — the two users see each other live before
  either confirms. Mutual Reveal (name/photo) is in scope too, as its own
  step before the call, not collapsed into it. TURN server: deferred —
  STUN-only for this pass, a documented limitation, not an oversight.
- **WP5** — Voice message cap: 60 seconds, confirmed explicitly rather
  than assumed. Conversation list: built (not a single-active-thread
  MVP) — WP3's one-candidate-a-day limit caps how fast new matches
  appear, not how many stay active at once, confirmed explicitly rather
  than assumed too. Sending is REST-only, not the symmetric socket
  `message:send` event a first-draft spec assumed — see the Chat section
  above for why. Kicked off explicitly before WP1-4 were verified on a
  real device (a prerequisite the kickoff brief itself named) — a known,
  accepted risk, not an oversight; see the Mobile section's own caveat.

## Suggested next steps (WP6+)

- Calling (voice/video, not just Live Snap's one-time check) once a
  Connection reaches `AUTHENTICATED_MATCH`/`ACTIVE` — `realtime` has the
  WebRTC signaling groundwork (WP4) but nothing wired up for an
  on-demand call the way Live Snap's is for the one-time check.
- A TURN server for Live Snap (and any future calling) — STUN-only today
  means a call can fail to connect behind a restrictive/symmetric NAT.
- Push notifications — for an incoming Live Snap call AND for messages:
  today both users need the app open (with a socket connected) at the
  same time for either to work at all. This is the single biggest gap
  between "built" and "shippable" across WP4 and WP5 both.
- Wire up a global `ValidationPipe` (see the Chat section's own note) --
  every DTO's `class-validator` decorators across WP1-5 currently do
  nothing; each service has had to hand-roll its own validation instead.
- In-call/in-chat reporting and the `block()` connection action —
  `trust_safety` and `ConnectionsService.block()` are both still stubs.

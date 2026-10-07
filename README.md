# Lolly.ai — WP1 + WP2 + WP3 + WP4 + WP5 + WP6 + WP7

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
**WP6**: Moderation & Block — launch-blocking per the original spec, not
optional scope. `block()`/`report()` implemented for real (closing the
WP1-era `BLOCKED` status and WP5's own messaging TODO), a priority-aware
moderation queue, and enforcement wired into discovery, messaging, Live
Snap, and Mutual Reveal — each with its own explicit test rather than
assumed coverage from a general rule (the same lesson WP3's photo-leak
bug taught).
**WP7**: Push notifications — the "single biggest gap between built and
shippable" named at the end of WP5. FCM via `firebase-admin` behind a
pluggable provider (console stub when no service account is configured),
device-token registration, and pushes on new message, mutual match, Live
Snap invite and authenticated match — with "hear before you see" applied
to the push text itself. **Backend and mobile both unit-tested; never
exercised end-to-end**: creating the Firebase project needs the account
owner (see "What WP7 still needs from you" in its section).

## Verification status

What's actually been confirmed, and what hasn't, as of WP6 — kept in one
place so it doesn't get lost in the per-section detail below:

| | Backend tests | Mobile unit tests | `flutter analyze`/build | Real device/emulator | Real two-device session |
|---|---|---|---|---|---|
| WP1-3 | ✅ pass | ✅ pass | ✅ clean / APK builds | ❌ not run | n/a |
| WP4 (Reveal + Live Snap) | ✅ pass | ✅ pass (`confirmMatch`/`declineMatch` only — see below) | ✅ clean / APK builds | ❌ not run | ❌ never exercised |
| WP5 (Chat) | ✅ pass | ✅ pass (`MessageThreadState` fully covered) | ✅ clean / APK builds | ❌ not run | ❌ never exercised |
| WP6 (Moderation & Block) | ✅ pass | ✅ pass (pure `wireValue` mapping only — see below) | ✅ clean / APK builds | ❌ not run | ❌ never exercised |
| WP7 (Push notifications) | ✅ pass | ✅ pass (pure `PushPayload` parsing/routing only — see below) | ✅ clean / APK builds (without `google-services.json`) | ❌ launched only, push off (no Firebase config) | ❌ never exercised |

Current totals (all of WP1-7 together): **261 backend tests, 54 mobile
tests, 0 analyzer issues** — see each module's own test file for the
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
- WP6's `confirmAndBlockUser()`/`showReportDialog()` dialogs and their
  wiring into `RevealScreen`/`MessageThreadScreen`/`LiveSnapCallScreen`
  have never been tapped through on a real screen -- only the pure
  `ReportReason`/`ReportContext` wire-value mapping they depend on is
  unit-tested (no Flutter `State`/`ChangeNotifier` layer exists for these
  dialogs to test against a fake repository the way Reveal/Chat do).
- WP7's `PushNotifications` (Firebase init, token registration, foreground
  display, tap routing) has never run with a real `google-services.json`:
  only the pure `PushPayload` parsing/routing rules it depends on are
  unit-tested. The APK was installed and launched on a real Android
  device once (OnePlus CPH2573, Android 16), which verified exactly one
  thing: with no Firebase config the app starts normally to the auth
  screen, no crash. The `[push] disabled` log line itself was NOT
  observed -- that device surfaces no Flutter-tagged logcat lines at all
  under `adb logcat`, so treat the graceful-degrade path as
  launch-verified, not log-verified.
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
npx prisma migrate dev           # applies the committed backend/prisma/migrations/
npm run start:dev
```

Tests: `npm test` (Vitest, all offline — Prisma/OTP-delivery/queues are
mocked, no live DB or Redis needed). Lint: `npm run lint`. Type-check:
`npx tsc --noEmit`. **261 tests, all passing** as of WP7.

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
GET  /connections/:id/reveal          -> { userId, displayName, photoUrl }  (the OTHER party's)
POST /connections/:id/decline         -> status CLOSED
POST /connections/:id/snap/confirm    -> { connection, matched }

POST /live-snap/:connectionId/start   -> { session, iceServers }
GET  /live-snap/:connectionId/session -> latest LiveSnapSession for this connection
```

**Mutual Reveal**: `ConnectionsService.getReveal()` — the matched user's
id, name + a signed photo URL (`StorageService.getDownloadUrl`, same
pattern `discovery.service.ts` uses for `voiceClipUrl`), gated on the
connection being MUTUAL_INTEREST or later — and, since WP6, explicitly
rejecting BLOCKED too (a prior reveal doesn't grandfather in access once
blocked, same rule WP6 applies to messaging). "Hear before you see" only
governs the pre-decision discovery payload (`TodayQueueEntryView`) —
once there's a real mutual match, revealing identity (including the
userId, added in WP6 so the client can actually address a block/report
call) is the whole point of this step.

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
GET  /messaging/conversations              -> { conversations: [{ connectionId, otherUserId, displayName, photoUrl, lastMessage }] }
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
all rejected by not being in the allowed set. That mattered specifically
for BLOCKED: this allowlist shape meant `block()` (`ConnectionsService`,
landed in WP6 — see below) cut messaging off for free the moment it
started actually setting that status, with nothing in this module needing
to change. WP6 added one more layer on top regardless (an explicit
`isBlocked` check against the `Block` table itself) — see WP6's own
section for why.
`otherUserId` on both the conversation list and the thread's own address
(connectionId + otherUserId, threaded from `RevealScreen` and
`ConversationsListScreen`) is what lets the Flutter client actually
address a block()/report() call from WP6's UI — added for that reason,
not part of the original WP5 scope.

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

**Discovered while building this, not introduced by it:** at the time of
WP5 there was no `ValidationPipe` registered anywhere in this app, so
every DTO's `class-validator` decorators across WP1-5 were inert; Nest
never ran them. `MessagingService.validateSendDto()` was written to
enforce WP5's type-specific required fields (TEXT needs `textContent`,
VOICE needs `audioUrl` + `audioDurationSec` capped at 60s) by hand for
that reason. **Fixed in the post-WP6 hardening pass** (see that section
below): the pipe is now global, so a bad body is a 400 before it reaches
the service. `validateSendDto()` stays as a second line of defence for
any non-HTTP caller.

**Explicitly out of scope for WP5**: the conversation list has no live
updates of its own (REST-only, refreshed on open/pull-to-refresh) — only
an open thread gets real-time delivery. No typing indicators, no message
editing/deletion, no group chat (one Connection, two participants, always).

### Moderation & Block — WP6

```
POST /connections/block                    { blockedUserId } -> { block, connection }
GET  /connections/blocks                   -> Block[] (the caller's own "people I've blocked" list)

POST /moderation/reports                   { reportedUserId, reason, context, contextId?, details? } -> Report
GET  /moderation/reports                   ?status=&context=&priority= -> Report[] (admin only)
GET  /moderation/reports/:id               -> Report (admin only)
POST /moderation/reports/:id/action        { status, decision? } -> Report (admin only; covers assign/action AND dismiss)
```

Launch-blocking per the original spec, not optional scope — the Connections
schema had a `BLOCKED` status sitting unused since WP1, WP3's eligibility
filter already excluded it generally, and messaging's access-control gate
had a TODO referencing this future implementation. All three now have
something real behind them.

**`block()`** (`ConnectionsService.block(blockerId, blockedId)`, by user
id rather than connectionId — unlike every other method in that service,
a block must be reachable even for a pair with no `Connection` row yet) —
one transaction: upsert a `Block` row (idempotent on its own unique
constraint) AND force any `Connection` between the pair, existing or not,
to `BLOCKED` — unconditionally overriding whatever status it was in,
reusing `createSuggestion`'s own upsert-by-canonical-pair idiom rather
than writing new matching logic. This is the one transition in this
service that does NOT guard off a specific prior status, by design — the
spec's "immediately, everywhere" requirement means a block has to win
over AUTHENTICATED_MATCH/ACTIVE/whatever else, not just a tidy subset of
statuses.

**Enforcement** is layered, not single-point, per an explicit instruction
not to trust one check alone:
- Discovery already excluded any existing `Connection` in any status
  (including `BLOCKED`) before this WP — `eligibility.util.spec.ts`
  already asserted this specific case at the pure-function level. WP6
  adds `eligibility.service.spec.ts`, a DB-mocked integration-level test
  of the same case through `eligibleCandidatesFor()` itself — the WP3
  photo-leak bug happened at exactly this kind of gap (correct pure logic,
  never actually exercised through the service that wires it up), so this
  specific case gets its own test at that level too, not just inferred
  from the util-level one "generally covering" it.
- `ConnectionsService.createSuggestion()` (discovery's decide() path) now
  checks a new shared `isBlocked()` helper (`shared/moderation/block.util.ts`
  — a direct `Block`-table query, callable from any module with
  `PrismaService` already in hand, no cross-module DI needed) before
  creating/progressing a `Connection` — defense in depth on top of the
  eligibility filter, not a replacement for it.
- `MessagingService.getOwnedActiveConnection()` and
  `LiveSnapService.getOwnedConnection()` both call the same `isBlocked()`
  helper on top of their existing status checks — BLOCKED already fails
  the allowlist/status check on its own, so this is a second, independent
  signal (the `Block` table itself, not a status derived from it) standing
  between a blocked pair and messaging or a new Live Snap session.
- `ConnectionsService.getReveal()` now explicitly rejects `BLOCKED` too —
  a prior reveal doesn't grandfather in access.

**`report()`** (`ModerationService.report()`) is deliberately independent
of `block()` — reporting never blocks, and blocking never requires a
report on file first (confirmed explicitly per the kickoff brief's own
ask, not assumed). Reports a profile, a message, or a Live Snap session
(`ReportContext`), with an optional `contextId` naming the specific one.
**Priority** (`report-priority.util.ts`) is computed, not a stored
column — a `LIVE_SNAP`-context report or a `SAFETY_CONCERN` reason ranks
`HIGH`, everything else `NORMAL`, oldest-first within each tier (FIFO) —
computing it keeps it from ever drifting out of sync with the
reason/context it's derived from.

**Admin**, for this MVP pass: a plain `isAdmin` boolean on `User`
(confirmed explicitly per the kickoff brief's own ask — manually set via
a direct DB `UPDATE`, no self-serve promotion flow, no role/RBAC system).
`AdminGuard` (`identity/guards/`, alongside `AccessTokenGuard`) does the
one DB lookup this needs; `isAdmin` is deliberately NOT encoded into the
short-lived access token itself, so revoking admin access takes effect on
a user's very next request rather than only their next login. Every
`/moderation/reports` route except creating a report itself is gated with
`@UseGuards(AccessTokenGuard, AdminGuard)`, in that order (`AdminGuard`
needs `request.userId`, which `AccessTokenGuard` sets).

**Query pattern for "who have I blocked"**: one-directional storage
(`blockerId`/`blockedId` on `Block`), queried only in the blocker's own
direction (`listBlocked()` filters on `blockerId = callerId`) — there's
no "who blocked me" surface anywhere in the product, and exposing one
would defeat the point of a block, so `User.blocksReceived` exists purely
as the inverse Prisma relation, never queried on its own. Enforcement
(`isBlocked()`), unlike this query, checks both directions — if A blocked
B, B is blocked from reaching A too, not just vice versa.

**Message history on block**: kept, not deleted or hidden server-side —
confirmed explicitly per the kickoff brief's own ask. Blocking forces the
`Connection` to `BLOCKED`, and `getOwnedActiveConnection`'s allowlist
already stops both read and send access for both parties the instant
that happens; there's no separate "hide history" step because the access
gate already covers it, and keeping the rows themselves intact leaves
them available if a report tied to that conversation ever needs review.

**Flutter**: a new `trust_safety/` feature — `TrustSafetyRepository`
(`blockUser`/`reportUser`) plus two reusable pieces,
`confirmAndBlockUser()` (a confirmation dialog first; blocking is a
meaningful, hard-to-undo action, never a single accidental tap) and
`showReportDialog()` (reason picker + optional details). Wired into
`RevealScreen` (profile view, context `PROFILE`), `MessageThreadScreen`
(context `CONNECTION`, contextId the connectionId), and
`LiveSnapCallScreen` (report only, context `LIVE_SNAP`, contextId the
session id — block isn't offered mid-call, matching the kickoff brief's
own surface list). A blocked match doesn't need its own "no longer
available" UI state: the backend's conversation list and reveal already
only return AUTHENTICATED_MATCH/ACTIVE/non-BLOCKED connections, so once
you pop back to a list screen after blocking, it's just gone, the same
way any other filtered-out row would be. Threading `otherUserId` into
`RevealProfile` and `Conversation` (both previously exposed only
`displayName`/`photoUrl` — see WP4/WP5's sections above) is what makes
addressing these calls from the client possible at all.

**Explicitly out of scope for WP6**: no admin UI (REST-only, per the
kickoff brief's own instruction to ask before building more than a small
addition) and no in-call reporting UI beyond the single Live Snap report
action described above (no moderator review tooling, no automated
action on a report — `actionReport()` is a manual admin decision every
time).

### Push notifications — WP7

```
POST /notifications/devices             { token, platform: "ANDROID"|"IOS" } -> DeviceToken   (upsert by token)
POST /notifications/devices/unregister  { token }                            -> { removed }
```

Nothing is sent on a client's say-so: pushes originate only inside the
services that own the triggering event, each hooked at the one place
that event is decided and **after the transaction commits**:

| Event | Hook | Recipient | Push text |
|---|---|---|---|
| New message | `MessagingService.sendMessage`, after the socket broadcast | the other party | sender's display name + text preview (80 chars) / "sent you a voice message" |
| Mutual match | `ConnectionsService.markInterested`, the single call that flips SUGGESTED → MUTUAL_INTEREST | the party who liked *first* (the flipper already gets `matched` back) | **anonymous** — "Someone you liked likes you back" |
| Live Snap invite | `LiveSnapService.startSession`, only on a genuinely new session (a re-tap on one already RINGING returns early) | the callee | caller's name + "wants to Live Snap" |
| Authenticated match | `ConnectionsService.markSnapDone`, the single call that flips to AUTHENTICATED_MATCH | the party who confirmed first | other party's name + "Your chat is open" |

**"Hear before you see" applies to the push text too.** The mutual-match
push deliberately does no profile lookup: no name, no photo, and the
mobile tap just foregrounds the app (`PushDestination.home`) — Reveal
hasn't happened yet. From MUTUAL_INTEREST on, `getReveal` already permits
the name, so Live Snap invites and match confirmations carry it and
deep-link to the call / the thread. `notifications.service.spec.ts` pins
this ("never looks up a profile and carries no name in title, body or
data").

**Provider seam** (`notifications/push/`): `PushProvider` is the one
interface; `FcmPushProvider` wraps `firebase-admin`'s
`sendEachForMulticast` (500-token batches, Android channel
`lolly_default`, maps FCM's two dead-token codes to `unregistered`), and
`ConsolePushProvider` logs instead — chosen by `push-provider.factory.ts`
from `FIREBASE_SERVICE_ACCOUNT_PATH` / `FIREBASE_SERVICE_ACCOUNT_JSON`, with
a loud warning when neither is set so a logged push is never mistaken for
a delivered one. Same shape as identity's `ConsoleOtpProvider`.

**Token bookkeeping** (`DeviceToken`, keyed by token not user): the same
phone logging into another account moves the token to that account;
tokens FCM reports dead are deleted on the spot; logout unregisters
*before* the session is cleared (the call needs the access token).
`notifyX` never throws — a push failing must never fail the message /
match / call that triggered it; the services `await` it only so tests
are deterministic.

**Mobile** (`core/notifications/`): `PushNotifications` initializes
Firebase before `runApp` (and simply disables itself if
`google-services.json` is absent), creates the `lolly_default` channel,
registers the token through `AuthState` (via the `PushRegistrar`
interface so AuthState's own tests never touch Firebase), mirrors
foreground arrivals as local notifications — except a message for the
thread currently on screen, which `MessageThreadScreen` reports via
`activeConnectionId` — and routes taps through `PushPayload`
(`core/notifications/push_payload.dart`, pure Dart, fully unit-tested:
wire parsing, forward-compatible null on unknown types, destination per
kind, foreground suppression rule). A tap that arrives before the user id
is known is parked and replayed by `attachSession`. Android:
`POST_NOTIFICATIONS` permission, default channel meta-data, core-library
desugaring (a `flutter_local_notifications` requirement), and the
`google-services` Gradle plugin applied **only if the JSON file exists**
so a clone without it still builds.

**What WP7 still needs from you** (none of this can be done from a
session without your Google account):

1. A Firebase project (the CLI here is logged in but creating a project
   was blocked as an account-level action). Add an Android app with
   package name `com.lolly.lolly`, download `google-services.json` into
   `mobile/android/app/` (gitignored).
2. Project settings → Service accounts → *Generate new private key*; save
   it as `backend/firebase-service-account.json` (gitignored) and set
   `FIREBASE_SERVICE_ACCOUNT_PATH` in `backend/.env`.
3. `flutter run` on a device: after login the log shows the token being
   registered; the Firebase console's *Messaging → Send test message*
   with that token is the quickest check of the mobile side alone; a
   second account sending a message / starting Live Snap is the real
   end-to-end check.

**Explicitly out of scope for WP7**: iOS APNs setup (the code paths exist,
no `GoogleService-Info.plist` or capability has been configured), a
notification inbox / history, per-event opt-outs, and any push for
events other than the four above.

### Post-WP6 hardening pass

Four fixes that fell out of reviewing the WP6 tree, none of them new
product scope:

- **Global `ValidationPipe`** (`src/validation.ts`, registered in
  `main.ts` and mirrored in `test/app.e2e-spec.ts`). Every DTO's
  `class-validator` decorators were inert from WP1 through WP6 -- see the
  Chat section's note. Policy: `whitelist` on (unknown body fields are
  stripped), `forbidNonWhitelisted` off (an older/newer mobile build
  sending one extra field must not 400), `transform` on (DTOs arrive as
  class instances so `@ValidateIf` works), implicit primitive conversion
  off (`"18"` must not pass `@IsInt()`), `stopAtFirstError` on (one
  message per bad property, which is what `api_client.dart` joins into a
  single line). `src/validation.spec.ts` runs the exact pipe `main.ts`
  registers against the real DTO classes -- including the shapes the
  mobile client actually sends (date-only `dateOfBirth`, omitted optional
  preferences) -- since the per-module unit tests never cross the HTTP
  layer. The hand-rolled checks in `MessagingService`,
  `ModerationService` and `ConnectionsService` stay in place as a second
  line of defence; the DTO comments that said "the pipe doesn't exist"
  are updated.
- **Committed baseline migration** (`backend/prisma/migrations/`).
  `schema.prisma` had been edited through six work packages with no
  migration history checked in, so a fresh clone had nothing to
  `migrate deploy`. `20261007000000_init` is the full schema as of WP6,
  generated offline with `prisma migrate diff --from-empty`, plus the
  `migration_lock.toml` Prisma expects. Local setup is now plain
  `npx prisma migrate dev`; future schema changes get their own
  migration the normal way. Not yet applied to a real Postgres from this
  session -- Docker wasn't available -- so the first `migrate dev` against
  a live DB is the verification step still owed.
- **CI never ran on push.** `.github/workflows/ci.yml` triggered on
  `push: branches: [main]`, but this repo's branch is `master`, so only
  pull requests ever exercised it. Now `[master]`. Its first real run then
  failed at `npm ci`: the lockfile is authored here on Node 24 / npm 11,
  which tolerates two nested optional peers (`typescript@5` under
  `vite-tsconfig-paths`, `magicast@0.3` under `@prisma/config`) being
  absent, while CI's Node 22 / npm 10 rejects the lock as out of sync.
  Reproduced locally with a portable Node 22. Fixed both ways: the lock
  is regenerated so npm 10 and 11 both accept it, and CI now runs Node
  24 to match the machine that writes the lock.
- **Analyzer clean, not just error-free.** The 7 `flutter analyze` info
  lints (deprecated `RadioListTile.groupValue`/`onChanged` -> a
  `RadioGroup` ancestor, an unnecessary `dart:typed_data` import, and
  `const`/quote style) are fixed; `flutter analyze` reports 0 issues.

### Module structure

Every module under `backend/src/modules/` follows the same shape
(`controller` / `service` / `module` / `dto/`). `identity/`, `profile/`,
`ai-profile/`, `connections/`, `discovery/`, `live-snap/`, `messaging/`,
and `moderation/` (real since WP6) are built out fully. `realtime/` has
its WP1 auth skeleton plus WP4's Live Snap signaling relay and WP5's
chat broadcast. `notifications/` is real since WP7. `billing` is still a
stub.

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
- WP6: `User.isAdmin` (plain boolean, see the Moderation section above for
  why not a role/RBAC system). `Block` (`blockerId`/`blockedId`, unique on
  the pair) and `Report` (`reporterId`/`reportedUserId`/`reason`/
  `context`/`contextId`/`details`/`status`/`reviewedAt`/`reviewedBy`/
  `decision`), plus `ReportReason`/`ReportContext`/`ReportStatus`. No
  stored priority column on `Report` -- computed from `reason`/`context`
  instead (see `report-priority.util.ts`), so it can't drift out of sync
  with the columns it's derived from. No `ConnectionStatus` change --
  `BLOCKED` already existed on the enum (WP1) but nothing ever set it
  until WP6's `block()`.

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
--debug` have all actually been run and pass (37 tests, 0 analyzer errors,
APK builds — including WP4's `flutter_webrtc`/`socket_io_client` native
code, reused as-is by WP5's chat socket and WP6's trust_safety/ dialogs
(plain `http` calls, no new native dependency), no new native
dependencies needed). Two `dependency_overrides` in `pubspec.yaml` were
needed to get there — both documented inline there:
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

### Visual identity, splash and launcher icon ("Afterglow", 2026-10-07)

A refresh in the same spirit as visitorX's, with an identity built for
*hear before you see* rather than borrowed from it:

- **Colour** (`lib/core/theme/app_theme.dart`): **plum → magenta**
  (`#5B2A86` → `#B83A8C`) is the brand gradient — after-dark, a little
  mysterious, the part of someone you haven't seen yet. It seeds the whole
  Material 3 scheme (tonal surfaces, chips, app bar), light *and* dark
  (`themeMode: system`). **Coral** (`#FF7A59`) is the voice: reserved for
  waveforms, the mark's lollipop head, and the ONE call-to-action per
  screen (`AppTheme.accentButton`), so it always means "this is the
  moment". Pill buttons, generous radii, `AppSpacing`/`AppRadius` scales
  instead of ad-hoc numbers, error text on `colorScheme.error` everywhere
  (no more `Colors.red`).
- **Mark** (`lib/core/theme/branding.dart`, `LollyMark`): a lollipop whose
  head holds a five-bar sound wave — the name and the motto in one shape.
  Drawn by a `CustomPainter`, not an asset, with a `progress` input that
  plays its build-in (head pops, stick draws, bars rise in sequence).
  `AppWordmark` sets "Lolly.ai" with the ".ai" in coral; `VoiceWaveform`
  is the breathing-bars cue used beside every play button.
- **Splash** (`lib/core/splash/brand_splash.dart`): the Android window is
  plain brand plum (`res/values/colors.xml`, `launch_background.xml`,
  `values-v31` with a transparent system-splash icon), and the animation
  itself runs in Flutter above the Navigator (`MaterialApp.builder`): the
  mark builds in, wordmark and tagline lift under it, then the overlay
  fades to reveal whatever the auth bootstrap resolved to underneath.
  Same reasoning as visitorX: the OS dismisses its own splash on
  Flutter's first frame, too early to see anything. Plays once per
  process and resumes from elapsed wall-clock time on start-up rebuilds
  (unit-tested with an injectable clock).
- **Launcher icon**: rendered *from the same painter* by
  `tool/brand/render_launcher_icons_test.dart` (`flutter test
  tool/brand/...`), which writes the legacy `ic_launcher.png` tiles and
  the adaptive `ic_launcher_foreground.png` layers for every density; the
  adaptive background is the gradient in
  `res/drawable/ic_launcher_background.xml`. Re-run it whenever the mark
  changes — the icon can never drift from the in-app brand.
- **Screens touched** (widgets only, no state/business logic): auth entry
  (gradient hero + pill toggles + coral CTA), OTP, discovery (today's-voice
  card with waveform header, round Pass/Interested actions), match
  (full-bleed gradient), reveal (photo card), conversations (tiles,
  gradient avatar fallback), message thread (asymmetric bubbles, pill
  composer), onboarding completion, placeholders, and the shared
  `EmptyState` used for every empty/error/coming-soon state.

Verified: `flutter analyze` 0 issues, 54 mobile tests (theme, mark
painter, wordmark, waveform, splash sequence + resume), debug APK built
(app + new adaptive icon). The phone that was attached earlier in the day
had been unplugged by the time this build finished, so the refreshed UI
and the animated splash have NOT yet been seen on a real device — first
`flutter run` is the owed check.

### Structure

```
lib/
  core/       app config (dart-define based), theme + branding (Afterglow,
              see below), brand splash, push notifications, a single
              AppException type
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
    trust_safety/ WP6: not a screen -- TrustSafetyRepository
                  (blockUser/reportUser) plus two reusable dialogs,
                  confirmAndBlockUser() and showReportDialog(), used FROM
                  reveal/, messaging/, and live_snap/ rather than being a
                  destination of their own. trust_safety_screen.dart (the
                  original placeholder) is still unused.
    voice_date/, premium/
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
- **WP6** — Admin concept: a plain `isAdmin` boolean on `User`, confirmed
  explicitly rather than assumed (manually set for MVP, no self-serve
  promotion flow, no role/RBAC system). Message history on block: kept,
  not retroactively deleted/hidden, confirmed explicitly too — the
  existing access-control allowlist already cuts off read/send the
  instant a connection goes `BLOCKED`, so there's nothing left for a
  separate "hide history" step to do. `report()`/`block()` kept fully
  independent (reporting never blocks, blocking never requires a report
  on file) — see the Moderation section above for the full reasoning.
- **WP7** — Firebase project: NOT created from this session (account-level
  action, left to the owner); everything is built so that dropping in the
  two config files is the only remaining step. Mutual-match push: kept
  anonymous on purpose, extending "hear before you see" to the lock
  screen. Delivery policy: always push a new message, even to a user
  whose socket is connected — Android keeps a background socket alive
  for minutes, and "connected" is not "looking at the thread"; the mobile
  side suppresses only the one redundant case (open thread, foreground).
  Push failures never fail the triggering action.

## Suggested next steps (WP7+)

- Calling (voice/video, not just Live Snap's one-time check) once a
  Connection reaches `AUTHENTICATED_MATCH`/`ACTIVE` — `realtime` has the
  WebRTC signaling groundwork (WP4) but nothing wired up for an
  on-demand call the way Live Snap's is for the one-time check.
- A TURN server for Live Snap (and any future calling) — STUN-only today
  means a call can fail to connect behind a restrictive/symmetric NAT.
- Push notifications: built in WP7 — what remains is the Firebase
  project + service-account key and the first real on-device delivery
  (see "What WP7 still needs from you"). iOS APNs is untouched.
- An admin UI for the moderation queue (WP6 is REST-only, per an explicit
  decision not to build more than a small addition without asking first)
  and moderator tooling beyond a manual `actionReport()` decision per
  report (no automated action, no escalation workflow).
- Billing/premium — `billing/` is still a stub; `User.tier` exists (WP3)
  but nothing sets it from a real payment yet.

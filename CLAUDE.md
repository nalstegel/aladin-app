# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Aladin** is an internal Flutter app (Android + iOS) for a Slovenian carpet-cleaning
business, used only by employees. It replaces paper logs for order intake, per-rug
production tracking (wash → dry → measure/price → ready), and proof-of-return
(customer signature). The UI, docs, and domain terms are in Slovenian.

Read [plan.md](plan.md) fully before making non-trivial changes — it is a living
project log (owner decisions, exact done/not-done status, gotchas) that a fresh agent
session should read before touching code. [README.md](README.md) is the shorter
user-facing description of the domain model with a diagram of the status flow.

## Core invariant — read this before editing status logic

An **order** (`WorkOrder`) bundles one or more **rug items** (`RugItem`), each with
its own QR-coded ID (e.g. `1847-2`) and its own status
(`awaitingPickup → awaitingWash → drying → finishing → ready → returned`).

**An order's status is never set directly — it is always derived from its items'
statuses.** `Repository._recompute()` in [lib/data/repository.dart](lib/data/repository.dart)
is the *only* place allowed to set `order.status`, and every mutation method in
`Repository` ends by calling it. If you add a new rug/order status or transition,
update `_recompute()` and the corresponding tests in
[test/production_flow_test.dart](test/production_flow_test.dart).

## Commands

```bash
flutter pub get                 # install deps
flutter test                    # run all tests
flutter test test/production_flow_test.dart   # run one test file
flutter analyze                 # must report zero issues
flutter run                     # run the app (seeds demo data on first launch)
```

If `flutter analyze` crashes with a `FormatException`, the project path likely
contains a curly apostrophe (e.g. an iCloud `Desktop - Nal's MacBook Air` folder);
`dart analyze` gives the same result without crashing.

**Never boot a simulator/emulator or run `flutter run` yourself** to visually verify
UI changes — the owner checks those manually. Rely on `flutter analyze`/`flutter
test` and code review instead; if visual verification is genuinely needed, ask
first.

Release builds (Android only, signed + minified):
```bash
./tool/release_android.sh "opis sprememb"   # builds arm64 release, uploads to Firebase App Distribution
```
Requires `android/key.properties` (gitignored) pointing at a real keystore — see
plan.md §4.3 for one-time owner setup. Never let a debug-signed APK reach employees
(Android can't upgrade an install across signing keys).

Firebase console actions (`flutterfire configure`, `firebase login`, `firebase
deploy`, enabling Auth providers) require the owner's Google login and cannot be
done by an agent — surface the exact command for the human to run instead.

## Architecture

```
lib/
  models/      immutable data classes (WorkOrder, RugItem, Customer, AppUser,
               catalog types, ReturnProof, StatusEvent) — no logic beyond
               computed getters (e.g. RugItem.m2/basePrice/computedPrice)
  data/
    repository.dart   StateNotifier<AppState>; ALL mutations go through here
    app_state.dart     immutable snapshot of the whole app + lookup helpers
    store.dart         DataStore abstract interface — the backend abstraction
    auth.dart          AuthService (Firebase email/password sign-in)
    alerts.dart        bell alerts derived from order state; seen-state per device
    push.dart          FCM, topic-based (see functions/)
    navigation.dart    shell/orders tab providers, for cross-tab deep links
    seed.dart          demo data
    providers.dart     Riverpod providers built on repositoryProvider
  ui/
    dashboard/     "Danes" (Today) — 5 tappable tiles, inline Prevzemi/Vrni actions
    orders/        Aktivna/Zaključena tabs + filter sheet (channel + step)
    rugs/          single rug: measure sheet, finish sheet (extras/discount/price)
    scanner/       scanner TAB (live camera) + work lists + ScanCaptureScreen
    customers/     CRM (auto-built from order history)
    notifications/ bell alert list
    more/          menu hub: rug types, extras, stats, users, settings, backup, help
  core/          theme (Inter, fixed color per status), Fmt, scan-code normalization
functions/       Cloud Functions for push — NOT deployed, see functions/README.md
```

Bottom nav has 5 tabs; the scanner is tab index 2 (the centre button), not a
pushed route. Its camera only runs while that tab is selected — `ScannerScreen`
takes an `active` flag from the shell for exactly this reason. The pushed
full-screen scanner still exists as `ScanCaptureScreen`, used by the return flow.

**Backend is Firebase** (Firestore + Storage), behind the `DataStore` interface in
`store.dart`. `FirestoreStore` is the live implementation; `LocalStore` (device JSON)
and `InMemoryStore` (tests) remain as reference/test implementations. `Repository`
and all UI code are backend-agnostic by design — never make them depend on which
`DataStore` is active.

Two non-obvious things in the live-sync path (`FirestoreStore.watch()` /
`Repository.init()`), don't touch without understanding why:
- The incoming remote snapshot is assigned to `state` directly, never through
  `_commit` — otherwise every received snapshot would get written straight back to
  Firestore and phones would bounce writes off each other forever.
- The remote state is merged as `remote.copyWith(currentUserId: state.currentUserId)`
  — `currentUserId` (which employee is signed in on *this* phone) is deliberately
  device-local (`SharedPreferences`/Firebase Auth session), never synced, so an
  incoming snapshot doesn't log other phones' employees out.

Auth: one Firebase account per employee, email + password, no self-registration.
New accounts are always created as `worker` — nobody can self-assign `admin` (see
`firestore.rules`, and plan.md §4.2 for why an earlier draft was unsafe). Admins
manage roles in Nastavitve → Zaposleni. `AppUser.id` is the Firebase UID.

`main.dart` wires `_AuthGate` (signed in?) → `_DataGate` (data loaded + account
bound to an `AppUser` via `Repository.bindAuthUser`) → `AppShell`.

## UI conventions (added in the 2026-08-29 redesign, plan.md §4.4)

- **Status labels live only in `enums.dart`.** Never hardcode a status string in
  a screen — the redesign renamed several (READY → Pripravljeno, Sušenje →
  V sušenju, Osebni prevzem → Pripeljano) and hardcoded copies would drift.
- `RugStatus.doneLabel` is the *past-participle* form ("oprano"), separate from
  `.label` ("Na pranju"). Order-card progress uses `StageProgress` in
  `ui/widgets/common.dart`: it measures how many rugs have *passed* the step
  most of them are stuck in, which is why it reads "3/8 oprano" and not
  "5/8 na pranju". Covered by `test/stage_progress_test.dart`.
- Shared widgets to reuse rather than re-roll: `AppCard` (has an `accent` left
  bar), `PageHeader`, `MenuGroup`/`MenuRow`, `FilterPill`, `SearchField`,
  `AvatarCircle`, `StatusChip`, `StageProgressBar`, `PlainProgressBar`.
- Any button that completes a return must go through `ReturnFlowScreen`. The
  dashboard's "Vrni" only opens it — the scan-every-item-then-sign gate is the
  feature, not an obstacle to route around.

## Current known-incomplete areas (check plan.md §4 for the current state)

- iOS Firebase config was written on a machine without Xcode and has never been
  built/run — verify before assuming it works.
- Real-time sync across two physical phones and the signature→Storage upload path
  are implemented and tested against a fake store, but not yet verified against
  live Firebase on real devices.
- Firestore/Storage security rules exist but must be deployed
  (`firebase deploy --only firestore:rules,storage`) — treat them as not-yet-live
  until confirmed.
- Push notifications are written but **not functional**: Cloud Messaging isn't
  enabled, the project isn't on Blaze, and `functions/` has never been deployed.
  See `functions/README.md`. The in-app bell works regardless — it derives
  alerts from data already in the database.
- `ui/more/support_screen.dart` has empty contact constants. Nobody has supplied
  a support phone/email; the screen says so rather than inventing one.

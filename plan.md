# Aladin — Project Plan & Continuation Guide

> **Read this whole file before touching code.** It is written so an AI agent
> (or a human) opening this directory cold, with zero prior conversation
> history, can understand what this app is, why it's built the way it is, and
> exactly what to do next. If you are an AI agent: after reading this, also
> skim `README.md` (user-facing docs) and `lib/data/repository.dart` (the
> single source of truth for business logic) before making changes.

## 1. What this app is

**Aladin** is an internal operations app for a carpet-cleaning business
(Slovenian company). It is used **only by employees** (washers, front-desk
staff, drivers, admin) — never by customers. It replaces paper logs for:

- tracking pickups/deliveries by day (was a handwritten sheet)
- tracking each individual rug through wash → dry → measure/price → ready
- proving to a customer, with a signature, that their rugs were actually
  returned (the business had disputes about this before)

The original spec (in Slovenian, from the business owner) is preserved
verbatim at the bottom of this file in **Section 6**, because it is the
ground truth for *why* the data model and screens are shaped the way they
are. If any future requirement seems ambiguous, re-read Section 6 first.

### Core domain concept (do not violate this when extending the app)

An **order** (`WorkOrder`) is a bundle of one or more **rug items**
(`RugItem`). Each rug item:

- has its own ID like `1847-2` (order number `1847`, piece 2) — this exact
  string is also the QR code payload printed on its label
- moves through its own status independently:
  `awaitingPickup → awaitingWash → drying → finishing → ready → returned`
- **an order's status is NEVER set directly.** It is always *derived* from
  the statuses of its items. See `Repository._recompute()` in
  `lib/data/repository.dart` — this is the one function that decides order
  status, and it runs after every item mutation. If you add a new rug
  status or a new order status, this function must be updated, and it is the
  only place that should ever set `order.status`.

This "status is derived, not set" rule is the single most important
invariant in the codebase. Every UI action (advance, measure, finish,
override) goes through `Repository` methods that end by calling
`_recompute()`. Never add code elsewhere that sets `WorkOrder.status`
directly.

## 2. Tech stack and why

- **Flutter** (chosen over React Native / native — user asked "is Flutter a
  good idea?" and this was confirmed). One codebase for Android + iOS.
- **Riverpod** (`flutter_riverpod`) for state. `lib/data/repository.dart` is
  a `StateNotifier<AppState>`; all providers in `lib/data/providers.dart`
  derive from it.
- **mobile_scanner** for QR scanning (MLKit-backed, works well on both
  platforms).
- **signature** package for the finger-signature capture on return.
- **pdf** + **printing** packages for generating/printing the A4 sheet of QR
  labels (3×6 grid per page).
- **qr_flutter** for on-screen QR previews.
- **Firebase (Firestore + Storage)** is the live backend as of 2026-08-26
  (`lib/data/store.dart` → `FirestoreStore`). `LocalStore` (JSON on device)
  still exists in the same file but is no longer wired up. See Section 4.1
  for exactly what is and isn't done.

Flutter SDK was cloned to `~/development/flutter` on the original dev
machine (not installed via a package manager) because Flutter wasn't
preinstalled. **On a new PC, check whether `flutter` is on PATH; if not,
either install it normally or clone stable branch as was done before:**
```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/development/flutter
export PATH="$HOME/development/flutter/bin:$PATH"
```
Android Studio + Android SDK + an emulator (`Resizable_Experimental` AVD) was
used for testing since **Xcode is NOT installed** on the original dev
machine (only Command Line Tools). iOS has never been built or tested —
only prepared for (see Section 3).

## 3. Current status: what is DONE

The app is a **fully working, locally-persisted prototype**. It has been
manually tested end-to-end on an Android emulator by simulating a real
worker's day: creating an order, scanning through wash/dry, entering
measurements, applying extras/discounts, confirming price, scanning all
items back at return time, and signing.

### Done — data model (`lib/models/`)
- `enums.dart` — `OrderChannel` (delivery/dropoff/b2b), `HandoverMode`,
  `OrderStatus`, `RugStatus`, `ExtraKind`, `CustomerType`, `UserRole`. All
  have Slovenian `.label` extensions.
- `customer.dart` — private person or company (B2B), with
  `defaultDiscountPercent` that auto-suggests at pricing time.
- `app_user.dart` — employee (worker/admin), used for "who did this scan".
- `catalog.dart` — `RugType` (price per m², min charge m²) and
  `ExtraTemplate` (named surcharge/discount: percent / per-m² / fixed).
  `AppliedExtra` is the snapshot actually attached to a rug item.
- `rug_item.dart` — the core entity. Computes `m2`, `chargeableM2` (respects
  min charge), `basePrice`, `extrasTotal`, `discountAmount`,
  `computedPrice`, `price` (uses `confirmedPrice` once set). Has `history:
  List<StatusEvent>` for full audit trail.
- `order.dart` (`WorkOrder`) — bundles items, tracks channel, handover mode,
  pickup/delivery/due dates, `returnProof`.
- `return_proof.dart` — the return fail-safe record: timestamp, employee,
  scanned item IDs, signature (base64 PNG), receiver name, or an admin
  override reason if no signature was possible.
- `status_event.dart` — one history entry (status, timestamp, user, note).

### Done — business logic (`lib/data/`)
- `app_state.dart` — immutable snapshot of everything (customers, orders,
  items, catalogs, users, `nextOrderNumber`). Has convenience lookups
  (`order(id)`, `itemsOf(orderId)`, `readyCount`, `orderTotal`, etc).
- `repository.dart` — **all mutations go through here.** Key methods:
  `createOrder` (also generates all `RugItem`s + QR IDs at once),
  `addItemToOrder`, `markOrderPickedUp`, `advance` (simple one-step
  transitions), `setMeasurements` (dry→finishing step, snapshots rug type
  price/min-charge onto the item), `finishItem` (applies extras/discount,
  confirms price, → ready), `sendBackToWash` (re-wash, clears confirmed
  price), `overrideStatus` (admin manual fix), `completeReturn` (writes
  `ReturnProof`, marks items `returned`, order `completed`). Ends every
  mutation with `_recompute()`.
- `store.dart` — `DataStore` **abstract interface** with two
  implementations: `InMemoryStore` (used by tests) and `LocalStore` (writes
  JSON to app documents directory via `path_provider`). **This is the
  abstraction point for the Firebase migration — see Section 4.**
- `seed.dart` — demo data matching the original spec's example (order
  `#1847`, customer Janez Novak, 3 items, 2 ready + 1 drying), plus several
  other orders covering every channel/status combination, and a full
  catalog (5 rug types, 8 extra templates), 3 demo users (Nal=admin,
  Marko/Ana=workers).
- `providers.dart` — Riverpod providers: `repositoryProvider`,
  `bootstrapProvider` (loads persisted state or seeds on first run),
  `currentUserProvider`, channel/status-filtered order lists for the
  dashboard, `productionCountsProvider`, `overdueOrdersProvider`, etc.

### Done — UI (`lib/ui/`)
- `login_screen.dart` — email + password sign-in (replaced the old
  `user_picker_screen.dart`, which was deleted — see Section 4.2).
- `shell.dart` — bottom nav: Danes (Today) / Naročila (Orders) / **big
  center QR scan button** / Stranke (Customers) / Več (Settings/More).
- `dashboard/dashboard_screen.dart` — "Today" view: production counts
  (waiting-wash / drying / finishing / ready), overdue orders, today's
  pickups, today's deliveries, awaiting-in-store collections. This replaces
  the paper sheet mentioned in the spec.
- `orders/` — `orders_screen.dart` (3 channel tabs, each with
  active/ready/history filter chips), `order_card.dart`, `new_order_screen.dart`
  (channel + customer search/create + item count + dates + handover mode),
  `order_detail_screen.dart` (full order view, per-item rows, totals,
  return-proof display), `labels_screen.dart` (QR label grid preview +
  A4 PDF print via `printing` package), `return_flow_screen.dart` (the
  fail-safe: must scan every item before "POTRDI VRAČILO" appears),
  `signature_screen.dart` (finger signature + statement text + receiver
  name).
- `rugs/` — `rug_detail_screen.dart` (single item view — this is what
  opens when you scan a QR in "open item" mode; shows status, pricing
  breakdown, full history, the QR itself, and the relevant next-step
  button), `measure_sheet.dart` (width×length or manual m² + rug type
  picker + live price preview), `finish_sheet.dart` (extras checklist +
  discount + manual price override + final confirm → READY).
- `scanner/scanner_screen.dart` — camera QR scanner with two modes: "Odpri
  kos" (open item detail) and "Hitri način" (quick mode — each scan
  auto-advances the item one step, for working at the machine without
  touching the screen).
- `customers/` — `customers_screen.dart` (searchable list, filter by
  private/company), `customer_detail_screen.dart` (auto-built CRM: lifetime
  stats, active orders, history), `customer_form.dart`.
- `settings/settings_screen.dart` — signed-in employee + sign out,
  revenue/order stats, rug type price list editor, extra template editor,
  employee list (admins can edit roles/access there), and an admin-only
  "reset to demo data" button. That reset wipes the **shared** database for
  every employee, not just this phone, so it asks for typed confirmation.
- `widgets/common.dart` — shared components: `StatusChip`, `ReadyProgress`
  (the "2/3 READY" bar), `SectionHeader`, `EmptyState`, `StatTile`,
  `DetailRow`, `AppCard`.

### Done — theming & formatting
- `core/theme.dart` — `AppColors` (fixed color per status, so workers
  recognize state by color without reading), `AppIcons`, full
  `ThemeData`.
- `core/format.dart` — `Fmt` class: Slovenian date/time formatting,
  `Fmt.money`, `Fmt.m2`, `Fmt.dimensions`, `Fmt.dayHeader` (danes/jutri/
  weekday name), `Fmt.pieces(n)` (correct Slovenian plural: kos/kosa/kosi/
  kosov).

### Done — tests
`test/production_flow_test.dart` — 6 tests covering: full order lifecycle
to completion, delivery channel → awaiting-delivery transition, min-charge
area rounding up price, extras+discount math, return proof completion,
re-wash invalidating confirmed price.
`test/sync_test.dart` — 3 tests covering live sync between devices (4.1).
`test/auth_binding_test.dart` — 7 tests covering account binding and role
management (4.2). **All 16 passing.** Run with:
```bash
flutter test
```

### Done — platform prep
- Android: `applicationId "si.aladin.aladin"`, camera permission via the
  `mobile_scanner` plugin's own manifest merge (no extra permission needed
  in app manifest — verify this is still true if the plugin version
  changes).
- iOS: `NSCameraUsageDescription` added to `ios/Runner/Info.plist`
  ("Kamera se uporablja za skeniranje QR etiket na preprogah."). **iOS has
  never actually been built or run** — no Xcode on the original dev
  machine. Bundle ID is `si.aladin.aladin`.

### Verified working (manual test on Android emulator)
Full walkthrough was done and screenshotted: login as employee → dashboard
→ orders tab → order #1847 detail → open rug 1847-3 → measure (250×350cm,
Perzija type → 8.75m² × 22€/m² = 192.50€ base) → finish (added
"Odstranjevanje madežev" +20% → 231.00€) → confirmed READY → order
auto-flipped to "Čaka na prevzem" (2/3→3/3) → opened return flow → all 3
items required before POTRDI VRAČILO appeared → signature screen → order
completed → return proof (timestamp, employee, receiver name, signature
image) displayed correctly on order detail. Two UI bugs found during this
walkthrough were fixed (tab overflow on "Osebni prevzem" label; long
`DetailRow` labels overlapping values) — both already fixed in current
code.

## 4. What is NOT done yet — prioritized

### 4.1 — Firebase backend — MOSTLY DONE (2026-08-26)

Firebase project `aladin-app-d9427` is live and the app writes to it.
Verified on a real Android phone (Samsung SM A725F): first launch seeded
all collections into Firestore successfully.

**Done:**
- `flutterfire configure` run for **Android only** (see iOS caveat below).
  Generated `lib/firebase_options.dart`, `android/app/google-services.json`,
  and updated the Android Gradle files.
- Packages added: `firebase_core`, `cloud_firestore`, `firebase_storage`.
- `Firebase.initializeApp()` wired into `lib/main.dart`.
- `FirestoreStore implements DataStore` written in `lib/data/store.dart`.
  Collections: `customers`, `orders`, `items`, `rugTypes`,
  `extraTemplates`, `users`, plus a `meta/counters` doc holding
  `nextOrderNumber`. It diffs against the last saved `AppState` and writes
  only changed documents in a batch, so one item scan does not rewrite the
  whole database. `Repository` and all UI files were left untouched, as
  the abstraction intends.
- `storeProvider` in `lib/data/providers.dart` now returns `FirestoreStore()`
  instead of `LocalStore()`. `LocalStore` is still in the file, unused, as
  a working reference implementation.
- Signatures upload to Firebase Storage at `signatures/{orderId}.png`;
  `ReturnProof` gained a `signatureUrl` field and the Firestore document
  no longer carries the inline base64 PNG. `order_detail_screen.dart`
  prefers the URL and falls back to base64 for older records.
- Firestore + Storage security rules exist as `firestore.rules` /
  `storage.rules`, wired through `firebase.json` and `.firebaserc`, and
  deployed with `firebase deploy --only firestore:rules,storage`.

**Deliberate design decision — do not "fix" this without thinking:**
`currentUserId` (which employee is signed in on THIS phone) is **not**
synced to Firestore. It is stored per-device via `SharedPreferences`.
Syncing it would mean one employee picking their name on their phone
silently changes who is logged in on everyone else's phone.

**Real-time sync — DONE in code, NOT yet verified on two phones:**
`DataStore` gained `Stream<AppState> watch()`. `FirestoreStore.watch()`
opens a snapshot listener on all six collections plus `meta/counters` and
emits a combined `AppState` whenever any of them changes; stores that
cannot sync (`InMemoryStore`, `LocalStore`) return an empty stream and the
app behaves exactly as before. `Repository.init()` subscribes to it and
`dispose()` cancels it.

Two things in that code are load-bearing — read before changing it:
- The listener assigns `state` **directly and never calls `_commit`**. Going
  through `_commit` would save every received snapshot straight back to
  Firestore, and the phones would bounce writes off each other forever.
- The received state is merged as
  `remote.copyWith(currentUserId: state.currentUserId)`. Firestore never
  carries `currentUserId`, so without that merge every incoming snapshot
  would log the employee out and bounce them to the user picker.

`test/sync_test.dart` covers all three behaviours (remote change lands,
local user survives, no write-back loop) using a fake store. Worst-case
failure mode of the save-diffing under concurrent updates is a redundant
write, never a lost one.

**Still open under 4.1:**
1. **Sync has only been tested against a fake store, never two real
   phones.** Install on a second device and confirm a status change on one
   appears on the other within a second or two, without restarting.
2. **The signature → Storage upload path has never actually run.** It is
   written and compiles, but no return flow has been completed against
   live Firebase yet. Test a full return + signature and confirm the PNG
   appears in the Storage bucket and renders on the order detail screen.
3. Security rules — now written to require sign-in, see 4.2. **They still
   need deploying**, and the wide-open ones are live until then.
4. **iOS is not configured.** `flutterfire configure` crashed on the iOS
   step (`cannot load such file -- xcodeproj`) because the Ruby gem is
   missing and there is no Xcode on this machine. The iOS app IS
   registered in the Firebase console and `ios/Runner/GoogleService-Info.plist`
   was written, but it is not referenced from the Xcode project and
   `firebase_options.dart` throws `UnsupportedError` for iOS. Re-run
   `flutterfire configure` on a Mac with full Xcode to finish it.
5. `firebase_auth` is back in and building. It had failed with
   `:firebase_auth:compileDebugKotlin` → "Type annotation class
   `UnknownInitialization` is inaccessible". Fixed in
   `android/build.gradle.kts` by adding `checker-qual` as a `compileOnly`
   dependency to every Android library subproject. **Don't delete that
   block** — the build breaks again without it.
6. Firestore's offline persistence is on by default on mobile — the wash
   room has no signal, so do NOT disable it.

### 4.2 — Real authentication — DONE in code (2026-08-26)

Decision made by the owner: **email + password, one account per employee.**
`UserPickerScreen` (tap any name to become them) is **deleted** — do not
bring it back, it made the "who did this scan" audit trail meaningless.

- `lib/data/auth.dart` — `AuthService` (sign in, sign out, password reset)
  with Firebase's error codes translated to Slovenian, plus
  `authStateProvider`. Firebase persists the session per device, so an
  employee signs in once per phone.
- `lib/ui/login_screen.dart` — email + password form.
- `lib/main.dart` — `_AuthGate` (signed in?) wraps `_DataGate` (data
  loaded + account bound to an employee record) wraps `AppShell`.
- `Repository.bindAuthUser()` — links the Firebase UID to an `AppUser`.
  **`AppUser.id` is now the Firebase UID**, so item history points at a
  real account. `AppUser` gained an `email` field.
- **New accounts are always created as `worker`.** Nobody may assign
  themselves a role: an earlier draft made the first account admin
  automatically, which meant the rules had to permit self-assigned roles —
  and anyone could then have set `role: 'admin'` on themselves with a
  hand-written Firebase client and gained the right to wipe the database.
  See the bootstrap step in "Still to do" below.
- Admins manage everyone else in Nastavitve → Zaposleni (name, role,
  access). Employees are never deleted — item history hangs off them — they
  are deactivated with `active: false`.
- `Repository` no longer stores `currentUserId` anywhere itself, and
  `FirestoreStore` no longer keeps it in `SharedPreferences` — Firebase
  Auth is the single source of truth for who is signed in on a device.
- Settings: "Zamenjaj" (switch user) replaced by "Odjava" (sign out).
- `test/auth_binding_test.dart` — 7 tests: new accounts are workers,
  admin can change role/access, re-login doesn't overwrite an assigned
  role, re-login doesn't duplicate, name derived from email, history
  attributed to the account, sign-out clears.

**Security rules are now closed** (`firestore.rules`, `storage.rules`):
everything requires `request.auth != null`. Three deliberate details, each
guarding against a specific hole:
- On `users/{uid}`, self-`create` is allowed **only with `role: 'worker'`**
  and self-`update` **only if `role` and `active` are unchanged**. Otherwise
  any employee could promote themselves to admin.
- Admins may write any user document; this is checked with a `get()` on the
  requester's own user doc. That costs one extra read per user write, which
  is fine because role changes are rare.
- Storage grants `create, update` but **not** `delete` on signatures.
  Rules are a permissive union, so writing `write` would have silently
  re-allowed deleting the only proof a delivery happened.

**Still to do for 4.2 — in this order:**
1. **Enable Email/Password** in the Firebase console (Authentication →
   Sign-in method) and **create an account per employee** there. There is
   deliberately no self-registration in the app.
2. **Deploy the rules** — until then the wide-open ones are still live:
   `firebase deploy --only firestore:rules,storage`
3. **Bootstrap the first admin by hand.** Sign in once in the app so the
   `users/{uid}` document is created, then in the Firestore console edit
   that document and set `role` to `admin`. Only after this can anyone use
   Nastavitve → Zaposleni to manage the rest. Skipping this leaves the
   company with no admin and no way to appoint one.
4. Never run on a real device — the whole login → bind → shell path is
   unverified.
5. The seeded demo employees (`u-nal`, `u-marko`, `u-ana`) still exist with
   no account attached. Harmless, but tidy them up before going live.
6. Beyond the user documents, roles are enforced only in the UI (the
   reset-data button is admin-only). If e.g. only admins should edit the
   price list, add that to `firestore.rules` too — hiding a button is not
   access control.

### 4.3 — Distribution (no App Store / Play Store)
Business owner explicitly does NOT want to publish to public stores (this
was discussed at length in this conversation — see chat history if
available, otherwise re-derive from first principles below).

#### Android — build side DONE (2026-08-26), setup steps left for the owner

Release builds are wired up and a signed-release build has been verified to
compile with R8 minification on (the usual place release builds break).

- `android/app/build.gradle.kts` reads `android/key.properties` (gitignored)
  and signs with it. **If that file is missing it falls back to the debug
  key and prints a warning** — handy for `flutter run --release`, but such
  an APK must never reach employees: Android refuses to upgrade an install
  when the signing certificate changes, so they'd have to uninstall (losing
  nothing, since data is in Firestore, but it's avoidable friction).
- `android/app/proguard-rules.pro` keeps the Firebase and MLKit classes
  that are loaded by reflection. Without these, a release build compiles
  fine and then **silently fails at runtime** — QR scanning is the first
  thing to break. Do not trim this file casually.
- `tool/release_android.sh "opis sprememb"` builds and uploads to App
  Distribution. It refuses to run without a keystore, and re-verifies with
  `apksigner` that the output isn't debug-signed before uploading.
- It builds `--target-platform android-arm64` only: ~30 MB instead of the
  ~75 MB universal APK. Every phone from the last several years is arm64.
  If a genuinely old 32-bit device ever needs it, drop that flag.

**Owner's one-time setup, in order:**
1. Generate the keystore (choose your own passwords — never commit them):
   ```bash
   keytool -genkey -v -keystore ~/keys/aladin-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias aladin
   ```
   **Back this file and its passwords up somewhere safe and permanent.**
   Losing it means no existing install can ever be updated again — every
   employee would have to uninstall and reinstall.
2. Create `android/key.properties` (already gitignored):
   ```
   storePassword=<geslo>
   keyPassword=<geslo>
   keyAlias=aladin
   storeFile=/Users/<ti>/keys/aladin-release.jks
   ```
3. In the Firebase console, enable **App Distribution** and create a tester
   group named `zaposleni`, adding each employee's email.
4. Bump the build number in `pubspec.yaml` (`1.0.0+1` → `1.0.0+2`) for
   every release — App Distribution treats an unchanged build number as
   the same release.
5. Run `./tool/release_android.sh "kaj je novega"`.
- **iOS**: no sideloading equivalent exists (Apple hard-blocks unsigned
  apps at the OS level — not a setting that can be toggled). Options
  discussed:
  - **TestFlight** (requires $99/year Apple Developer Program): internal
    testers (up to 100), no UDID collection needed, but each build
    **expires after 90 days** — needs a new build uploaded periodically
    (can literally just bump the build number with zero code changes to
    reset the 90-day clock; version stays e.g. `1.0.0+1` → `1.0.0+2`).
  - **Ad Hoc distribution** (same $99/year): requires collecting each
    iPhone's UDID into the provisioning profile once, but the resulting
    `.ipa` can be installed via a direct link (no TestFlight, no 90-day
    limit) and the profile lasts a full year.
  - Enterprise Program ($299/yr, needs 100+ employees) and the EU web
    distribution route are NOT viable for a 5-person business — ruled out.
  - **This decision (TestFlight vs Ad Hoc) has not been finalized by the
    owner yet.** Either requires an Apple Developer account, which
    requires the owner's own Apple ID — cannot be set up by an agent.
- Building for iOS at all requires a Mac with **Xcode installed** (not
  just Command Line Tools, which is all that's on the original dev
  machine). This must happen on a Mac that has Xcode before any iOS work
  can proceed.

### 4.4 — Nice-to-have, not urgent
- SMS/email confirmation to customer after return (spec mentions this as
  "po želji" / optional). Needs a third-party service (Twilio/SendGrid or
  similar) and the owner's account — not started, low priority.
- Admin UI polish for catalog/employee management is minimal but
  functional; could be expanded if the owner wants more control without
  code changes.

## 5. How to resume work in a fresh session

1. Read this file fully.
2. Check `flutter --version` works; if not, see Section 2 for how Flutter
   was installed on the original machine.
3. Run `flutter pub get`, then `flutter test` to confirm the baseline
   still passes before changing anything.
4. Run `flutter analyze` — should report **zero issues**; keep it that way.
   If it crashes with a `FormatException` from the analysis server, the
   project path contains a curly apostrophe (the iCloud
   `Desktop - Nal’s MacBook Air` folder). `dart analyze` works fine and
   gives the same result; moving the project out of iCloud fixes it.
5. Firebase is already set up and live — read 4.1 for the exact state
   before touching it. Anything needing the owner's Google login
   (`flutterfire configure`, `firebase login`, enabling billing, changing
   console settings) **cannot be done by an agent — ask the human.**
   Note `firebase deploy` may also be blocked for agents; hand the human
   the command instead.
6. Never make `Repository` or UI files depend on which `DataStore` is
   active — that separation is intentional and is the main thing that
   makes this codebase easy to extend.
7. If adding new rug/order statuses or transitions, update
   `Repository._recompute()` and the corresponding tests in
   `test/production_flow_test.dart`.

## 6. Original spec (verbatim, Slovenian) — ground truth for requirements

Evo, ta slika je približno vizualizacija tega, kar imam v mislih. Na izi bi
sistem deloval tako:

**1. ZGORAJ = NAROČILA / OFFICE**
Imamo 3 glavne kategorije:
- DOSTAVA – stranke, kjer mi pobiramo in vračamo preproge. Tukaj bi imel po
  dnevih napisano, kdo je za prevzem in kdo za vračanje, naslov, okvirno uro
  in št. kosov. To bi mi zamenjalo list, kamor zdaj pišem vse prevzeme in
  dostave.
- OSEBNI PREVZEM – ljudje, ki sami pripeljejo preproge. Ko pride stranka,
  naredimo naročilo, vpišemo podatke in koliko kosov je pustila. Ko so vsi
  tepihi končani, se naročilo avtomatsko pojavi pod ČAKA NA PREVZEM.
- B2B – hoteli, firme, ustanove itd. Isti princip, samo da ima firma svoj
  profil, aktivna naročila in zgodovino.

Vse troje so v bistvu samo različni načini, kako naročilo pride v isti
sistem.

**2. SPODAJ = POSAMEZNA PREPROGA / PROIZVODNJA**
Vsak tepih znotraj naročila ima svojo QR etiketo. Primer, če ima Novak 3
tepihe: #1847-1, #1847-2, #1847-3. Na etiketi bi bilo ime, št. naročila,
npr. KOS 2/3 in QR. Ko skeniraš QR, se vedno odpre direktno ta konkretni
tepih, ne samo celo naročilo. Po pranju ga skeniraš → SUŠENJE. Ko pride iz
sušilnice, ga spet skeniraš in vneseš mere + vrsto/material. App iz tega
izračuna m² in osnovno ceno. Na končnem sesanju pa dodamo še morebitna
doplačila/popuste glede na to, kaj se je dejansko delalo, potrdimo končno
ceno in damo READY.

**3. APP SAM SESTAVLJA NAROČILO**
Če ima Novak 3 kose in je stanje: 1847-1 READY, 1847-2 READY, 1847-3
SUŠENJE — kaže 2/3 READY in celo naročilo še ni pripravljeno. Ko je 3/3
READY, se avtomatsko prestavi: če je stranka sama pripeljala → ČAKA NA
PREVZEM; če smo mi pobrali → ČAKA NA VRAČILO; če je B2B → pod ustrezno B2B
naročilo. Tako vedno vemo, kateri konkretni tepih manjka.

**4. FAIL-SAFE PRI VRAČILU**
To bi rad še zaradi dokazila, da smo preproge dejansko vrnili. Ko stranka
pride po preproge oziroma jih dostavimo, odpremo naročilo in pred
zaključkom poskeniramo QR-je vseh kosov: 1/3 ✓, 2/3 ✓, 3/3 ✓. Šele ko so
vsi poskenirani, se pojavi POTRDI VRAČILO. Potem se na telefonu odpre mini
okno: "Potrjujem prevzem 3 preprog iz naročila #1847." Stranka se s prstom
podpiše direktno na telefon. Sistem potem shrani: datum in uro vračila, 3/3
vrnjene kose, kdo od zaposlenih je izvedel vračilo, podpis stranke. Po
želji lahko stranka avtomatsko dobi še SMS/email potrdilo, da je bilo
naročilo vrnjeno. Če podpisa iz nekega razloga noče/ne more dati, bi imeli
admin override z razlogom, da nikoli ne blokiramo naročila. Tako imamo
dejanski digitalni dokaz vračila in ni več situacije, da čez en mesec
nekdo reče, da tepihov ni dobil nazaj.

**5. GLAVNA LOGIKA**
```
WAITING FOR PICKUP
        ↓
ČAKA NA PRANJE
        ↓
SUŠENJE
        ↓
MERE + VRSTA + KONČNA OBDELAVA/CENA
        ↓
READY
        ↓
ČAKA NA PREVZEM / VRAČILO
        ↓
SCAN VSEH KOSOV + PODPIS
        ↓
VRNJENO / ZAKLJUČENO
```

Poanta je, da s tem zamenjamo praktično vse sedanje liste in ročno
evidenco, hkrati pa se v ozadju avtomatsko gradi še CRM in zgodovina vsake
stranke.

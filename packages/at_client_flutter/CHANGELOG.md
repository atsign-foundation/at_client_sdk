# CHANGELOG

## 2.0.0-rc1

The dialogs and the keychain build on at_client's lifecycle verbs
(`Atsign.open`, `activate`, `enroll` and `resumeEnrollment`, and
`client.enrollments` on the approving side) and hand back the `AtClient` they
open. An app imports `package:at_client_flutter/at_client_flutter.dart` and
nothing from at_auth.

- BREAKING: `AuthService` and `FlutterEnrollmentService` are gone; what they
  orchestrated is at_client's. `authenticate`, `onboard` and `enroll` are
  `PkamDialog`, `CramDialog` and `ApkamActivationDialog`, or `Atsign.open`,
  `activate` and `enroll` for an app with its own UI; list, approve, deny and
  revoke are `client.enrollments`, and the request stream is
  `client.enrollments.requests`.
- BREAKING: `PkamDialog.show`, `CramDialog.show` and
  `ApkamActivationDialog.show` return the `AtClient` they open, null when the
  dialog fails or is cancelled, and take the atSign, the keys store, the
  `AtClientPreference` and an optional `AtClientStorage` in place of the
  at_auth request objects. `onAuthenticationComplete` and
  `onOnboardingComplete` are invoked with the client. The app owns the client:
  `AtClientManager.getInstance().use(client)` makes it the current one for an
  app whose screens read it from there.
- BREAKING: `AtSignSelectionDialog.show` returns an `AtsignSelection`, the
  atSign and its root domain, and `RegistrarCramDialog.show` takes the atSign.
- BREAKING: `ApkamActivationDialog` opens the client itself once the approval
  lands; there is no second `PkamDialog` to show. Its `atKeysIo` is now
  `keys`, where the enrollment's keys are filed and read back from, the
  keychain by default. A request submitted earlier for the same app and device
  is resumed from that store rather than repeated, so the passcode is asked
  for only when nothing is pending. `signingAlgo` and `keyExchangeMode` name
  the enrollment's algorithm and key exchange, defaulting to the preference's.
- BREAKING: `EnrollmentRequestList` takes an optional `atClient` and works
  over `client.enrollments`; with none it uses `AtClientManager`'s current
  client, as it always has. Its cards render at_client's `Enrollment`, whose
  `namespacePermissions` and `enrollmentStatus` are what they read.
- BREAKING: the keychain holds keys only. `EnrollmentData`, `Otp` and
  `KeychainStorage`'s `readEnrollmentData`, `writeEnrollmentData`,
  `deleteEnrollmentData`, `validateEnrollment` and `saveSpp` are gone: an
  enrollment awaiting approval lives in the keys store as pending key
  material, which is how it is resumed.
- `RegistrarService` is re-exported, so an app driving `RegistrarCramDialog`
  imports nothing from at_auth; `FileAtKeysIo`, `AtKeysIo`, `WrittenAtKeysIo`,
  `InMemoryAtKeysIo`, `NamespacePermission` and `EnrollmentKeyExchangeMode`
  come through at_client.
- fix: the enrollment request list can approve a pq-mode request, whose
  enrollee expects the approver to mint its key and so wraps none; the old
  approve action null-banged the wrapped key and crashed before anything was
  sent. A post-approval conveyance refusal clears the row and shows the
  refusal's own message — approved, cannot decrypt, consider revoking —
  instead of `Failed to approve`, which invited a retry of an approval that
  had already gone through.
- fix: an atSign names one keychain entry however the caller spells it.
  `write('@Alice', …)` succeeded and the very next `read('@Alice')` reported
  the atSign as absent, and a `flush` under a spelling that normalizes
  differently (`@colin.constable` → `@colinconstable`) appended beside the
  entry and left the newer keys unreachable behind the older ones.
  `KeychainStorage` compares normalized in `_indexOf` and
  `removeAtsignFromKeychain`, and still returns the stored spelling; a value
  `toAtsign()` rejects is compared as it stands, so a malformed entry stays
  readable and removable.
- fix: a failed keychain read no longer wipes the store. The read's error
  path wrote an empty entry over the stored data before rethrowing, so a
  transient platform-channel error or a cancelled biometric prompt destroyed
  the only copy of the atSign's keys. Recovery from a genuinely corrupt store
  is now the caller's explicit decision, never a side effect of the read that
  discovered it.
- fix: the keychain is a usable key store for the post-quantum paths.
  `KeychainAtKeysIo` implemented only `read`/`write`, so `flush` fell through
  to the interface's throwing default — and on Flutter that is the *default*
  store, so filing an nskey private or a signing-root private threw
  `UnimplementedError` on the platform where those paths matter most. It now
  replaces the atSign's entry, with the same never-lose assurance the `.atKeys`
  file gets, and implements `update` through it.
- fix: `KeychainAtKeysIo.write` refuses an atSign that already has an entry,
  like every other `WrittenAtKeysIo`. It used to append unconditionally to a
  list `read` scans front-to-back, so a second write left the newer keys
  permanently unreachable behind the older ones — a silent loss that looked
  like a successful write. Use `flush` to persist a change to existing keys.
- fix: an entry written by an older release, which carries its atSign under the
  `name` metadata key rather than `atsign`, is now found, replaced and removed
  by the same predicate the reads use. `getAllAtsigns` threw a `TypeError` on
  one (a `String` used as a condition) and `removeAtsignFromKeychain` silently
  kept it.
- The examples (`example/`, `examples/todos`, `examples/dockerstats`) build
  their flows on the dialogs and hand the client to `AtClientManager.use`;
  the APKAM example's simulated requester runs on `client.enrollments.otp()`
  and `Atsign.enroll`.
- build: requires `at_client` ^3.15.0-rc1, the first version carrying the
  lifecycle verbs.
- fix: `KeychainAtKeysIo.read` throws `AtKeysSourceAbsentException` for an
  atSign the keychain does not hold, as the file store does, so `Atsign.enroll`
  and `resumeEnrollment` start on a fresh keychain rather than refusing it as
  unreadable.

## 1.1.4

- feat: `AuthService.onboard` / `authenticate` accept an optional `timeout` that
  bounds the whole onboarding/auth attempt (sets `RetryOptions.overallTimeout`;
  otherwise the process-wide `AtNetworkTimeouts` default applies). Requires
  `at_auth ^3.2.0` (#1909).
- fix: `FlutterEnrollmentService.enroll` no longer leaks the `AtLookupImpl`
  connection when the enrollment submit fails — it now closes in a `finally`.
- fix: `CramDialog` and `PkamDialog` no longer hang forever when
  onboarding/authentication throws (e.g. the atServer is unreachable). Both now
  handle the error path — surface a user-friendly message and pop the dialog —
  so `.show()` always completes. On an `AtTimeoutException` the onboarding
  dialog explains the atSign may still be provisioning rather than reporting a
  hard failure; `ApkamActivationDialog` likewise catches enrollment errors and
  distinguishes a timeout from a failure instead of leaking an unhandled
  exception (#1905, #1909).
- fix: `CramDialog` / `PkamDialog` now start onboarding/authentication once in
  `initState` instead of from `build`, so a widget rebuild during the wait can
  no longer spawn a second attempt; and their default loading view surfaces live
  `progressStream` messages instead of static text, so a multi-minute
  provisioning wait shows real progress.

## 1.1.3

- fix: force uppercase on OTP/CRAM input fields so lowercase or pasted alphanumeric codes no longer fail validation
- fix: switch APKAM dialog keyboard to visible-password so letters can be typed

## 1.1.2

- fix: prevent blank dialog box flashing during login
- fix: remove phosphor_flutter dependency which fails to build on Flutter 3.44+, now using a built-in icon
- docs(examples): improved READMEs, added dockerstats flutter app

## 1.1.1

- refactor: updated example app deprecated methods.
- fix: example app over flow error fixed.
- fix: APKM Dialog scrolls to reveal OTP pin outside of viewport.
- fix: Registrar Dialog scrolls to reveal OTP pin outside of viewport.
- fix: Soft keyboard for Registrar Dialog OTP field is Capitalized by default and set to show numbers and text.

## 1.1.0

- feat: models NamespacePermission, Otp, ServerEnrollmentRequest, AuthorisationException
- feat: additional functionality on FlutterEnrollmentService
- rework: lifecycle on FlutterEnrollmentService
- feat: new widgets for Enrollment related activities
- feat: extensions for additional functionality
- fix: bug where example app consumes atsigns with '\_' inside them

## 1.0.2

- fix(ai): automatically prepend @ symbol into text box

## 1.0.1

- deps: at_auth 3.0.1

## 1.0.0

- feat: `ApkamActivationDialog` introduced for apkam onboarding
- fix: proxy parsing on root domains
- chore: file_picker pinned at 10.3.10
- feat: list to `AtEnrollment`

## 0.1.2

- pin file_picker to 10.3.9 (BC)

## 0.1.1

- chore: removed unused dependencies
  - flutter_keychain
  - hive
  - crypton
  - flutter_riverpod
  - at_persistence_secondary_server
- docs: Update README with more documentation
- fix: broken links in README

## 0.1.0

- Initial version, consolidating in functionality from legacy packages
- feat: `KeychainAtKeysIo` defines authentication via keychain for `at_auth`
- feat: Dialog widgets for flutter applications
- feat: Use case focused services for onboarding

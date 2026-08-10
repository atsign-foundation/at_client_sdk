# CHANGELOG

## 1.1.5
- fix: an atSign names one keychain entry however the caller spells it.
  Nothing normalizes on the way in — `AuthRequest.atSign` is a plain String,
  and at_auth passes that string verbatim to `read`/`write` while passing
  `toAtsign()` to `flush` — so once entries started recording the canonical
  spelling, `write('@Alice', …)` succeeded and the very next `read('@Alice')`
  reported the atSign as absent. Worse for `flush`: an entry stored under a
  spelling that normalizes differently (`@colin.constable` →
  `@colinconstable`) was not found, so the flush appended beside it and left
  the newer keys unreachable behind the older ones. `KeychainStorage` now
  compares normalized in `_indexOf` and `removeAtsignFromKeychain`, and still
  returns the stored spelling; a value `toAtsign()` rejects is compared as it
  stands, so a malformed entry stays readable and removable.
- fix: `EnrollmentRequestList` no longer disposes an `enrollmentService` it
  was given. `FlutterEnrollmentService.dispose()` closes the request stream
  and drops the controller, so routing away from the widget left a caller's
  shared service throwing on every later `getEnrollments()`. It now closes
  only a service it created itself.
- fix: the enrollment request list can approve a pq-mode request. The
  approve action null-banged `encryptedAPKAMSymmetricKey`, which a
  request that expects the approver to mint its key does not carry, so
  every such approval crashed before the service was called; and a
  post-approval conveyance refusal now clears the row and shows the
  refusal's own message instead of `Failed to approve`. The list widget
  gains an injectable `enrollmentService` (the `ApkamActivationDialog`
  pattern) and resolves its `AtClient` through the service's seam.
- fix: an approval whose secret conveyance was refused is no longer
  re-reported as `Enrollment failed`. at_client's `approve()` now throws
  `EnrollmentConveyanceException` after a server-side approval whose
  enrollee advertised an unverifiable key package; `approve()` here finishes
  the approval bookkeeping and rethrows it, so the caller sees the true
  state — approved, cannot decrypt, consider revoking — instead of a
  failure claim about an enrollment that is live.
- fix: a failed keychain read no longer wipes the store. The read's error
  path wrote an empty entry over the stored data before rethrowing, so a
  transient platform-channel error or a cancelled biometric prompt destroyed
  the only copy of the atSign's keys. Recovery from a genuinely corrupt store
  is now the caller's explicit decision, never a side effect of the read that
  discovered it.
- fix: approving an enrollment no longer reports `Enrollment failed: Null
  check operator used on a null value` after the server-side approval has
  succeeded. `approve()` returns no key material — the enrollee files its own
  keys on its own device — and the approver-side keychain write now runs only
  when keys are actually present.
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
- feat: `CramDialog` and `PkamDialog` take an optional `authService`, and
  `ApkamActivationDialog` an optional `enrollmentService`. Both default to the
  real service, so existing call sites are unaffected; passing one lets the
  dialogs' error and timeout paths be widget-tested without a live atServer
  (#1909).
- fix: `FlutterEnrollmentService.approve` waits for the pending enrollment
  record to be dropped. The delete was started and never awaited, so it
  outlived the call that began it and a keychain failure had no caller left to
  catch it — it surfaced as an unhandled async error. It is now awaited under
  its own guard: by the time it runs the atServer has already recorded the
  decision, so a keychain failure logs a warning and costs a pending row that
  lingers until it expires, never a successful approval reported as a failure.
- fix: `approve`, `deny` and `revoke` close the `AtLookUp` they were given even
  when the operation throws. Each closed only after its `try`, so every failure
  path leaked the caller's connection — the same defect fixed in `enroll` in
  1.1.4, in the three methods that still had it.

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

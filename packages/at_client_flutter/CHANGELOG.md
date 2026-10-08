# CHANGELOG

## 2.0.0-rc5

- feat: a dialog given no storage opens Hive in the app's support directory,
  or under `preference.hiveStoragePath` while that is set. An app that kept its
  store anywhere else should pass it as `storage:` before at_client 4.0.
- BREAKING: an app whose preference sets `isLocalStoreRequired` false must
  pass `storage:`, as at_client now refuses a client with no local storage.
- build: requires `at_client` ^3.15.0-rc6.

## 2.0.0-rc4

- fix: an atSign that an app built on at_client_mobile saved to the keychain
  signs in again, instead of failing with "PKAM mode requires
  defaultEncryptionPrivateKey".

## 2.0.0-rc3

- build: requires `at_client` ^3.15.0-rc5 and `at_auth` ^4.0.0-rc4, for their
  fixes to upgrading from at_client 3.14.0.
- feat: `AtSignServerCheck`, `AtSignServerState`, `checkAtSignServer` and
  `AtSignLogger` come through this package, so an app no longer needs at_lookup
  or at_utils for them.
- fix: `ApkamActivationDialog` fails at once for an expired or unknown
  enrollment, rather than after its whole retry budget.
- fix: the package no longer includes Xcode logs from the invitations example.

## 2.0.0-rc2

- build: requires `at_client` ^3.15.0-rc2 and `at_auth` ^4.0.0-rc3, for their
  post-quantum sharing and keyfile lock fixes.

## 2.0.0-rc1

- BREAKING: `AuthService` and `FlutterEnrollmentService` are removed. Use
  `PkamDialog`, `CramDialog` and `ApkamActivationDialog`, or at_client's
  `Atsign.open`, `activate` and `enroll` for an app with its own UI; list,
  approve, deny and revoke are `client.enrollments`.
- BREAKING: the dialogs take the atSign, the keys store, the
  `AtClientPreference`, an optional `AtClientStorage` and `lookUps:` in place
  of at_auth's request objects, and return the `AtClient` they open (null on
  failure or cancel); `onAuthenticationComplete` and `onOnboardingComplete`
  receive it. `ApkamActivationDialog` opens the client itself once approved,
  resumes a pending request for the same app and device, and its `atKeysIo`
  is now `keys`.
- BREAKING: `AtSignSelectionDialog.show` returns an `AtsignSelection`,
  `RegistrarCramDialog.show` takes the atSign, and `EnrollmentRequestList`
  works over `client.enrollments` and renders at_client's `Enrollment`.
- BREAKING: the keychain holds only keys and passcodes. `EnrollmentData` and
  `KeychainStorage`'s enrollment-data methods are removed, since a pending
  enrollment lives in the keys store, and `saveSpp` takes a `Passcode` in
  place of at_auth's `Otp`.
- feat: an app no longer needs at_auth: `RegistrarService` is re-exported, and
  the keys-store types come through at_client.
- feat: keychain entries use `:` as the name delimiter. Keys under the old `_`
  name are copied across, and the `_` copy is kept until 3.0.0.
- fix: the keychain store finds an atSign however it is spelled, keeps its
  contents when a read fails, and finds and removes entries older releases
  wrote; `flush` and `update` work. `write` refuses an atSign that already has
  an entry (use `flush`), and `read` throws `AtKeysSourceAbsentException` for
  one it doesn't hold.
- fix: the enrollment request list approves a post-quantum request instead of
  crashing, and shows a post-approval conveyance refusal's own message.
- docs: the examples in `example/`, `example/todos` and `example/dockerstats`
  use these flows.
- build: requires `at_client` ^3.15.0-rc1, `at_auth` ^4.0.0-rc2 and
  `at_lookup` ^3.7.0-rc2.

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

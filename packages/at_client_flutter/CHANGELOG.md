# CHANGELOG

## 2.1.0-rc.2

- fix: `KeychainStorage.appendAtKeysToKeychain` throws
  `AtKeysFileOverwriteException` for an Atsign the keychain already holds,
  rather than adding keys no read by Atsign reaches. `KeychainAtKeysIo.write`
  adds an Atsign's keys and `KeychainAtKeysIo.update` changes them.
- fix: the keychain stores keys that name their Atsign only in the typed
  field under that Atsign, and refuses keys that name two different Atsigns
  across their typed field and their metadata's `atsign` and `name` entries
  with `AtKeysValidationException`.
- fix: `KeychainStorage.updateAtKeysInKeychain`, and `KeychainAtKeysIo.write`,
  `flush` and `update`, refuse keys naming another Atsign than the one given
  with `AtKeysValidationException`; `updateAtKeysInKeychain` stores keys
  naming none under the one given.
- fix: `KeychainStorage.getAllAtsigns` lists an Atsign stored under two
  spellings once, and lists none for an entry with no typed Atsign and an
  empty metadata `atsign`.
- build: requires `at_commons` ^5.26.0.

## 2.1.0-rc.1

- fix: the dialogs' keys messages, and the one a confirmed Cancel that
  cannot remove the keys shows, name where the keys are, such as "the
  AtKeys store (this device's keychain)".
- feat: `PkamDialog` offers Cancel while it waits on a pending enrollment, as
  `ApkamActivationDialog` does: after the user confirms, it removes the
  request's pending keys from the AtKeys store.
- fix: after a confirmed Cancel, `ApkamActivationDialog` and `PkamDialog` say
  the Atsign's manager can deny the request, or revoke it if they approved it
  already.
- fix: a confirmed Cancel in `ApkamActivationDialog` or `PkamDialog` that an
  approval filed by another wait beat opens the Atsign on that approval,
  rather than saying the request was abandoned.
- fix: `ApkamActivationDialog`, `PkamDialog` and `CramDialog` no longer close
  the screen beneath them when a failure, an approval, a confirmed Cancel or
  the user leaving lands as they close. `ApkamActivationDialog` also closes
  its Cancel confirmation when the wait fails.
- fix: a client a dialog opens after the user has left it goes to the
  dialog's callback (`onAuthenticationComplete`, `onOnboardingComplete`) when
  one is given, and is stopped when none is, so the Atsign can be opened
  again.
- fix: `CramDialog` stops the client it opened when `onOnboardingComplete`
  throws, and no longer throws when the activation reports progress after
  the user has left.
- fix: `ApkamActivationDialog` and `PkamDialog` show a failure when the
  request they wait on is approved after another wait has cancelled it,
  saying the Atsign's manager can revoke the approval.
- docs: the example's APKAM page shows a passcode another device quotes to
  request enrollment, and where to use it, with the `at_activate enroll`
  command at the client's own root, and no longer files a request of its
  own.
- fix: `ApkamActivationDialog`'s resume status shows the enrollment id and
  the names its AtKeys store records with their control characters escaped,
  and both dialogs' Cancel texts and `PkamDialog`'s waiting status show the
  enrollment id the same way.
- fix: `EnrollmentRequestCard`, `AuthorisationFeedbackOverlay` and the
  approved enrollments in `EnrollmentRequestList` show a request's app and
  device names, the card its namespaces, and the list the key an Anchored
  verdict names, with their control and format characters escaped, each
  clipped at 180 characters.
- fix: the onboarding dialogs show an error's own text, when they have no
  plainer words for it, with its control characters escaped, clipped at 180
  characters.
- feat: `package:at_client_flutter/testing.dart` re-exports at_client's
  experimental `TestEnvelopeSigner`, for tests that verify signed envelopes.
- fix: a keychain entry that is not valid JSON is reported as
  `AtKeysFormatException`, as a keyfile is: its `reason` and `position`, and
  none of the entry's text.
- fix: on Windows, a keychain read logs the store name and the length of
  what it read, never the text.
- fix: on Windows, reading a keychain entry whose header's segment count is
  missing, not a whole number or out of range, legacy headers included, throws
  `AtKeysFormatException`.
- fix: `KeychainStorage.removeAtsignFromKeychain` and
  `appendAtKeysToKeychain` throw, changing nothing, when they cannot read the
  keychain (or its legacy-named store, when the keychain holds nothing under
  its current name) or its entry is not a JSON object, and throw a write that
  fails; `deleteAllAtKeysData` clears a keychain whose entry does not parse.
- fix: on Windows, a keychain write of keys that fails partway is undone
  before it is thrown, so the keychain reads back as it did, unless undoing
  it fails too, which is logged.
- fix: on Windows, deleting the keychain deletes its entry's segments even
  when its header does not parse or a segment it names cannot be read, and
  rewriting it deletes the old header's segments that the new entry does not
  reuse; each stops at the first segment it cannot delete and logs that at
  severe.
- fix: reading the keychain throws when it holds nothing under its current
  name and its legacy-named store cannot be read, rather than reading as a
  keychain that holds no keys.
- fix: `AtsignFlows.activate` and `open` refuse a keychain whose entry is not
  JSON or not a JSON object, saying every Atsign stored there is affected.
- chore: requires at_client 4.1.0-rc.1 and at_auth 4.1.0-rc.1.
- feat: `KeychainAtKeysIo.describeSource` returns "this device's keychain".
- fix: `CramDialog` fails before sending anything when the keychain holds
  keys it cannot read.
- fix: `PkamDialog`, `CramDialog`, `ApkamActivationDialog` and
  `RegistrarCramDialog` say what failed: a keys problem, an atServer refusal
  in plain words, a server that could not be reached, or "Something went
  wrong with <Atsign>: <message>", never a stack trace.
- fix: `PkamDialog` tells the user in plain words to enroll the device again
  when its keys hold no credential, or only enrollments awaiting approval
  that it cannot wait on.
- fix: `ApkamActivationDialog` resumes the request its AtKeys store already
  holds, even one filed under another device or app name, naming the app and
  device the request records when either differs.
- fix: `AtsignFlows.resumeEnrollment`'s `app` and `device` are deprecated
  and ignored: it returns the AtKeys store's one pending request whatever app
  and device it was filed under.

## 2.0.0

- docs: [Upgrading to at_client 4.0](https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md) takes an app from at_client 3 to 4.
- breaking: `EnrollmentStore` is removed, as `EnrollmentData` was.
- feat: `package:at_client_flutter/at_client_flutter.dart` also re-exports the
  SQLite and in-memory stores and at_client's mixins (`AtClientInvitations`,
  `EnrollmentUpdater`), so an app needs no second SDK import.
- feat: `AtsignFlows` and `storageOrDefault` are exported: an app with its own
  UI activates, opens and enrolls with the dialogs' store, transport and
  atDirectory in one call, still passing any other option its `Atsign` verb
  takes, such as `provisioningBudget`, and a widget test can give a dialog
  its own `flows`.
- feat: an app catches a keyfile that is not valid JSON as
  `AtKeysFormatException` and shows its `reason` and `position`.
- feat: `EnrollmentRequestList` lists the approved enrollments below the
  pending requests, each showing whether its keys are anchored to the atSign's
  signing root.
- feat: `at_client_flutter.dart` re-exports `at_client_io.dart`, so an app
  importing it has `FileAtKeysIo`, `secureSocketLookUps` and
  `CacheableSecondaryAddressFinder`.
- fix: leaving `ApkamActivationDialog` while it waits for approval keeps the
  request, which the next show resumes without a passcode, and the atSign can
  be opened again afterwards. Its Cancel button abandons the request once the
  user confirms, and names the enrollment to ask the manager to deny.
- feat: `PkamDialog`, given keys that hold only an enrollment awaiting
  approval, waits for the approval and returns the client, rather than
  failing.
- build: requires `at_client` ^4.0.0.
- build: requires `at_persistence_secondary_server` ^5.4.0.
- chore(deps): at_utils ^4.0.0

## 2.0.0-rc6

- feat: a dialog given no storage opens Hive in the app's support directory,
  or under `preference.hiveStoragePath` while that is set. An app that kept its
  store anywhere else should pass it as `storage:` before at_client 4.0.
- fix: an app whose preference sets `isLocalStoreRequired` false must pass
  `storage:`, as at_client now refuses a client with no local storage;
  `ApkamActivationDialog` refuses such an app when it opens, before any
  enrollment request goes out.
- build: requires `at_client` ^3.15.0-rc7.

## 2.0.0-rc5

- fix: keychain writes made at the same moment no longer lose another
  atSign's keys, and `update` no longer fails or brings back an atSign
  removed meanwhile.

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

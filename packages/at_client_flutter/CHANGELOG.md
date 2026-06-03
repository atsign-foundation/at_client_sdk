# CHANGELOG

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
